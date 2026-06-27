import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../data/hive_chat_data_source.dart';
import '../models/chat_hive_model.dart';
import '../services/api_service_simple.dart';
import '../storage/storage_service.dart';
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

  bool _asBool(dynamic value) => ChatHiveModel.parseAttendanceGroup(value);

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.tryParse(value.toString());
  }

  Map<String, dynamic> _parseChatKey(String key) {
    final isAttendanceGroup = key.endsWith('true');
    final normalizedKey = isAttendanceGroup
        ? key.substring(0, key.length - 'true'.length)
        : key;
    final separatorIndex = normalizedKey.indexOf('_');

    if (separatorIndex == -1) {
      return {
        'type': 'user',
        'id': normalizedKey,
        'attendance_group': isAttendanceGroup,
      };
    }

    return {
      'type': normalizedKey.substring(0, separatorIndex),
      'id': normalizedKey.substring(separatorIndex + 1),
      'attendance_group': isAttendanceGroup,
    };
  }

  /// Called from splash via unawaited() — only when user is logged in.
  /// Fetches /api/users/chat-list and stores into Hive in background so
  /// HomeScreen reads from cache instantly with correct unread counts.
  static Future<void> preloadForSplash() async {
    try {
      final storage = StorageService();
      final token = await storage.getToken();
      final user = await storage.getUser();

      // Only run when authenticated
      if (token == null || user == null) {
        debugPrint('⏭️ SplashPreload: not logged in, skipping');
        return;
      }

      debugPrint('🚀 SplashPreload: background chat sync for user ${user.id}');

      final instance = ChatListSyncService();

      // Initialize Hive box for this user
      final hive = HiveChatDataSource();
      await hive.initialize(userId: user.id);

      // Initialize image cache
      final imageCache = ImageCacheService();
      await imageCache.initialize();

      // Set instance fields so syncFromApi works
      instance._hiveDataSource = hive;
      instance._imageCacheService = imageCache;
      instance._currentUserId = user.id;
      instance._isInitialized = true;

      // Call API
      final apiService = ApiService(Dio());
      apiService.setAuthToken(token);
      final response = await apiService.getChatList();
      if (response.isEmpty) return;

      final apiChats =
          response.map((e) => e as Map<String, dynamic>).toList();

      // Sync into Firebase + Hive (same pipeline as HomeScreen)
      await instance.syncFromApi(apiChats);

      debugPrint(
          '✅ SplashPreload: ${apiChats.length} chats cached — HomeScreen loads instantly');
    } catch (e) {
      // Never crash splash — this is best-effort background work
      debugPrint('⚠️ SplashPreload error (non-fatal): $e');
    }
  }

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
        final chatType = apiChat['type']?.toString() ?? 'user';
        final attendanceGroup = _asBool(apiChat['attendance_group']);
        final key = ChatHiveModel.buildKey(
          id: chatId,
          type: chatType,
          attendanceGroup: attendanceGroup,
        );

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
          'member_count': hiveChat.memberCount,
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

    final key = ChatHiveModel.buildKey(
      id: chatId,
      type: chatType,
      attendanceGroup: attendanceGroup,
    );
    debugPrint('📬 Updating chat $key with new message');

    try {
      // Read current unread count from Hive first
      final existing = _hiveDataSource.getChatById(chatId, chatType, attendanceGroup);
      final newUnread = incrementUnread
          ? (existing?.unreadCount ?? 0) + 1
          : (existing?.unreadCount ?? 0);

      // Update Hive first (source of truth for UI)
      await _hiveDataSource.updateChatLastMessage(
        chatId: chatId,
        chatType: chatType,
        lastMessage: lastMessage,
        attendanceGroup: attendanceGroup,
        lastMessageTime: lastMessageTime,
        incrementUnread: incrementUnread,
      );
      debugPrint('✅ Hive: Updated $key unread=$newUnread');

      // Update Firebase WITH unread_count so _handleFirebaseUpdate
      // never reverts the incremented count back to 0
      await _chatListRef.child(_currentUserId!).child(key).update({
        'last_message': lastMessage,
        'last_message_time': lastMessageTime.millisecondsSinceEpoch,
        'last_message_time_iso': lastMessageTime.toIso8601String(),
        'sort_time': lastMessageTime.millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'unread_count': newUnread, // keep Firebase in sync with Hive
        if (senderId != null) 'last_sender_id': senderId,
        if (senderName != null) 'last_sender_name': senderName,
      });
      debugPrint('✅ Firebase: Updated $key unread=$newUnread');
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
      final parsedKey = _parseChatKey(key);
      final chatId = chatData['id']?.toString() ?? parsedKey['id']?.toString();
      final chatType =
          chatData['type']?.toString() ?? parsedKey['type']?.toString();
      final attendanceGroup = _asBool(
        chatData['attendance_group'] ?? parsedKey['attendance_group'],
      );

      if (chatId == null || chatType == null) return;

      debugPrint('🔥 Firebase update detected for $key');
//
      // Get existing chat from Hive
      final existingChat = _hiveDataSource.getChatById(
        chatId,
        chatType,
        attendanceGroup,
      );

      if (existingChat != null) {
        // Update existing chat
        final lastMsgTime =
            _asDateTime(chatData['last_message_time']) ??
                _asDateTime(chatData['last_message_time_iso']) ??
                existingChat.lastMessageTime;

        final sortTime = _asDateTime(chatData['sort_time']) ?? lastMsgTime;

        // Never overwrite a higher local unread count with a lower Firebase value.
        // Local Hive is the source of truth for unread badge.
        final firebaseUnread = _asInt(chatData['unread_count'], fallback: existingChat.unreadCount);
        final localUnread = existingChat.unreadCount;
        final resolvedUnread = firebaseUnread > localUnread ? firebaseUnread : localUnread;

        final updated = ChatHiveModel(
          id: chatId,
          type: chatType,
          name: chatData['name']?.toString() ?? existingChat.name,
          profilePicture:
              chatData['profile_picture']?.toString() ?? existingChat.profilePicture,
          localImagePath: existingChat.localImagePath,
          lastMessage:
              chatData['last_message']?.toString() ?? existingChat.lastMessage,
          lastMessageTime: lastMsgTime,
          unreadCount: resolvedUnread,
          isPinned: chatData.containsKey('is_pinned')
              ? _asBool(chatData['is_pinned'])
              : existingChat.isPinned,
          attendanceGroup: attendanceGroup,
          actualRole:
              chatData['actual_role']?.toString() ?? existingChat.actualRole,
          createdAt: existingChat.createdAt,
          updatedAt: DateTime.now(),
          lastReadAt: existingChat.lastReadAt,
          memberCount: chatData['member_count'] != null
              ? _asInt(chatData['member_count'])
              : existingChat.memberCount,
          groupType:
              chatData['group_type']?.toString() ?? existingChat.groupType,
          role: chatData['role']?.toString() ?? existingChat.role,
          mobile: chatData['mobile']?.toString() ?? existingChat.mobile,
          className:
              chatData['class_name']?.toString() ?? existingChat.className,
          sectionName:
              chatData['section_name']?.toString() ?? existingChat.sectionName,
          sortTime: sortTime,
        );

        await _hiveDataSource.upsertChat(updated);
        debugPrint('⬆️ Chat $key moved to top with sortTime: $sortTime');
      } else {
        // Create new chat entry
        final lastMsgTime =
            _asDateTime(chatData['last_message_time']) ??
                _asDateTime(chatData['last_message_time_iso']) ??
                DateTime.now();

        final sortTime = _asDateTime(chatData['sort_time']) ?? lastMsgTime;

        // Download profile image if available
        String? localImagePath;
        final imageUrl = chatData['profile_picture'];
        if (imageUrl != null && imageUrl.toString().isNotEmpty) {
          localImagePath = await _imageCacheService.downloadAndCache(imageUrl);
        }

        final newChat = ChatHiveModel(
          id: chatId,
          type: chatType,
          name: chatData['name']?.toString() ?? 'Unknown',
          profilePicture: chatData['profile_picture']?.toString(),
          localImagePath: localImagePath,
          lastMessage: chatData['last_message']?.toString(),
          lastMessageTime: lastMsgTime,
          unreadCount: _asInt(chatData['unread_count']),
          isPinned: _asBool(chatData['is_pinned']),
          attendanceGroup: attendanceGroup,
          actualRole: chatData['actual_role']?.toString(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          memberCount: chatData['member_count'] != null
              ? _asInt(chatData['member_count'])
              : null,
          groupType: chatData['group_type']?.toString(),
          role: chatData['role']?.toString(),
          mobile: chatData['mobile']?.toString(),
          className: chatData['class_name']?.toString(),
          sectionName: chatData['section_name']?.toString(),
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

    final attendanceGroup = _asBool(attendance_group);
    final key = ChatHiveModel.buildKey(
      id: chatId,
      type: chatType,
      attendanceGroup: attendanceGroup,
    );
    try {
      // Update Firebase
      await _chatListRef.child(_currentUserId!).child(key).update({
        'unread_count': 0,
        'last_read_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Update Hive
      await _hiveDataSource.updateUnreadCount(
        chatId,
        chatType,
        0,
        attendanceGroup,
      );
      
      debugPrint('✅ Marked $key as read');
    } catch (e) {
      debugPrint('❌ Failed to mark $key as read: $e');
    }
  }

  /// Toggle pin status
  Future<void> togglePin(
    String chatId,
    String chatType,
    bool isPinned, {
    bool attendanceGroup = false,
  }) async {
    if (!_isInitialized || _currentUserId == null) return;

    final key = ChatHiveModel.buildKey(
      id: chatId,
      type: chatType,
      attendanceGroup: attendanceGroup,
    );
    
    try {
      // Update Firebase
      await _chatListRef.child(_currentUserId!).child(key).update({
        'is_pinned': isPinned,
      });

      // Update Hive
      await _hiveDataSource.togglePinChat(
        chatId,
        chatType,
        isPinned,
        attendanceGroup: attendanceGroup,
      );
      
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
