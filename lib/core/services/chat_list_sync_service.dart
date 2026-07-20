import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../data/hive_chat_data_source.dart';
import '../models/chat_hive_model.dart';
import '../services/api_service_simple.dart';
import '../storage/storage_service.dart';
import '../utils/chat_utils.dart';
import '../models/message_model.dart' show statusKey;
import 'active_chat_tracker.dart';
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
  // Per-chat message listeners for real-time unread badge updates
  final Map<String, StreamSubscription> _messageListeners = {};
  // Track latest known message timestamp per chat to skip old messages on re-subscribe
  final Map<String, int> _latestMessageTimestamp = {};
  // Tracks timestamps of chat_list writes we made ourselves to avoid echo in _handleFirebaseUpdate
  // Value is the epoch-ms written as updated_at; we match with a ±50ms tolerance window.
  final Map<String, int> _ownWriteTimestamps = {};

  // Callback registered by OptimizedChatNotifier so Hive-write paths that
  // bypass watchAllChats can still push state updates synchronously.
  void Function(List<ChatHiveModel>)? _onChatsUpdated;
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
  /// Register a callback that fires after every unread-count / last-message
  /// Hive write so the provider state updates immediately without relying solely
  /// on the Hive watch stream (which can have a microtask delay).
  void setOnChatsUpdated(void Function(List<ChatHiveModel>) callback) {
    _onChatsUpdated = callback;
  }

  void _notifyProvider() {
    final cb = _onChatsUpdated;
    if (cb == null) return;
    cb(_hiveDataSource.getAllChats());
  }

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

        // Preserve local lastReadAt in Firebase so other devices can also
        // respect the read state. Never overwrite a newer local lastReadAt.
        final existingLocal =
            _hiveDataSource.getChatById(chatId, chatType, attendanceGroup);
        final localReadAtMs = existingLocal?.lastReadAt?.millisecondsSinceEpoch;

        // Create Hive model
        final hiveChat =
            ChatHiveModel.fromApi(apiChat, localImagePath: localImagePath);
        hiveChats.add(hiveChat);

        // Resolve unread count before writing to Firebase:
        // if user already read this chat (lastReadAt >= lastMessageTime), keep 0.
        // This prevents Firebase from storing a stale API count that would be
        // echoed back and restore the badge on the next sync/app-resume.
        final lastMsgTime = hiveChat.lastMessageTime ?? hiveChat.updatedAt;
        final localReadAt = existingLocal?.lastReadAt;
        final resolvedUnread = (localReadAt != null &&
                !localReadAt.isBefore(lastMsgTime))
            ? 0
            : hiveChat.unreadCount;

        firebaseUpdates['$_currentUserId/$key'] = {
          'id': chatId,
          'type': chatType,
          'name': hiveChat.name,
          'profile_picture': hiveChat.profilePicture,
          'last_message': hiveChat.lastMessage,
          'last_message_time': lastMsgTime.millisecondsSinceEpoch,
          'last_message_time_iso': lastMsgTime.toIso8601String(),
          'unread_count': resolvedUnread,
          'is_pinned': hiveChat.isPinned,
          'attendance_group': hiveChat.attendanceGroup,
          'actual_role': hiveChat.actualRole,
          'member_count': hiveChat.memberCount,
          'group_type': hiveChat.groupType,
          'role': hiveChat.role,
          'mobile': hiveChat.mobile,
          'class_name': hiveChat.className,
          'section_name': hiveChat.sectionName,
          'sort_time':
              (hiveChat.sortTime ?? lastMsgTime).millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          // Preserve local read timestamp so cross-device read state is not lost
          if (localReadAtMs != null) 'last_read_at': localReadAtMs,
        };
      } catch (e) {
        debugPrint('⚠️ Failed to process chat ${apiChat['id']}: $e');
      }
    }

    // Batch update Firebase
    if (firebaseUpdates.isNotEmpty) {
      try {
        // Mark all keys as own-writes BEFORE the batch update so the
        // Firebase onChildChanged echo is suppressed for every chat.
        // Without this, _handleFirebaseUpdate re-writes Hive from stale
        // Firebase data (including old sort_time) right after saveChatsBatch,
        // causing attendance_group chats to reorder chaotically.
        final batchWriteTs = DateTime.now().millisecondsSinceEpoch;
        for (final fbKey in firebaseUpdates.keys) {
          // fbKey is "userId/chatKey" — extract just the chatKey part
          final chatKey = fbKey.contains('/') ? fbKey.split('/').last : fbKey;
          _ownWriteTimestamps[chatKey] = batchWriteTs;
        }
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
    // Start per-chat message listeners for real-time unread badge updates
    _startMessageListeners(hiveChats);
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

      // Notify provider immediately so HomeScreen rebuilds without waiting for
      // the Hive watch stream microtask.
      _notifyProvider();

      // Mark this Firebase write as ours so _handleFirebaseUpdate skips the echo.
      final writeTs = DateTime.now().millisecondsSinceEpoch;
      _ownWriteTimestamps[key] = writeTs;

      // Update Firebase WITH unread_count so _handleFirebaseUpdate
      // never reverts the incremented count back to 0
      unawaited(_chatListRef.child(_currentUserId!).child(key).update({
        'last_message': lastMessage,
        'last_message_time': lastMessageTime.millisecondsSinceEpoch,
        'last_message_time_iso': lastMessageTime.toIso8601String(),
        'sort_time': lastMessageTime.millisecondsSinceEpoch,
        'updated_at': writeTs,
        'unread_count': newUnread, // keep Firebase in sync with Hive
        if (senderId != null) 'last_sender_id': senderId,
        if (senderName != null) 'last_sender_name': senderName,
      }));
      debugPrint('✅ Firebase: Updated $key unread=$newUnread (own-write marked)');
    } catch (e) {
      debugPrint('❌ Failed to update chat $key: $e');
    }
  }

  /// Step 3: Start real-time Firebase listeners
  void _startRealtimeListeners() {
    if (_currentUserId == null) return;

    // Cancel existing listeners
    _stopRealtimeListeners();

    // onChildChanged: fires when an existing chat entry is updated (last message,
    // unread count, sort_time). Covers ~95% of all real-time events.
    final changedListener = _chatListRef.child(_currentUserId!).onChildChanged.listen((event) {
      _handleFirebaseUpdate(event);
    });
    _activeListeners['changed'] = changedListener;

    // onChildAdded: fires for brand-new chats added by other devices / server.
    // Without this, a new group created on another device never appears here.
    // Skip the initial seed burst by checking if the chat already exists in Hive
    // — onChildChanged handles all updates for pre-existing chats.
    final addedListener = _chatListRef.child(_currentUserId!).onChildAdded.listen((event) {
      final key = event.snapshot.key;
      if (key == null) return;
      final parsed = _parseChatKey(key);
      final chatId = parsed['id']?.toString();
      final chatType = parsed['type']?.toString();
      final attendance = _asBool(parsed['attendance_group']);
      if (chatId == null || chatType == null) return;
      // Already in Hive — skip, onChildChanged handles updates
      if (_hiveDataSource.getChatById(chatId, chatType, attendance) != null) return;
      _handleFirebaseUpdate(event);
    });
    _activeListeners['added'] = addedListener;

    debugPrint('👂 Started Firebase real-time listeners (added+changed) for user: $_currentUserId');
  }

  /// Start per-chat message listeners so new messages from other users
  /// immediately increment the unread badge on HomeScreen without FCM.
  /// BANDWIDTH OPTIMIZATION: Only subscribe to chats with recent activity
  /// (last 24h) or unread messages. Other chats are subscribed lazily when
  /// the user opens them. This prevents N simultaneous Firebase connections
  /// for users with hundreds of chats.
  void _startMessageListeners(List<ChatHiveModel> chats) {
    if (_currentUserId == null) return;

    // Priority 1: chats with unread messages (must always be subscribed)
    // Priority 2: chats active in the last 24 hours (likely to receive messages)
    // Everything else: skip — subscribe lazily when user opens the chat
    final now = DateTime.now();
    final activeChats = chats.where((chat) {
      if (chat.unreadCount > 0) return true;
      final lastActivity = chat.sortTime ?? chat.lastMessageTime ?? chat.updatedAt;
      return now.difference(lastActivity).inHours < 24;
    }).take(20).toList(); // hard cap at 20 simultaneous listeners

    for (final chat in activeChats) {
      _subscribeToChat(chat);
    }
    debugPrint('👂 Started message listeners for ${activeChats.length}/${chats.length} active chats');
  }

  /// Subscribe to a single chat's messages node for real-time unread updates.
  void _subscribeToChat(ChatHiveModel chat) {
    if (_currentUserId == null) return;

    // Resolve attendanceGroup — treat null as false for regular groups
    final isAttendance = chat.attendanceGroup == true;

    // For private chats: otherUserId is the other user's ID (chat.id).
    // Ensure it is never the same as _currentUserId to avoid a self-chat path.
    // If chat.id equals _currentUserId (edge case from stale data), skip subscription.
    final isPrivate = chat.type != 'group';
    if (isPrivate && chat.id == _currentUserId) {
      // Re-check: if the chat name differs from the current user's own name,
      // this is a valid chat that happens to share the same ID (data anomaly).
      // Only skip if it is truly a self-referencing entry with no real peer.
      // We detect this by checking whether the Firebase path would be
      // 'private_X_X' (same ID on both sides), which is always invalid.
      final testPath = ChatUtils.generateChatId(
        chat.id,
        chatType: chat.type,
        currentUserId: _currentUserId,
        otherUserId: chat.id,
      );
      if (testPath.contains('${_currentUserId}_$_currentUserId')) {
        debugPrint('⚠️ [ChatListSync] Skipping self-chat subscription for ${chat.id}');
        return;
      }
      // Otherwise fall through — the IDs match but the Firebase path is valid
      // (e.g. sorted IDs produce a different path). This covers the edge case
      // where User 1 and User 3 have low numeric IDs that sort unexpectedly.
    }

    final firebaseChatId = ChatUtils.generateChatId(
      chat.id,
      chatType: chat.type,
      attendanceGroup: isAttendance,
      currentUserId: _currentUserId,
      otherUserId: isPrivate ? chat.id : '0',
    );

    // Cancel existing listener for this chat before re-subscribing
    _messageListeners[firebaseChatId]?.cancel();

    // Seed: advance cursor only — never retreat it to avoid re-counting old messages.
    // Use the chat's known last-message time as the lower bound.
    // We do NOT use nowMs as the seed because it would miss messages sent in the
    // brief window between app start and subscription setup (causing phantom 0 unread).
    // Instead seed at chatSeedMs so only messages strictly newer than the last
    // known message are counted as new arrivals.
    final chatSeedMs = (chat.sortTime ?? chat.lastMessageTime ?? chat.updatedAt)
        .millisecondsSinceEpoch;
    final existing = _latestMessageTimestamp[firebaseChatId];
    if (existing == null) {
      // First subscription: seed at chatSeedMs so pre-existing messages are skipped
      // but messages arriving after the last known message are counted.
      _latestMessageTimestamp[firebaseChatId] = chatSeedMs;
    } else if (chatSeedMs > existing) {
      // Subsequent re-subscribe: only advance the cursor, never retreat.
      _latestMessageTimestamp[firebaseChatId] = chatSeedMs;
    }
    final seedMs = _latestMessageTimestamp[firebaseChatId]!;

    // Always use startAfter(seedMs) — seedMs is always > 0 now, so we never
    // fall back to limitToLast(1) which was the source of the phantom +1 unread.
    final query = FirebaseDatabase.instance
        .ref('chats/$firebaseChatId/messages')
        .orderByChild('timestamp')
        .startAfter(seedMs);

    final sub = query.onChildAdded
        .listen((event) => _handleNewMessage(event, chat.id, chat.type, isAttendance, firebaseChatId));

    _messageListeners[firebaseChatId] = sub;
  }

  /// Handle a new message event: increment unread if sender ≠ current user.
  void _handleNewMessage(
    DatabaseEvent event,
    String chatId,
    String chatType,
    bool attendanceGroup,
    String firebaseChatId,
  ) async {
    try {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return;

      final msgData = Map<String, dynamic>.from(data);
      final senderId = msgData['senderId']?.toString() ??
          msgData['sender_id']?.toString() ?? '';
      final msgTimestamp = _asInt(msgData['timestamp']);

      // Advance cursor — never retreat it.
      final prevTs = _latestMessageTimestamp[firebaseChatId] ?? 0;
      if (msgTimestamp > prevTs) {
        _latestMessageTimestamp[firebaseChatId] = msgTimestamp;
      }

      // Drop any message that is not genuinely newer than our subscription
      // cursor. startAfter(seedMs) should already exclude these, but Firebase
      // can occasionally deliver the boundary item; this guard is the safety net.
      if (msgTimestamp > 0 && msgTimestamp <= prevTs) {
        debugPrint('⏭️ [ChatListSync] Skip non-new msg ts=$msgTimestamp (cursor=$prevTs) for $firebaseChatId');
        return;
      }

      // Only process messages from OTHER users
      if (senderId.isEmpty || senderId == _currentUserId) return;

      final messageText = msgData['text']?.toString() ??
          msgData['content']?.toString() ??
          msgData['message']?.toString() ?? '';
      final messageTime = msgTimestamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(msgTimestamp)
          : DateTime.now();

      // Write delivered status to Firebase so the sender sees double grey tick.
      // This fires as soon as the message reaches this device (app foreground).
      // Only write if current status is 'sent' — never downgrade from 'read'.
      final messageKey = event.snapshot.key;
      if (messageKey != null && messageKey.isNotEmpty) {
        final currentStatus = msgData['status'];
        // Check both prefixed and raw key for backward compatibility
        final receiverStatus = currentStatus is Map
            ? (currentStatus[statusKey(_currentUserId!)] ??
                currentStatus[_currentUserId])?.toString()
            : null;
        if (receiverStatus == null || receiverStatus == 'sent') {
          unawaited(FirebaseDatabase.instance
              .ref('chats/$firebaseChatId/messages/$messageKey/status/${statusKey(_currentUserId!)}')
              .set('delivered'));
          debugPrint('✅ [Delivered] Set delivered for msg $messageKey in $firebaseChatId');
        }
      }

      // Always read the CURRENT state from Hive with the resolved attendanceGroup
      // so we use the right key and never use stale closure data.
      final current = _hiveDataSource.getChatById(chatId, chatType, attendanceGroup);
      if (current == null) {
        debugPrint('⚠️ [ChatListSync] Chat $chatId/$chatType/$attendanceGroup not in Hive — skip');
        return;
      }

      final key = ChatHiveModel.buildKey(
        id: current.id,
        type: current.type,
        attendanceGroup: attendanceGroup,
      );
      final writeTs = DateTime.now().millisecondsSinceEpoch;

      // If the user is currently viewing this chat, mark it as read immediately
      // instead of incrementing the badge — the message is already visible.
      if (ActiveChatTracker.isChatActive(chatId)) {
        debugPrint('👁️ [ChatListSync] User is viewing $chatId — marking as read, no badge increment');

        // Keep unread at 0 and stamp lastReadAt so saveChatsBatch never restores the badge.
        await _hiveDataSource.updateUnreadCount(chatId, chatType, 0, attendanceGroup);
        // Also update last message text/time so the chat tile stays current.
        await _hiveDataSource.updateChatLastMessage(
          chatId: current.id,
          chatType: current.type,
          lastMessage: messageText.isNotEmpty ? messageText : (current.lastMessage ?? ''),
          attendanceGroup: attendanceGroup,
          lastMessageTime: messageTime,
          incrementUnread: false,
        );
        _notifyProvider();

        // Advance the cursor so this message is never re-counted on reconnect.
        _latestMessageTimestamp[firebaseChatId] = writeTs;

        // Persist read state to Firebase so other devices respect it.
        _ownWriteTimestamps[key] = writeTs;
        unawaited(_chatListRef.child(_currentUserId!).child(key).update({
          'last_message': messageText,
          'last_message_time': messageTime.millisecondsSinceEpoch,
          'sort_time': messageTime.millisecondsSinceEpoch,
          'unread_count': 0,
          'last_read_at': writeTs,
          'updated_at': writeTs,
        }));
        unawaited(FirebaseDatabase.instance
            .ref('read_receipts/$key/$_currentUserId')
            .set({'read_at': writeTs}));
        return;
      }

      debugPrint('🔔 [ChatListSync] New msg in $chatId from $senderId — incrementing unread');

      // User is NOT viewing this chat — increment the badge normally.
      await _hiveDataSource.updateChatLastMessage(
        chatId: current.id,
        chatType: current.type,
        lastMessage: messageText.isNotEmpty ? messageText : (current.lastMessage ?? ''),
        attendanceGroup: attendanceGroup,
        lastMessageTime: messageTime,
        incrementUnread: true,
      );

      // Read back the confirmed new count
      final afterUpdate = _hiveDataSource.getChatById(chatId, chatType, attendanceGroup);
      final newUnread = afterUpdate?.unreadCount ?? (current.unreadCount + 1);

      // Notify provider immediately — HomeScreen badge updates without any stream delay
      _notifyProvider();

      // Mark this Firebase chat_list write as ours so _handleFirebaseUpdate
      // skips the echo and doesn't revert the incremented count.
      _ownWriteTimestamps[key] = writeTs;

      unawaited(_chatListRef.child(_currentUserId!).child(key).update({
        'last_message': messageText,
        'last_message_time': messageTime.millisecondsSinceEpoch,
        'sort_time': messageTime.millisecondsSinceEpoch,
        'unread_count': newUnread,
        'updated_at': writeTs,
      }));

      debugPrint('✅ [ChatListSync] Badge +1 for $chatId: unread=$newUnread');
    } catch (e) {
      debugPrint('❌ [ChatListSync] _handleNewMessage error: $e');
    }
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

      // Skip echo: if this update was written by _handleNewMessage,
      // updateChatOnMessage, or syncFromApi batch, Hive is already up-to-date.
      // Use a 5s tolerance to cover the network round-trip of the batch write.
      final ownWriteTs = _ownWriteTimestamps[key];
      final updateTs = _asInt(chatData['updated_at']);
      if (ownWriteTs != null && updateTs > 0 &&
          (updateTs - ownWriteTs).abs() <= 5000) {
        _ownWriteTimestamps.remove(key);
        debugPrint('⏭️ Skipping own-write echo for $key');
        return;
      }

      debugPrint('🔥 Firebase update detected for $key');

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

        // Never restore a badge the user has already read:
        // if local lastReadAt >= last message time, keep 0.
        // lastReadAt >= lastMessageTime is the sole source of truth.
        // Do NOT also require existingChat.unreadCount == 0 — that caused
        // the badge to resurrect when Firebase echoed a stale non-zero count.
        final localReadAt = existingChat.lastReadAt;
        final incomingMsgTime = lastMsgTime ?? existingChat.lastMessageTime;
        final userAlreadyRead = localReadAt != null &&
            incomingMsgTime != null &&
            !localReadAt.isBefore(incomingMsgTime);

        final firebaseUnread = _asInt(chatData['unread_count'],
            fallback: existingChat.unreadCount);
        final resolvedUnread =
            userAlreadyRead ? 0 : firebaseUnread;

        // Restore lastReadAt from Firebase payload if it's newer than what we
        // have locally — ensures cross-device read state is respected.
        final firebaseReadAtMs = _asInt(chatData['last_read_at'], fallback: 0);
        final firebaseReadAt = firebaseReadAtMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(firebaseReadAtMs)
            : null;
        final resolvedReadAt = (firebaseReadAt != null &&
                (existingChat.lastReadAt == null ||
                    firebaseReadAt.isAfter(existingChat.lastReadAt!)))
            ? firebaseReadAt
            : existingChat.lastReadAt;

        final updated = ChatHiveModel(
          id: chatId,
          type: chatType,
          name: chatData['name']?.toString() ?? existingChat.name,
          profilePicture:
              chatData['profile_picture']?.toString() ??
                  existingChat.profilePicture,
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
          lastReadAt: resolvedReadAt,
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
              chatData['section_name']?.toString() ??
                  existingChat.sectionName,
          sortTime: sortTime,
        );

        await _hiveDataSource.upsertChat(updated);
        // Notify provider after Firebase-triggered update so HomeScreen
        // reflects changes from other devices in real time.
        _notifyProvider();
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
        _notifyProvider();
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
    for (final sub in _messageListeners.values) {
      sub.cancel();
    }
    _messageListeners.clear();
    _ownWriteTimestamps.clear();
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

  /// Mark chat as read: zero the badge in Hive + Firebase and stamp lastReadAt.
  /// Uses a per-user read-receipt node in Firebase so group members each
  /// maintain independent read state across devices.
  Future<void> markAsRead(
      String chatId, String chatType, bool attendance_group) async {
    if (!_isInitialized || _currentUserId == null) return;

    final attendanceGroup = _asBool(attendance_group);
    final key = ChatHiveModel.buildKey(
      id: chatId,
      type: chatType,
      attendanceGroup: attendanceGroup,
    );
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Mark own write so _handleFirebaseUpdate skips the echo
      _ownWriteTimestamps[key] = nowMs;

      // 1. Zero the badge in Hive and stamp lastReadAt (persists across restarts)
      await _hiveDataSource.updateUnreadCount(
          chatId, chatType, 0, attendanceGroup);
      _notifyProvider();

      // 2. Update chat_list node for this user — unread_count + last_read_at
      unawaited(_chatListRef.child(_currentUserId!).child(key).update({
        'unread_count': 0,
        'last_read_at': nowMs,
        'updated_at': nowMs,
      }));

      // 3. Write per-user read-receipt so other devices know this user has read.
      //    Path: read_receipts/{chatKey}/{userId}  = { read_at: nowMs }
      //    Group members each write their own sub-key so they never overwrite
      //    each other's read state.
      unawaited(FirebaseDatabase.instance
          .ref('read_receipts/$key/$_currentUserId')
          .set({'read_at': nowMs}));

      // 4. Advance the message-listener cursor so reconnects don't re-count
      final isPrivate = chatType != 'group';
      final firebaseChatId = ChatUtils.generateChatId(
        chatId,
        chatType: chatType,
        attendanceGroup: attendanceGroup,
        currentUserId: _currentUserId,
        otherUserId: isPrivate ? chatId : '0',
      );
      _latestMessageTimestamp[firebaseChatId] = nowMs;

      debugPrint('✅ markAsRead: $key | lastReadAt=$nowMs');
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
    _latestMessageTimestamp.clear();
    _ownWriteTimestamps.clear();
    _isInitialized = false;
    _currentUserId = null;
    debugPrint('🗑️ ChatListSyncService disposed');
  }
}
