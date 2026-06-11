import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../data/hive_chat_data_source.dart';
import '../models/chat_hive_model.dart';
import 'image_cache_service.dart';

/// Comprehensive chat list synchronization service
/// Handles API → Firebase → Hive sync pipeline with real-time updates
class ChatListSyncService {
  static final ChatListSyncService _instance = ChatListSyncService._internal();
  factory ChatListSyncService() => _instance;
  ChatListSyncService._internal();

  final DatabaseReference _chatListRef = FirebaseDatabase.instance.ref('chat_list');
  late final HiveChatDataSource _hiveDataSource;
  late final ImageCacheService _imageCacheService;
  
  final Map<String, StreamSubscription> _activeListeners = {};
  bool _isInitialized = false;
  String? _currentUserId;

  /// Initialize service with user ID
  Future<void> initialize(String userId) async {
    if (_isInitialized && _currentUserId == userId) return;
    
    _currentUserId = userId;
    _hiveDataSource = HiveChatDataSource(); // Singleton instance
    _imageCacheService = ImageCacheService(); // Singleton instance
    
    await _hiveDataSource.initialize();
    await _imageCacheService.initialize();
    _isInitialized = true;
    
    debugPrint('✅ ChatListSyncService initialized for user: $userId');
  }

  /// Step 1: Store API chat list to both Firebase and Hive
  Future<void> syncFromApi(List<Map<String, dynamic>> apiChats) async {
    if (!_isInitialized || _currentUserId == null) {
      debugPrint('⚠️ ChatListSyncService not initialized');
      return;
    }

    debugPrint('🔄 Starting API → Firebase + Hive sync (${apiChats.length} chats)');
    
    final List<ChatHiveModel> hiveChats = [];
    final Map<String, dynamic> firebaseUpdates = {};

    for (final apiChat in apiChats) {
      try {
        final chatId = apiChat['id'].toString();
        final chatType = apiChat['type'] ?? 'user';
        final attendance_group = apiChat['attendance_group'] ?? false;

        // final key = '${chatType}_$chatId';
        final key = attendance_group ==false ? '${chatType}_$chatId' : '${chatType}_$chatId$attendance_group' ;

        // Download and cache profile image
        String? localImagePath;
        final imageUrl = apiChat['profile_picture'];
        if (imageUrl != null && imageUrl.toString().isNotEmpty) {
          localImagePath = await _imageCacheService.downloadAndCache(imageUrl);
        }

        // Create Hive model
        final hiveChat = ChatHiveModel.fromApi(apiChat, localImagePath: localImagePath);
        hiveChats.add(hiveChat);

        // Prepare Firebase data
        final lastMsgTime = hiveChat.lastMessageTime ?? hiveChat.updatedAt;
        firebaseUpdates['$_currentUserId/$key'] = {
          'id': chatId,
          'type': chatType,
          'name': hiveChat.name,
          'profile_picture': hiveChat.profilePicture,
          'last_message': hiveChat.lastMessage,
          'last_message_time': lastMsgTime.millisecondsSinceEpoch,
          'last_message_time_iso': lastMsgTime.toIso8601String(),
          'unread_count': hiveChat.unreadCount,
          'is_pinned': hiveChat.isPinned,
          'attendance_group': hiveChat.attendanceGroup,
          'actual_role': hiveChat.actualRole,
          'group_type': hiveChat.groupType,
          'role': hiveChat.role,
          'mobile': hiveChat.mobile,
          'class_name': hiveChat.className,
          'section_name': hiveChat.sectionName,
          'sort_time': (hiveChat.sortTime ?? lastMsgTime).millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        };
      } catch (e) {
        debugPrint('⚠️ Failed to process chat ${apiChat['id']}: $e');
      }
    }

    // Batch update Firebase
    if (firebaseUpdates.isNotEmpty) {
      try {
        await _chatListRef.update(firebaseUpdates);
        debugPrint('✅ Firebase: Saved ${firebaseUpdates.length} chats');
      } catch (e) {
        debugPrint('❌ Firebase batch update failed: $e');
      }
    }

    // Batch save to Hive
    if (hiveChats.isNotEmpty) {
      final stats = await _hiveDataSource.saveChatsBatch(hiveChats);
      debugPrint('✅ Hive: ${stats['added']} added, ${stats['updated']} updated');
    }

    // Start real-time listeners for all chats
    _startRealtimeListeners();
  }

  /// Step 2: Update chat when new message sent/received
  Future<void> updateChatOnMessage({
    required String chatId,
    required String chatType,
    required String lastMessage,
    required bool attendanceGroup,
    required DateTime lastMessageTime,
    String? senderId,
    String? senderName,
    bool incrementUnread = false,
  }) async {
    if (!_isInitialized || _currentUserId == null) return;

    final key = attendanceGroup ==false ? '${chatType}_$chatId' : '${chatType}_$chatId$attendanceGroup' ;
    debugPrint('📬 Updating chat $key with new message');

    try {
      // Update Firebase
      await _chatListRef.child(_currentUserId!).child(key).update({
        'last_message': lastMessage,
        'last_message_time': lastMessageTime.millisecondsSinceEpoch,
        'last_message_time_iso': lastMessageTime.toIso8601String(),
        'sort_time': lastMessageTime.millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        if (senderId != null) 'last_sender_id': senderId,
        if (senderName != null) 'last_sender_name': senderName,
      });
      debugPrint('✅ Firebase: Updated $key');

      // Update Hive (with unread increment if needed)
      await _hiveDataSource.updateChatLastMessage(
        chatId: chatId,
        chatType: chatType,
        lastMessage: lastMessage,
        attendanceGroup: attendanceGroup,
        lastMessageTime: lastMessageTime,
        incrementUnread: incrementUnread,
      );
      debugPrint('✅ Hive: Updated $key');
    } catch (e) {
      debugPrint('❌ Failed to update chat $key: $e');
    }
  }

  /// Step 3: Start real-time Firebase listeners
  void _startRealtimeListeners() {
    if (_currentUserId == null) return;

    // Cancel existing listeners
    _stopRealtimeListeners();

    // Listen to all chats under current user
    final listener = _chatListRef.child(_currentUserId!).onChildChanged.listen((event) {
      _handleFirebaseUpdate(event);
    });

    _activeListeners['main'] = listener;
    debugPrint('👂 Started Firebase real-time listener for user: $_currentUserId');
  }

  /// Handle Firebase real-time updates
  void _handleFirebaseUpdate(DatabaseEvent event) async {
    try {
      final key = event.snapshot.key;
      if (key == null) return;

      final data = event.snapshot.value as Map?;
      if (data == null) return;

      final chatData = Map<String, dynamic>.from(data);
      final chatId = chatData['id']?.toString();
      final chatType = chatData['type']?.toString();
      final attendanceGroup = chatData['attendance_group'];

      if (chatId == null || chatType == null) return;

      debugPrint('🔥 Firebase update detected for $key');
//
      // Get existing chat from Hive
      final existingChat = _hiveDataSource.getChatById(chatId,chatType,attendanceGroup);

      if (existingChat != null) {
        // Update existing chat
        final lastMsgTime = chatData['last_message_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(chatData['last_message_time'])
            : existingChat.lastMessageTime;

        final sortTime = chatData['sort_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(chatData['sort_time'])
            : lastMsgTime;

        final updated = ChatHiveModel(
          id: chatId,
          type: chatType,
          name: chatData['name'] ?? existingChat.name,
          profilePicture: chatData['profile_picture'] ?? existingChat.profilePicture,
          localImagePath: existingChat.localImagePath,
          lastMessage: chatData['last_message'] ?? existingChat.lastMessage,
          lastMessageTime: lastMsgTime,
          unreadCount: chatData['unread_count'] ?? existingChat.unreadCount,
          isPinned: chatData['is_pinned'] ?? existingChat.isPinned,
          attendanceGroup: chatData['attendance_group'] ?? existingChat.attendanceGroup,
          actualRole: chatData['actual_role'] ?? existingChat.actualRole,
          createdAt: existingChat.createdAt,
          updatedAt: DateTime.now(),
          lastReadAt: existingChat.lastReadAt,
          memberCount: chatData['member_count'] ?? existingChat.memberCount,
          groupType: chatData['group_type'] ?? existingChat.groupType,
          role: chatData['role'] ?? existingChat.role,
          mobile: chatData['mobile'] ?? existingChat.mobile,
          className: chatData['class_name'] ?? existingChat.className,
          sectionName: chatData['section_name'] ?? existingChat.sectionName,
          sortTime: sortTime,
        );

        await _hiveDataSource.upsertChat(updated);
        debugPrint('⬆️ Chat $key moved to top with sortTime: $sortTime');
      } else {
        // Create new chat entry
        final lastMsgTime = chatData['last_message_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(chatData['last_message_time'])
            : DateTime.now();

        final sortTime = chatData['sort_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(chatData['sort_time'])
            : lastMsgTime;

        // Download profile image if available
        String? localImagePath;
        final imageUrl = chatData['profile_picture'];
        if (imageUrl != null && imageUrl.toString().isNotEmpty) {
          localImagePath = await _imageCacheService.downloadAndCache(imageUrl);
        }

        final newChat = ChatHiveModel(
          id: chatId,
          type: chatType,
          name: chatData['name'] ?? 'Unknown',
          profilePicture: chatData['profile_picture'],
          localImagePath: localImagePath,
          lastMessage: chatData['last_message'],
          lastMessageTime: lastMsgTime,
          unreadCount: chatData['unread_count'] ?? 0,
          isPinned: chatData['is_pinned'] ?? false,
          attendanceGroup: chatData['attendance_group'],
          actualRole: chatData['actual_role'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          groupType: chatData['group_type'],
          role: chatData['role'],
          mobile: chatData['mobile'],
          className: chatData['class_name'],
          sectionName: chatData['section_name'],
          sortTime: sortTime,
        );

        await _hiveDataSource.upsertChat(newChat);
        debugPrint('➕ New chat $key created with sortTime: $sortTime');
      }
    } catch (e) {
      debugPrint('❌ Error handling Firebase update: $e');
    }
  }

  /// Stop real-time listeners
  void _stopRealtimeListeners() {
    for (final subscription in _activeListeners.values) {
      subscription.cancel();
    }
    _activeListeners.clear();
    debugPrint('🛑 Stopped all Firebase listeners');
  }

  /// Get sorted chat list from Hive (UI consumes this)
  List<ChatHiveModel> getSortedChatList() {
    return _hiveDataSource.getAllChats();
  }

  /// Watch chat list changes for real-time UI updates
  Stream<List<ChatHiveModel>> watchChatList() {
    return _hiveDataSource.watchAllChats();
  }

  /// Mark chat as read (updates both Firebase and Hive)
  Future<void> markAsRead(String chatId, String chatType, bool attendance_group) async {
    if (!_isInitialized || _currentUserId == null) return;

    // final key = '${chatType}_$chatId';
    final key = attendance_group ==false ? '${chatType}_$chatId' : '${chatType}_$chatId$attendance_group' ;
    try {
      // Update Firebase
      await _chatListRef.child(_currentUserId!).child(key).update({
        'unread_count': 0,
        'last_read_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Update Hive
      await _hiveDataSource.updateUnreadCount(chatId, chatType, 0,attendance_group ??false);
      
      debugPrint('✅ Marked $key as read');
    } catch (e) {
      debugPrint('❌ Failed to mark $key as read: $e');
    }
  }

  /// Toggle pin status
  Future<void> togglePin(String chatId, String chatType, bool isPinned) async {
    if (!_isInitialized || _currentUserId == null) return;

    final key = '${chatType}_$chatId';
    
    try {
      // Update Firebase
      await _chatListRef.child(_currentUserId!).child(key).update({
        'is_pinned': isPinned,
      });

      // Update Hive
      await _hiveDataSource.togglePinChat(chatId, chatType, isPinned);
      
      debugPrint('📌 ${isPinned ? 'Pinned' : 'Unpinned'} $key');
    } catch (e) {
      debugPrint('❌ Failed to toggle pin $key: $e');
    }
  }

  /// Dispose service
  void dispose() {
    _stopRealtimeListeners();
    _isInitialized = false;
    _currentUserId = null;
    debugPrint('🗑️ ChatListSyncService disposed');
  }
}
