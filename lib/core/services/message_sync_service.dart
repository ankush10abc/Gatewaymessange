import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/chat_hive_model.dart';
import '../models/message_model.dart';
import '../utils/chat_utils.dart';
import '../utils/internet_checker.dart';
import 'api_service_simple.dart';
import 'firebase_realtime_service.dart';
import 'firebase_sync_isolate_service.dart';
import 'image_cache_service.dart';
import 'message_database_service.dart';

/// HIGH-PERFORMANCE MESSAGE CACHING SERVICE WITH SQLITE
///
/// Storage Strategy:
/// - SQLite database (PRIORITY 1): Fast, indexed queries, background thread sync
/// - Hive cache (PRIORITY 2): Fallback for backward compatibility
///
/// Key Features:
/// ✅ Instant load from SQLite (<50ms) - NO LOADER needed
/// ✅ Firebase messages synced in background isolate (non-blocking)
/// ✅ API called only ONCE per conversation
/// ✅ Background thread processing with compute() isolates
/// ✅ Automatic Hive → SQLite migration
/// ✅ Real-time Firebase → SQLite sync
/// ✅ Offline support with local database
///
/// Flow:
/// 1. ChatScreen opens → Load from SQLite (instant)
/// 2. Firebase listener starts → Messages synced to SQLite in background isolate
/// 3. UI receives messages via stream → No blocking
/// 4. New messages auto-saved to SQLite by background thread
///
/// Performance:
/// - Message load: <50ms (SQLite indexed query)
/// - Firebase sync: Non-blocking (runs in isolate)
/// - No loaders, no delays, instant UI
class MessageSyncService {
  static final MessageSyncService _instance = MessageSyncService._internal();
  factory MessageSyncService() => _instance;
  MessageSyncService._internal();
  static String TAG = 'MessageSyncService';
  final Map<String, Box<Map>> _messageBoxes = {};
  final Map<String, StreamSubscription> _firebaseListeners = {};
  final Map<String, bool> _apiLoadedFlags = {}; // Track if API was called
  final Map<String, Timer> _backgroundSyncTimers =
      {}; // Track background sync timers
  final Map<String, bool> _isSyncingBackground = {}; // Prevent concurrent syncs
  final Map<String, Timer> _firebaseOlderSyncTimers =
      {}; // Track Firebase older message sync
  final Map<String, bool> _isSyncingFirebaseOlder =
      {}; // Prevent concurrent Firebase older syncs
  final Map<String, bool> _isSyncingFirebaseRecent =
      {}; // Prevent concurrent recent Firebase syncs
  final ImageCacheService _imageCacheService = ImageCacheService();
  final MessageDatabaseService _dbService = MessageDatabaseService();
  final FirebaseSyncIsolateService _syncIsolateService =
      FirebaseSyncIsolateService();
  Box? _chatMetadataBox;
  Timer? _chatListBackgroundSyncTimer;
  String? _chatListBackgroundSyncSignature;
  bool _isChatListBackgroundSyncing = false;

  /// Get unique cache key based on chat type, IDs, role, and attendance_group
  String _getCacheKey(String chatId, String chatType,
      {String? currentUserId, String? userRole, bool? isAttendanceGroup}) {
    final role = (userRole ?? 'user').toLowerCase();
    final attendanceSuffix = (isAttendanceGroup == true) ? 'true' : '';

    if (chatType == 'group') {
      return 'group_$chatId$attendanceSuffix';
    } else {
      // For one-to-one: include both user IDs and role for uniqueness
      return 'private_${chatId}_${currentUserId ?? "unknown"}_$role$attendanceSuffix';
      //  if (currentUserId != null && otherUserId != null) {
      // final ids = [currentUserId, otherUserId]..sort();
      // return 'private_${ids[0]}_${ids[1]}';
      // }

      return 'private_$chatId';
    }
  }

  List<String> _getCacheKeyCandidates(
    String chatId,
    String chatType, {
    String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
  }) {
    final keys = <String>[];

    void add({String? userId, String? role, bool? attendance}) {
      final key = _getCacheKey(
        chatId,
        chatType,
        currentUserId: userId,
        userRole: role,
        isAttendanceGroup: attendance,
      );
      if (!keys.contains(key)) keys.add(key);
    }

    add(
      userId: currentUserId,
      role: userRole,
      attendance: isAttendanceGroup,
    );

    final normalizedRole = (userRole ?? 'user').toLowerCase();
    if (normalizedRole != 'user') {
      add(
        userId: currentUserId,
        role: 'user',
        attendance: isAttendanceGroup,
      );
    }

    if (chatType != 'group' && currentUserId != null) {
      add(
        userId: null,
        role: userRole,
        attendance: isAttendanceGroup,
      );
      if (normalizedRole != 'user') {
        add(
          userId: null,
          role: 'user',
          attendance: isAttendanceGroup,
        );
      }
    }

    return keys;
  }

  /// Initialize message cache box for a chat
  Future<Box<Map>> _getMessageBox(String cacheKey) async {
    if (_messageBoxes.containsKey(cacheKey)) {
      return _messageBoxes[cacheKey]!;
    }

    final box = await Hive.openBox<Map>(cacheKey);
    _messageBoxes[cacheKey] = box;
    debugPrint('$TAG$TAG $TAG 📦 Opened message box: $cacheKey');
    return box;
  }

  Future<Box> _getChatMetadataBox() async {
    if (_chatMetadataBox != null && _chatMetadataBox!.isOpen) {
      return _chatMetadataBox!;
    }

    _chatMetadataBox = await Hive.openBox('chat_metadata');
    return _chatMetadataBox!;
  }

  String _getChatMetadataKey(
    String chatId,
    String chatType, {
    bool? isAttendanceGroup,
  }) {
    return 'chat_info_${ChatHiveModel.buildKey(
      id: chatId,
      type: chatType,
      attendanceGroup: isAttendanceGroup,
    )}';
  }

  Future<Map<String, dynamic>?> getCachedChatMetadata(
    String chatId,
    String chatType, {
    bool? isAttendanceGroup,
  }) async {
    try {
      final box = await _getChatMetadataBox();
      final key = _getChatMetadataKey(
        chatId,
        chatType,
        isAttendanceGroup: isAttendanceGroup,
      );
      final cached = box.get(key);

      if (cached is Map) {
        return Map<String, dynamic>.from(cached);
      }
    } catch (e) {
      debugPrint('$TAG$TAG $TAG ❌ Chat metadata cache load error: $e');
    }

    return null;
  }

  Future<void> saveChatMetadataToCache({
    required String chatId,
    required String chatType,
    required Map<String, dynamic> metadata,
    bool? isAttendanceGroup,
  }) async {
    try {
      final box = await _getChatMetadataBox();
      final key = _getChatMetadataKey(
        chatId,
        chatType,
        isAttendanceGroup: isAttendanceGroup,
      );
      await box.put(key, metadata);
      debugPrint('$TAG$TAG $TAG 💾 Cached chat metadata for $key');
    } catch (e) {
      debugPrint('$TAG$TAG $TAG ❌ Chat metadata cache save error: $e');
    }
  }

  String _getMessageStorageKey(Message message) {
    final key = Message.resolveStorageKey(message);

    if (key.startsWith('msg_')) {
      debugPrint(
          '$TAG ⚠️ No valid key found for message (firebaseId=${message.firebaseId}, msgId=${message.msgId}, id=${message.id}), using fallback: $key');
    }

    return key;
  }

  String? _remoteImageUrl(Message message) {
    if (message.type != 'image') return null;

    final rawUrl = (message.fileUrl?.isNotEmpty == true
            ? message.fileUrl
            : message.file_path)
        ?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return null;

    if (rawUrl.startsWith('http')) return rawUrl;
    if (rawUrl.startsWith('/storage/')) return '${ApiService.baseUrl}$rawUrl';
    if (rawUrl.startsWith('storage/')) return '${ApiService.baseUrl}/$rawUrl';
    // Already a local file path — no download needed. Check after /storage
    // because API media paths can also begin with that prefix.
    if (rawUrl.startsWith('/') && File(rawUrl).existsSync()) return null;
    if (rawUrl.startsWith('/')) return '${ApiService.baseUrl}$rawUrl';
    // Relative path like "uploads/images/img.jpg"
    return '${ApiService.baseUrl}/storage/$rawUrl';
  }

  Future<Message> _withCachedImage(Message message) async {
    final metadata = Map<String, dynamic>.from(message.metadata ?? {});
    bool modified = false;

    // Cache message image (for image type messages)
    final imageUrl = _remoteImageUrl(message);
    if (imageUrl != null) {
      final localPath = await _imageCacheService.downloadAndCache(imageUrl);
      if (localPath != null && localPath != imageUrl) {
        metadata['local_image_path'] = localPath;
        metadata['remote_image_url'] = imageUrl;
        modified = true;
      }
    }

    // Cache profile picture (for all messages)
    final profilePictureUrl = _extractProfilePictureUrl(message);
    if (profilePictureUrl != null) {
      final localProfilePath =
          await _imageCacheService.downloadAndCache(profilePictureUrl);
      if (localProfilePath != null && localProfilePath != profilePictureUrl) {
        metadata['local_profile_picture'] = localProfilePath;
        metadata['remote_profile_picture'] = profilePictureUrl;
        modified = true;
      }
    }

    return modified ? message.copyWith(metadata: metadata) : message;
  }

  String? _extractProfilePictureUrl(Message message) {
    final rawUrl = message.profile_picture_url?.toString().trim();
    if (rawUrl == null || rawUrl.isEmpty || rawUrl == 'null') return null;

    if (rawUrl.startsWith('http')) return rawUrl;
    if (rawUrl.startsWith('/storage/')) return '${ApiService.baseUrl}$rawUrl';
    if (rawUrl.startsWith('storage/')) return '${ApiService.baseUrl}/$rawUrl';
    if (rawUrl.startsWith('/')) return '${ApiService.baseUrl}$rawUrl';

    return '${ApiService.baseUrl}/storage/$rawUrl';
  }

  Future<void> _putMessage(Box<Map> box, Message message) async {
    final cacheMessage = await _withCachedImage(message);
    final key = _getMessageStorageKey(cacheMessage);
    await box.put(key, cacheMessage.toJson());
  }

  List<Message> _messagesFromBox(Box<Map> box) {
    final messages = <Message>[];
    for (final entry in box.values) {
      try {
        final msgMap = _deepConvertMap(entry);
        messages.add(Message.fromJson(msgMap));
      } catch (e) {
        debugPrint('$TAG ⚠️ Failed to parse cached message: $e');
      }
    }
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return messages;
  }

  /// Deep convert any Map to Map<String, dynamic>, recursively.
  /// Ensures all nested maps (including 'status') have String keys and
  /// String values so Message.fromJson and parseStatus never get type errors.
  Map<String, dynamic> _deepConvertMap(dynamic input) {
    if (input is Map) {
      return Map<String, dynamic>.fromEntries(input.entries.map((e) {
        final key = e.key.toString();
        final value = e.value;
        if (value is Map) {
          return MapEntry(key, _deepConvertMap(value));
        } else if (value is List) {
          return MapEntry(
            key,
            value.map((item) => item is Map ? _deepConvertMap(item) : item).toList(),
          );
        }
        // Ensure all scalar values are stored as their natural type
        return MapEntry(key, value);
      }));
    }
    return {};
  }

  //d
  Future<void> addMessageToLocaldatabasefromApi(
    String chatId,
    String chatType,
    List<Message> fallbackMessages,
  ) async {
    await _dbService.saveMessages(fallbackMessages, chatId, chatType);
  }

  /// Sync old messages from API to Firebase + SQLite with full deduplication.
  /// Returns only the genuinely new (non-duplicate) messages that were inserted.
  Future<List<Message>> syncOldMessagesToFirebaseAndDb({
    required String chatId,
    required String chatType,
    required List<Message> messages,
    String? currentUserId,
    bool? isAttendanceGroup,
  }) async {
    if (messages.isEmpty) return [];

    // Firebase path: attendance groups use 'group_1true', regular groups use 'group_1'
    // This matches ChatUtils.generateChatId behavior
    final firebaseChatId = ChatUtils.generateChatId(
      chatId,
      currentUserId: currentUserId,
      otherUserId: '0',
      chatType: chatType,
      attendanceGroup: isAttendanceGroup,
    );

    debugPrint('$TAG 🔄 syncOldMessagesToFirebaseAndDb'
        ' path=chats/$firebaseChatId/messages'
        ' count=${messages.length} attendance=$isAttendanceGroup');

    // --- Step 1: Read existing Firebase nodes to build dedup sets ---
    // We read ALL fields per node so we can match by msgId stored inside
    final existingFbKeys = <String>{};
    final existingFbMsgIds =
        <String>{}; // values of msgId/id stored inside nodes
    try {
      final snap = await FirebaseRealtimeService.database
          .ref('chats/$firebaseChatId/messages')
          .get();
      if (snap.exists && snap.value is Map) {
        final raw = snap.value as Map<dynamic, dynamic>;
        for (final entry in raw.entries) {
          final nodeKey = entry.key.toString();
          existingFbKeys.add(nodeKey);
          // The key itself IS the msgId for old status-only nodes (e.g. "1","2"...)
          existingFbMsgIds.add(nodeKey);
          final val = entry.value;
          if (val is Map) {
            // Also collect any id values stored inside full message nodes
            for (final f in ['msgId', 'msg_id', 'id', 'firebaseId']) {
              final v = val[f]?.toString();
              if (v != null && v.isNotEmpty && v != '0')
                existingFbMsgIds.add(v);
            }
          }
        }
      }
      debugPrint('$TAG 📊 Firebase existing: ${existingFbKeys.length} nodes, '
          'msgIds: ${existingFbMsgIds.length}');
    } catch (e) {
      debugPrint('$TAG ⚠️ Firebase read failed (will insert all): $e');
    }

    // --- Step 2: Read existing SQLite rows (id, firebase_id, msg_id only) ---
    final existingDbIds = <String>{};
    try {
      final db = await _dbService.database;
      final rows = await db.rawQuery(
        'SELECT id, firebase_id, msg_id FROM messages WHERE chat_id=? AND chat_type=?',
        [chatId, chatType],
      );
      for (final row in rows) {
        for (final col in ['id', 'firebase_id', 'msg_id']) {
          final v = row[col]?.toString();
          if (v != null && v.isNotEmpty && v != '0' && v != 'null') {
            existingDbIds.add(v);
          }
        }
      }
      debugPrint('$TAG 📊 SQLite existing ids: ${existingDbIds.length}');
    } catch (e) {
      debugPrint('$TAG ⚠️ SQLite read failed (will insert all): $e');
    }

    // --- Step 3: Classify messages ---
    final firebaseUpdates = <String, dynamic>{};
    final dbInserts = <Message>[];
    final newMessages = <Message>[];

    for (final msg in messages) {
      final msgId = msg.msgId?.trim();
      final resolvedId = (msgId != null && msgId.isNotEmpty && msgId != '0')
          ? msgId
          : msg.id.trim();

      if (resolvedId.isEmpty) continue;

      final fbKey = resolvedId;

      // Skip per-message Firebase get() — use the batch snapshot already read above.
      // A node is considered to have full data if its key already exists in Firebase
      // AND the snapshot for that key contains senderId or text fields.
      // Since we already have the full snapshot value in existingFbKeys, we check inline.
      final nodeExists = existingFbKeys.contains(fbKey);

      // Insert/update Firebase only if node is absent (never do per-node reads in a loop)
      if (!nodeExists) {
        final data = _buildFirebasePayload(msg, fbKey, chatId, resolvedId);
        firebaseUpdates[fbKey] = data;
      }

      // SQLite dedup
      final dbDup = existingDbIds.contains(resolvedId) ||
          existingDbIds.contains('api_$resolvedId') ||
          (msg.firebaseId != null &&
              msg.firebaseId!.isNotEmpty &&
              existingDbIds.contains(msg.firebaseId!));

      if (!dbDup) {
        final enriched = msg.copyWith(firebaseId: fbKey);
        dbInserts.add(enriched);
        newMessages.add(enriched);
      }
    }

    debugPrint('$TAG 📋 Plan: firebase=${firebaseUpdates.length} writes, '
        'sqlite=${dbInserts.length} inserts, '
        'total=${messages.length}');

    // --- Step 4: Write to Firebase ---
    if (firebaseUpdates.isNotEmpty) {
      try {
        await FirebaseRealtimeService.database
            .ref('chats/$firebaseChatId/messages')
            .update(firebaseUpdates);
        debugPrint(
            '$TAG ✅ Firebase wrote ${firebaseUpdates.length} messages to '
            'chats/$firebaseChatId/messages');
      } catch (e) {
        debugPrint('$TAG ❌ Firebase write error: $e');
      }
    }

    // --- Step 5: Write to SQLite + Hive ---
    if (dbInserts.isNotEmpty) {
      try {
        await _dbService.saveMessages(dbInserts, chatId, chatType);
        debugPrint('$TAG ✅ SQLite inserted ${dbInserts.length} messages');

        final cacheKey = _getCacheKey(chatId, chatType,
            isAttendanceGroup: isAttendanceGroup);
        await _cacheMessages(cacheKey, dbInserts, append: true);
      } catch (e) {
        debugPrint('$TAG ❌ SQLite write error: $e');
      }
    }

    return newMessages;
  }

  /// Build a Firebase-safe payload — no nulls, timestamps as int.
  Map<String, dynamic> _buildFirebasePayload(
      Message msg, String fbKey, String chatId, String resolvedId) {
    final data = <String, dynamic>{
      'id': fbKey,
      'firebaseId': fbKey,
      'chatId': chatId,
      'msgId': resolvedId,
      'senderId': msg.senderId,
      'sender_id': msg.senderId,
      'senderName': msg.senderName ?? '',
      'sender_name': msg.senderName ?? '',
      'text': msg.text,
      'content': msg.text,
      'message': msg.text,
      'type': msg.type,
      'timestamp': msg.timestamp.millisecondsSinceEpoch,
      // Preserve existing status if any — merge with sent default
      'status': msg.status.isNotEmpty ? msg.status : {'default': 'sent'},
    };
    if (msg.fileUrl?.isNotEmpty == true) data['file_url'] = msg.fileUrl!;
    if (msg.file_path?.isNotEmpty == true) data['file_path'] = msg.file_path!;
    if (msg.fileName?.isNotEmpty == true) data['file_name'] = msg.fileName!;
    if (msg.fileSize != null && msg.fileSize! > 0)
      data['file_size'] = msg.fileSize!;
    if (msg.replyToId?.isNotEmpty == true) data['reply_to_id'] = msg.replyToId!;
    if (msg.profile_picture_url != null) {
      data['profile_picture_url'] = msg.profile_picture_url.toString();
    }
    return data;
  }

  /// STEP 1: Get cached messages instantly from SQLite (0ms delay)
  /// Falls back to Hive if SQLite is empty
  Future<List<Message>> getCachedMessages(String chatId, String chatType,
      {String? currentUserId,
      String? userRole,
      bool? isAttendanceGroup}) async {
    try {
      // PRIORITY 1: Load from SQLite (fastest)
      try {
        final dbMessages =
            await _dbService.getMessages(chatId, chatType, limit: 500);
        if (dbMessages.isNotEmpty) {
          // debugPrint('$TAG ✅ Loaded ${dbMessages.length} messages from SQLite (instant)');
          return dbMessages;
        }
      } catch (e) {
        debugPrint('$TAG ⚠️ SQLite not ready, falling back to Hive: $e');
      }

      // PRIORITY 2: Load from Hive (fallback)
      final cacheKey = _getCacheKey(chatId, chatType,
          currentUserId: currentUserId,
          userRole: userRole,
          isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);

      if (box.isEmpty) {
        final fallbackKeys = _getCacheKeyCandidates(
          chatId,
          chatType,
          currentUserId: currentUserId,
          userRole: userRole,
          isAttendanceGroup: isAttendanceGroup,
        ).where((key) => key != cacheKey);

        for (final fallbackKey in fallbackKeys) {
          final fallbackBox = await _getMessageBox(fallbackKey);
          if (fallbackBox.isEmpty) continue;

          final fallbackMessages = _messagesFromBox(fallbackBox);
          if (fallbackMessages.isEmpty) continue;

          await _cacheMessages(cacheKey, fallbackMessages, append: true);
          // Try to migrate to SQLite (best effort)
          try {
            await _dbService.saveMessages(fallbackMessages, chatId, chatType);
            debugPrint(
                '$TAG ✅ Migrated ${fallbackMessages.length} cached messages from $fallbackKey to SQLite');
          } catch (e) {
            debugPrint('$TAG ⚠️ SQLite migration skipped: $e');
          }
          return fallbackMessages;
        }

        debugPrint(
            '$TAG 💾 No cached messages for $cacheKey (first time load)');
        return [];
      }

      final messages = _messagesFromBox(box);
      // Try to migrate Hive data to SQLite for future instant loads (best effort)
      if (messages.isNotEmpty) {
        try {
          // Use _saveToDatabaseAsync so images are cached before SQLite write
          unawaited(_saveToDatabaseAsync(messages: messages, chatId: chatId, chatType: chatType));
          debugPrint(
              '$TAG 🔄 Migrating ${messages.length} Hive messages to SQLite');
        } catch (e) {
          debugPrint('$TAG ⚠️ SQLite migration skipped: $e');
        }
      }
      debugPrint(
          '$TAG ✅ Loaded ${messages.length} cached messages from Hive (instant, attendance: ${isAttendanceGroup ?? false})');
      return messages;
    } catch (e) {
      debugPrint('$TAG$TAG $TAG ❌ Cache load error: $e');
      return [];
    }
  }

  /// STEP 2: Load messages from API (ONLY if not loaded before)
  /// After first load, API is never called again for this conversation
  Future<Map<String, dynamic>> loadMessagesFromApi({
    required String chatId,
    required String chatType,
    required ApiService apiService,
    String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
    int page = 1,
    int limit = 50,
    bool forceReload = false,
  }) async {
    final cacheKey = _getCacheKey(chatId, chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup);

    // Check if API was already called using Hive persistent flag
    if (!forceReload) {
      final statusBox = await Hive.openBox('chat_status');
      final statusKey = '${cacheKey}_api_loaded';
      final isLoaded = statusBox.get(statusKey, defaultValue: false);
      if (isLoaded == true) {
        debugPrint(
            '$TAG$TAG $TAG ⏭️ API already loaded for $cacheKey (persistent), skipping API call');
        final cachedMessages = await getCachedMessages(chatId, chatType,
            currentUserId: currentUserId,
            userRole: userRole,
            isAttendanceGroup: isAttendanceGroup);
        return {
          'messages': cachedMessages,
          'user': null,
          'has_more': false,
          'from_cache': true,
        };
      }
    }

    try {
      debugPrint(
          '$TAG$TAG $TAG 🌐 Loading messages from API for $cacheKey (first time)');
      final id = int.parse(chatId);

      Map<String, dynamic> result;

      if (chatType == 'group') {
        final response = await apiService.getGroupMessages(id, page, limit);
        await _cacheMessages(cacheKey, response.data);
        result = {
          'messages': response.data,
          'user': response.user,
          'has_more': response.data.length >= limit,
          'from_cache': false,
        };
      } else {
        final response = await apiService.getConversation(id, page, limit);
        await _cacheMessages(cacheKey, response.data);
        result = {
          'messages': response.data,
          'user': response.user,
          'has_more': response.data.length >= limit,
          'from_cache': false,
        };
      }

      // Mark as loaded persistently in Hive
      final statusBox = await Hive.openBox('chat_status');
      final statusKey = '${cacheKey}_api_loaded';
      await statusBox.put(statusKey, true);
      debugPrint(
          '$TAG ✅ API loaded and cached for $cacheKey (persistent flag set, attendance: ${isAttendanceGroup ?? false})');

      return result;
    } catch (e) {
      debugPrint('$TAG$TAG $TAG ❌ API load error for $cacheKey: $e');
      rethrow;
    }
  }

  /// Load more messages (pagination)
  Future<List<Message>> loadMoreMessages({
    required String chatId,
    required String chatType,
    required ApiService apiService,
    String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
    required int page,
    int limit = 50,
  }) async {
    try {
      final id = int.parse(chatId);

      if (chatType == 'group') {
        final response = await apiService.getGroupMessages(id, page, limit);
        // Cache additional messages
        final cacheKey = _getCacheKey(chatId, chatType,
            currentUserId: currentUserId,
            userRole: userRole,
            isAttendanceGroup: isAttendanceGroup);
        await _cacheMessages(cacheKey, response.data, append: true);
        debugPrint(
            '$TAG 📄 Loaded page $page with ${response.data.length} messages (attendance: ${isAttendanceGroup ?? false})');
        return response.data;
      } else {
        final response = await apiService.getConversation(id, page, limit);
        final cacheKey = _getCacheKey(chatId, chatType,
            currentUserId: currentUserId,
            userRole: userRole,
            isAttendanceGroup: isAttendanceGroup);
        await _cacheMessages(cacheKey, response.data, append: true);
        debugPrint(
            '$TAG 📄 Loaded page $page with ${response.data.length} messages (attendance: ${isAttendanceGroup ?? false})');
        return response.data;
      }
    } catch (e) {
      debugPrint('$TAG$TAG $TAG ❌ Load more error: $e');
      return [];
    }
  }

  /// Cache messages to Hive
  Future<void> _cacheMessages(String cacheKey, List<Message> messages,
      {bool append = false}) async {
    try {
      final box = await _getMessageBox(cacheKey);

      final Map<String, Map> updates = {};
      for (final message in messages) {
        // Use firebaseId as primary key, fallback to msgId or id
        final cacheMessage = await _withCachedImage(message);
        final key = _getMessageStorageKey(cacheMessage);
        updates[key] = cacheMessage.toJson();
      }

      if (append) {
        await box.putAll(updates);
      } else {
        // First load: clear and write
        await box.clear();
        await box.putAll(updates);
      }

      debugPrint('$TAG$TAG 💾 Cached ${updates.length} messages for $cacheKey');
    } catch (e) {
      debugPrint('$TAG$TAG ❌ Cache save error: $e');
    }
  }

  Future<void> saveMessagesToCache({
    required String chatId,
    required String chatType,
    required List<Message> messages,
    String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
    bool append = true,
  }) async {
    final cacheKey = _getCacheKey(
      chatId,
      chatType,
      currentUserId: currentUserId,
      userRole: userRole,
      isAttendanceGroup: isAttendanceGroup,
    );
    await _cacheMessages(cacheKey, messages, append: append);
  }

  String _safeFirebaseMessageKey(Message message) {
    return _getMessageStorageKey(message)
        .replaceAll('.', '_')
        .replaceAll('#', '_')
        .replaceAll('\$', '_')
        .replaceAll('/', '_')
        .replaceAll('[', '_')
        .replaceAll(']', '_');
  }

  Future<void> _syncMessagesToFirebase({
    required String chatId,
    required String chatType,
    required List<Message> messages,
    String? currentUserId,
    String? otherUserId,
    bool? isAttendanceGroup,
  }) async {
    debugPrint("Ankush data update to firebase firebaseChatId ");
    if (messages.isEmpty) return;

    try {
      final firebaseChatId = ChatUtils.generateChatId(
        chatId,
        currentUserId: currentUserId,
        otherUserId: _resolveFirebaseOtherUserId(
          chatId,
          chatType,
          otherUserId,
        ),
        chatType: chatType,
        attendanceGroup: isAttendanceGroup,
      );

      final updates = <String, dynamic>{};
      for (final message in messages) {
        final key = _safeFirebaseMessageKey(message);
        final messageData = message.toJson();
        messageData['id'] = key;
        messageData['firebaseId'] = key;
        messageData['chatId'] = chatId;
        messageData['timestamp'] = message.timestamp.millisecondsSinceEpoch;
        updates[key] = messageData;
      }

      await FirebaseRealtimeService.database
          .ref('chats/$firebaseChatId/messages')
          .update(updates);

      final newest = [...messages]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      await FirebaseRealtimeService.database
          .ref('chats/$firebaseChatId')
          .update({
        'lastMessage': newest.first.toJson()
          ..['timestamp'] = newest.first.timestamp.millisecondsSinceEpoch,
        'updatedAt': newest.first.timestamp.millisecondsSinceEpoch,
      });

      debugPrint(
          '🔥 API → Firebase synced ${messages.length} messages for $firebaseChatId');
    } catch (e) {
      debugPrint('$TAG ❌ API → Firebase message sync failed: $e');
    }
  }

  Future<List<Message>> syncAttendanceGroupFromApi({
    required String chatId,
    required ApiService apiService,
    String? currentUserId,
    String? userRole,
    int page = 1,
    int limit = 50,
    bool append = false,
  }) async {
    final id = int.parse(chatId);
    final response = await apiService.getGroupMessages(id, page, 15);
    final userData = Map<String, dynamic>.from(response.user);
    userData['attendance_group'] = true;

    await saveChatMetadataToCache(
      chatId: chatId,
      chatType: 'group',
      metadata: userData,
      isAttendanceGroup: true,
    );

    // Save to Hive cache
    await saveMessagesToCache(
      chatId: chatId,
      chatType: 'group',
      messages: response.data,
      currentUserId: currentUserId,
      userRole: userRole,
      isAttendanceGroup: true,
      append: append,
    );

    // Save to SQLite with dedup (no Firebase sync here — caller handles it)
    if (response.data.isNotEmpty) {
      await _dbService.saveMessages(response.data, chatId, 'group');
      debugPrint(
          '$TAG 💾 syncAttendanceGroupFromApi: saved ${response.data.length} to SQLite page=$page');
    }

    return response.data;
  }

  String? _resolveFirebaseOtherUserId(
    String chatId,
    String chatType,
    String? otherUserId,
  ) {
    if (chatType == 'group') return '0';

    final resolved = otherUserId?.trim();
    if (resolved != null && resolved.isNotEmpty && resolved != 'null') {
      return resolved;
    }

    return chatId;
  }

  /// Fetch recent Firebase messages and save to SQLite in background
  /// Used by HomeScreen/background flows so ChatScreen can open from cache
  Future<List<Message>> syncRecentFirebaseMessages({
    required String chatId,
    required String chatType,
    String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
    String? otherUserId,
    int limit = 50,
    bool checkInternet = true,
  }) async {
    final cacheKey = _getCacheKey(
      chatId,
      chatType,
      currentUserId: currentUserId,
      userRole: userRole,
      isAttendanceGroup: isAttendanceGroup,
    );
    debugPrint('$TAG ⏭️ cachedMessages $cacheKey');
    if (_isSyncingFirebaseRecent[cacheKey] == true) {
      debugPrint(
          '$TAG$TAG ⏭️ Recent Firebase sync already running for $cacheKey');
      return [];
    }

    _isSyncingFirebaseRecent[cacheKey] = true;

    try {
      if (checkInternet) {
        final hasInternet = await InternetChecker.hasInternet();
        if (!hasInternet) {
          debugPrint(
              '📴 Skipping recent Firebase sync while offline: $cacheKey');
          return [];
        }
      }

      final resolvedOtherUserId = _resolveFirebaseOtherUserId(
        chatId,
        chatType,
        otherUserId,
      );

      final messages = await FirebaseRealtimeService.getMessagesStreamLimited(
        chatId,
        chatType,
        limit,
        currentUserId: currentUserId,
        otherUserId: resolvedOtherUserId,
        attendanceGroup: isAttendanceGroup,
      ).first.timeout(
            const Duration(seconds: 8),
            onTimeout: () => <Message>[],
          );

      if (messages.isNotEmpty) {
        // Save to SQLite in background (non-blocking async)
        unawaited(_saveToDatabaseAsync(
          messages: messages,
          chatId: chatId,
          chatType: chatType,
        ));
        // Also save to Hive for backward compatibility
        await _cacheMessages(cacheKey, messages, append: true);
      }

      debugPrint(
          '🔄 Firebase → SQLite synced ${messages.length} recent messages for $cacheKey');
      return messages;
    } catch (e) {
      debugPrint('$TAG$TAG ❌ Recent Firebase sync error for $cacheKey: $e');
      return [];
    } finally {
      _isSyncingFirebaseRecent[cacheKey] = false;
    }
  }

  /// Keep conversations from the HomeScreen chat list warm in the offline cache.
  void startChatListFirebaseSync({
    required List<ChatHiveModel> chats,
    required String currentUserId,
    String? userRole,
    Duration interval = const Duration(minutes: 2),
    int maxChats = 30,
  }) {
    final candidates = chats
        .where((chat) => chat.id.isNotEmpty && chat.type.isNotEmpty)
        .take(maxChats)
        .toList(growable: false);

    if (candidates.isEmpty) return;

    final signature = _buildChatListSyncSignature(
      candidates,
      currentUserId,
      userRole,
    );

    if (_chatListBackgroundSyncSignature == signature &&
        _chatListBackgroundSyncTimer?.isActive == true) {
      return;
    }

    _chatListBackgroundSyncTimer?.cancel();
    _chatListBackgroundSyncSignature = signature;

    void runSync() {
      unawaited(_syncChatListFirebaseMessages(
        chats: candidates,
        currentUserId: currentUserId,
        userRole: userRole,
      ));
    }

    runSync();
    _chatListBackgroundSyncTimer = Timer.periodic(interval, (_) => runSync());

    debugPrint(
        '⏰ Started chat-list Firebase → SQLite sync for ${candidates.length} chats');
  }

  String _buildChatListSyncSignature(
    List<ChatHiveModel> chats,
    String currentUserId,
    String? userRole,
  ) {
    final chatSignature = chats.map((chat) {
      final time = chat.sortTime ?? chat.lastMessageTime ?? chat.updatedAt;
      return '${chat.type}_${chat.id}_${time.millisecondsSinceEpoch}_${chat.unreadCount}';
    }).join('|');
    return '$currentUserId|${userRole ?? 'user'}|$chatSignature';
  }

  Future<void> _syncChatListFirebaseMessages({
    required List<ChatHiveModel> chats,
    required String currentUserId,
    String? userRole,
  }) async {
    if (_isChatListBackgroundSyncing) return;

    _isChatListBackgroundSyncing = true;

    try {
      final hasInternet = await InternetChecker.hasInternet();
      if (!hasInternet) {
        debugPrint(
            '$TAG$TAG 📴 Skipping chat-list Firebase cache sync while offline');
        return;
      }

      const batchSize = 3;
      for (var index = 0; index < chats.length; index += batchSize) {
        final batch = chats.skip(index).take(batchSize).toList();
        await Future.wait(batch.map((chat) {
          return syncRecentFirebaseMessages(
            chatId: chat.id,
            chatType: chat.type,
            currentUserId: currentUserId,
            userRole: userRole,
            isAttendanceGroup: chat.attendanceGroup,
            otherUserId: chat.type == 'group' ? '0' : chat.id,
            checkInternet: false,
          );
        }));
      }

      debugPrint(
          '✅ Background Firebase → SQLite sync completed for ${chats.length} chats');
    } catch (e) {
      debugPrint('$TAG$TAG ❌ Chat-list Firebase cache sync failed: $e');
    } finally {
      _isChatListBackgroundSyncing = false;
    }
  }

  /// Setup Firebase real-time listener with auto-caching to SQLite (background isolate)
  StreamSubscription<List<Message>> setupFirebaseListener({
    required String chatId,
    required String chatType,
    required String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
    String? otherUserId,
    required Function(List<Message>) onMessages,
  }) {
    final cacheKey = _getCacheKey(chatId, chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup);

    // Cancel existing listener
    _firebaseListeners[cacheKey]?.cancel();

    final subscription = FirebaseRealtimeService.getMessagesStreamLimited(
      chatId,
      chatType,
      50,
      currentUserId: currentUserId,
      otherUserId: _resolveFirebaseOtherUserId(chatId, chatType, otherUserId),
      attendanceGroup: isAttendanceGroup,
    ).listen((messages) {
      // Auto-cache Firebase messages to SQLite in background isolate (non-blocking)
      _cacheMessagesRealtimeBackground(cacheKey, messages, chatId, chatType);
      onMessages(messages);
    });

    _firebaseListeners[cacheKey] = subscription;
    debugPrint('$TAG$TAG 👂 Started Firebase listener for $cacheKey');

    // Start background isolate sync for continuous syncing
    _syncIsolateService.startSync(
      chatId: chatId,
      chatType: chatType,
      currentUserId: currentUserId,
      otherUserId: otherUserId,
      isAttendanceGroup: isAttendanceGroup,
    );

    return subscription;
  }

  /// Cache Firebase messages to SQLite in background (non-blocking async)
  Future<void> _cacheMessagesRealtimeBackground(String cacheKey,
      List<Message> messages, String chatId, String chatType) async {
    try {
      // Save to SQLite in background (non-blocking async)
      unawaited(_saveToDatabaseAsync(
        messages: messages,
        chatId: chatId,
        chatType: chatType,
      ));

      // Also update Hive cache for backward compatibility
      final box = await _getMessageBox(cacheKey);
      for (final message in messages) {
        await _putMessage(box, message);
      }
      debugPrint(
          '$TAG$TAG 🔄 Background cached ${messages.length} Firebase messages');
    } catch (e) {
      debugPrint('$TAG$TAG ❌ Realtime cache error: $e');
    }
  }

  /// Add single message to cache (for optimistic updates) - saves to both SQLite and Hive
  Future<void> addMessageToCache(
      String chatId, String chatType, Message message,
      {String? currentUserId,
      String? userRole,
      bool? isAttendanceGroup}) async {
    try {
      final cacheMessage = await _withCachedImage(message);

      // Try to save to SQLite (priority)
      try {
        await _dbService.saveMessage(cacheMessage, chatId, chatType);
      } catch (e) {
        debugPrint('$TAG$TAG ⚠️ SQLite save skipped: $e');
      }

      // Save to Hive (backward compatibility - always works)
      final cacheKey = _getCacheKey(chatId, chatType,
          currentUserId: currentUserId,
          userRole: userRole,
          isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);
      final key = _getMessageStorageKey(cacheMessage);
      await box.put(key, cacheMessage.toJson());

      debugPrint('$TAG$TAG 📝 Added message $key to cache');
    } catch (e) {
      debugPrint('$TAG$TAG ❌ Failed to cache message: $e');
    }
  }

  /// Start periodic background sync with API and Firebase older messages
  void startBackgroundSync({
    required String chatId,
    required String chatType,
    required ApiService apiService,
    String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
    String? otherUserId,
    Duration interval = const Duration(seconds: 30),
  }) {
    final cacheKey = _getCacheKey(chatId, chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup);

    // Cancel existing timers
    _backgroundSyncTimers[cacheKey]?.cancel();
    _firebaseOlderSyncTimers[cacheKey]?.cancel();

    // Start periodic API sync
    _backgroundSyncTimers[cacheKey] = Timer.periodic(interval, (timer) {
      _syncWithApiBackground(
        chatId: chatId,
        chatType: chatType,
        apiService: apiService,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup,
        otherUserId: otherUserId,
      );
    });

    // Start periodic Firebase older messages sync (every 45 seconds)
    _firebaseOlderSyncTimers[cacheKey] =
        Timer.periodic(const Duration(seconds: 45), (timer) {
      _syncFirebaseOlderMessages(
        chatId: chatId,
        chatType: chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup,
        otherUserId: otherUserId,
      );
    });

    debugPrint(
        '⏰ Started background sync for $cacheKey (API: ${interval.inSeconds}s, Firebase older: 45s)');
  }

  void stopChatListFirebaseSync() {
    _chatListBackgroundSyncTimer?.cancel();
    _chatListBackgroundSyncTimer = null;
    _chatListBackgroundSyncSignature = null;
    _isChatListBackgroundSyncing = false;
    debugPrint('$TAG 🛑 Stopped chat-list Firebase cache sync');
  }

  /// Sync with API in background (non-blocking)
  Future<void> _syncWithApiBackground({
    required String chatId,
    required String chatType,
    required ApiService apiService,
    String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
    String? otherUserId,
  }) async {
    final cacheKey = _getCacheKey(chatId, chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup);

    // Prevent concurrent syncs
    if (_isSyncingBackground[cacheKey] == true) {
      debugPrint('$TAG ⏭️ Background sync already in progress for $cacheKey');
      return;
    }

    _isSyncingBackground[cacheKey] = true;

    try {
      final messages = await syncRecentFirebaseMessages(
        chatId: chatId,
        chatType: chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup,
        otherUserId: otherUserId,
        limit: 50,
      );

      debugPrint(
          '🔄 Background synced ${messages.length} Firebase messages for $cacheKey');
    } catch (e) {
      debugPrint('$TAG ❌ Background API sync error: $e');
    } finally {
      _isSyncingBackground[cacheKey] = false;
    }
  }

  /// Sync older messages from Firebase in background (11 messages per batch)
  Future<void> _syncFirebaseOlderMessages({
    required String chatId,
    required String chatType,
    String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
    String? otherUserId,
  }) async {
    final cacheKey = _getCacheKey(chatId, chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup);

    // Prevent concurrent Firebase older syncs
    if (_isSyncingFirebaseOlder[cacheKey] == true) {
      debugPrint(
          '$TAG ⏭️ Firebase older sync already in progress for $cacheKey');
      return;
    }

    _isSyncingFirebaseOlder[cacheKey] = true;

    try {
      // Get oldest message from cache
      final cachedMessages = await getCachedMessages(chatId, chatType,
          currentUserId: currentUserId,
          userRole: userRole,
          isAttendanceGroup: isAttendanceGroup);

      if (cachedMessages.isEmpty) {
        debugPrint(
            '$TAG ⏭️ No cached messages for $cacheKey, skipping older sync');
        _isSyncingFirebaseOlder[cacheKey] = false;
        return;
      }

      // Get oldest message timestamp
      final oldestMessage = cachedMessages.last;
      final oldestTimestamp = oldestMessage.timestamp;

      // Fetch 11 older messages from Firebase
      final olderMessages = await FirebaseRealtimeService.getOlderMessages(
        chatId,
        chatType,
        oldestTimestamp,
        11, // Fetch 11 messages per batch
        currentUserId: currentUserId,
        otherUserId: _resolveFirebaseOtherUserId(chatId, chatType, otherUserId),
        attendanceGroup: isAttendanceGroup,
      );

      if (olderMessages.isEmpty) {
        debugPrint('$TAG ✅ No more older messages in Firebase for $cacheKey');
        _isSyncingFirebaseOlder[cacheKey] = false;
        return;
      }

      // Cache older messages in background
      final box = await _getMessageBox(cacheKey);
      for (final message in olderMessages) {
        await _putMessage(box, message);
      }

      debugPrint(
          '🔄 Background synced ${olderMessages.length} older Firebase messages for $cacheKey');
    } catch (e) {
      debugPrint('$TAG ❌ Firebase older sync error: $e');
    } finally {
      _isSyncingFirebaseOlder[cacheKey] = false;
    }
  }

  /// Sync specific batch of older Firebase messages (for pagination)
  Future<List<Message>> syncOlderFirebaseMessages({
    required String chatId,
    required String chatType,
    required DateTime beforeTimestamp,
    String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
    String? otherUserId,
    int limit = 11,
  }) async {
    final cacheKey = _getCacheKey(chatId, chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup);

    try {
      // Fetch older messages from Firebase
      final olderMessages = await FirebaseRealtimeService.getOlderMessages(
        chatId,
        chatType,
        beforeTimestamp,
        limit,
        currentUserId: currentUserId,
        otherUserId: _resolveFirebaseOtherUserId(chatId, chatType, otherUserId),
        attendanceGroup: isAttendanceGroup,
      );

      if (olderMessages.isEmpty) {
        debugPrint('$TAG ✅ No more older messages in Firebase for $cacheKey');
        return [];
      }

      // Cache older messages immediately
      final box = await _getMessageBox(cacheKey);
      for (final message in olderMessages) {
        await _putMessage(box, message);
      }

      debugPrint(
          '📥 Synced ${olderMessages.length} older messages from Firebase to cache');
      return olderMessages;
    } catch (e) {
      debugPrint('$TAG ❌ Sync older Firebase messages error: $e');
      return [];
    }
  }

  /// Stop background sync
  void stopBackgroundSync(String chatId, String chatType,
      {String? currentUserId, String? userRole, bool? isAttendanceGroup}) {
    final cacheKey = _getCacheKey(chatId, chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup);
    _backgroundSyncTimers[cacheKey]?.cancel();
    _backgroundSyncTimers.remove(cacheKey);
    _firebaseOlderSyncTimers[cacheKey]?.cancel();
    _firebaseOlderSyncTimers.remove(cacheKey);
    _isSyncingBackground.remove(cacheKey);
    _isSyncingFirebaseOlder.remove(cacheKey);
    _isSyncingFirebaseRecent.remove(cacheKey);
    debugPrint('$TAG 🛑 Stopped background sync for $cacheKey');
  }

  /// Returns all message IDs already marked as read in SQLite for this chat.
  /// Used to pre-seed the in-memory read-tracking set on app restart so
  /// already-read messages are never re-processed as unread.
  Future<Set<String>> getReadMessageIds(String chatId, String chatType) async {
    return _dbService.getReadMessageIds(chatId, chatType);
  }

  /// Update message in cache (e.g., status update)
  Future<void> updateMessageInCache(String chatId, String chatType,
      String messageKey, Map<String, dynamic> updates,
      {String? currentUserId,
      String? userRole,
      bool? isAttendanceGroup}) async {
    try {
      final cacheKey = _getCacheKey(chatId, chatType,
          currentUserId: currentUserId,
          userRole: userRole,
          isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);

      // Try all possible storage keys: direct key, msgid_ prefix, api_ prefix
      // Messages from API are stored under 'msgid_X' or 'api_X', not firebaseId.
      final candidateKeys = [
        messageKey,
        'msgid_$messageKey',
        'api_$messageKey',
      ];

      String? resolvedKey;
      Map? rawData;
      for (final k in candidateKeys) {
        final data = box.get(k);
        if (data != null) {
          resolvedKey = k;
          rawData = data;
          break;
        }
      }

      // Also scan box for a message whose firebaseId or msgId matches
      if (resolvedKey == null) {
        for (final entry in box.toMap().entries) {
          final val = entry.value;
          if (val is! Map) continue;
          final storedFbId = val['firebaseId']?.toString();
          final storedMsgId = val['msgId']?.toString() ?? val['msg_id']?.toString();
          if (storedFbId == messageKey || storedMsgId == messageKey) {
            resolvedKey = entry.key.toString();
            rawData = val;
            break;
          }
        }
      }

      if (resolvedKey != null && rawData != null) {
        // Deep-convert to avoid Map<dynamic,dynamic> corruption on re-store
        final msgMap = _deepConvertMap(rawData);
        // Merge status with priority — never downgrade read → delivered → sent
        if (updates.containsKey('status') && updates['status'] is Map) {
          final existingStatus = parseStatus(msgMap['status']);
          final incomingStatus = parseStatus(updates['status']);
          const priority = {'sending': -1, 'sent': 0, 'delivered': 1, 'read': 2};
          final merged = Map<String, String>.from(existingStatus);
          for (final entry in incomingStatus.entries) {
            final current = merged[entry.key];
            final currentP = priority[current] ?? 0;
            final incomingP = priority[entry.value] ?? 0;
            if (current == null || incomingP > currentP) {
              merged[entry.key] = entry.value;
            }
          }
          msgMap['status'] = merged;
          // Apply remaining updates (non-status fields)
          for (final e in updates.entries) {
            if (e.key != 'status') msgMap[e.key] = e.value;
          }
        } else {
          msgMap.addAll(updates);
        }
        await box.put(resolvedKey, msgMap);
        debugPrint('$TAG 🔄 Updated message $resolvedKey (looked up by $messageKey) in cache');
      } else {
        debugPrint('$TAG ⚠️ updateMessageInCache: key $messageKey not found in box $cacheKey');
      }

      // Also update SQLite per-user status so double tick persists across restarts
      final statusUpdate = updates['status'];
      if (statusUpdate is Map && messageKey.isNotEmpty) {
        for (final entry in statusUpdate.entries) {
          final userId = entry.key.toString();
          final userStatus = entry.value.toString();
          if (userId != 'default') {
            unawaited(_dbService.updateMessageUserStatus(messageKey, userId, userStatus));
          }
        }
      }
    } catch (e) {
      debugPrint('$TAG ❌ Failed to update message: $e');
    }
  }

  /// Replace a temporary optimistic message with the final Firebase/API message.
  Future<void> replaceMessageInCache(
    String chatId,
    String chatType,
    String oldMessageKey,
    Message newMessage, {
    String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
  }) async {
    try {
      final cacheKey = _getCacheKey(
        chatId,
        chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup,
      );
      final box = await _getMessageBox(cacheKey);
      final newKey = _getMessageStorageKey(newMessage);

      if (oldMessageKey.isNotEmpty && oldMessageKey != newKey) {
        await box.delete(oldMessageKey);
      }

      if (newKey.isNotEmpty) {
        await box.put(newKey, newMessage.toJson());
        debugPrint(
            '$TAG 🔁 Replaced cached message $oldMessageKey with $newKey');
      }
    } catch (e) {
      debugPrint('$TAG ❌ Failed to replace cached message: $e');
    }
  }

  /// Watch cache changes for real-time UI updates
  Stream<List<Message>> watchMessages(String chatId, String chatType,
      {String? currentUserId,
      String? userRole,
      bool? isAttendanceGroup}) async* {
    final cacheKey = _getCacheKey(chatId, chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup);
    final box = await _getMessageBox(cacheKey);

    yield await getCachedMessages(
      chatId,
      chatType,
      currentUserId: currentUserId,
      userRole: userRole,
      isAttendanceGroup: isAttendanceGroup,
    );

    yield* box.watch().asyncMap((_) async {
      return await getCachedMessages(chatId, chatType,
          currentUserId: currentUserId,
          userRole: userRole,
          isAttendanceGroup: isAttendanceGroup);
    });
  }

  /// Check if messages are cached (to decide whether to show loader)
  Future<bool> hasCachedMessages(String chatId, String chatType,
      {String? currentUserId,
      String? userRole,
      bool? isAttendanceGroup}) async {
    try {
      final cacheKey = _getCacheKey(chatId, chatType,
          currentUserId: currentUserId,
          userRole: userRole,
          isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);
      if (box.isNotEmpty) return true;

      final fallbackKeys = _getCacheKeyCandidates(
        chatId,
        chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup,
      ).where((key) => key != cacheKey);
      for (final fallbackKey in fallbackKeys) {
        final fallbackBox = await _getMessageBox(fallbackKey);
        if (fallbackBox.isNotEmpty) return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Clear cache for a specific conversation
  Future<void> clearCache(String chatId, String chatType,
      {String? currentUserId,
      String? userRole,
      bool? isAttendanceGroup}) async {
    try {
      final cacheKey = _getCacheKey(chatId, chatType,
          currentUserId: currentUserId,
          userRole: userRole,
          isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);
      await box.clear();

      // Clear persistent API loaded flag
      final statusBox = await Hive.openBox('chat_status');
      final statusKey = '${cacheKey}_api_loaded';
      await statusBox.delete(statusKey);

      debugPrint('$TAG 🗑️ Cleared cache for $cacheKey');
    } catch (e) {
      debugPrint('$TAG ❌ Failed to clear cache: $e');
    }
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats(String chatId, String chatType,
      {String? currentUserId,
      String? userRole,
      bool? isAttendanceGroup}) async {
    try {
      final cacheKey = _getCacheKey(chatId, chatType,
          currentUserId: currentUserId,
          userRole: userRole,
          isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);

      // Get persistent API loaded flag
      final statusBox = await Hive.openBox('chat_status');
      final statusKey = '${cacheKey}_api_loaded';
      final apiLoaded = statusBox.get(statusKey, defaultValue: false);

      return {
        'cache_key': cacheKey,
        'message_count': box.length,
        'api_loaded': apiLoaded,
        'has_cache': box.isNotEmpty,
      };
    } catch (e) {
      return {
        'error': e.toString(),
      };
    }
  }

  /// Cancel Firebase listener for a chat and stop background isolate sync
  void cancelFirebaseListener(String chatId, String chatType,
      {String? currentUserId, String? userRole, bool? isAttendanceGroup}) {
    final cacheKey = _getCacheKey(chatId, chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup);
    _firebaseListeners[cacheKey]?.cancel();
    _firebaseListeners.remove(cacheKey);

    // Stop background isolate sync
    _syncIsolateService.stopSync(chatId, chatType, isAttendanceGroup);

    debugPrint('$TAG 🛑 Cancelled Firebase listener for $cacheKey');
  }

  /// Dispose all listeners and background tasks including isolates
  void dispose() {
    for (var subscription in _firebaseListeners.values) {
      subscription.cancel();
    }
    for (var timer in _backgroundSyncTimers.values) {
      timer.cancel();
    }
    for (var timer in _firebaseOlderSyncTimers.values) {
      timer.cancel();
    }
    _firebaseListeners.clear();
    _backgroundSyncTimers.clear();
    _firebaseOlderSyncTimers.clear();
    _isSyncingBackground.clear();
    _isSyncingFirebaseOlder.clear();
    _isSyncingFirebaseRecent.clear();
    _apiLoadedFlags.clear();
    stopChatListFirebaseSync();

    // Stop all background isolate syncs
    _syncIsolateService.stopAllSyncs();

    debugPrint('$TAG 🛑 MessageSyncService disposed');
  }

  /// Force reload from API (for manual refresh)
  Future<void> forceReload(
      String chatId, String chatType, ApiService apiService,
      {String? currentUserId,
      String? userRole,
      bool? isAttendanceGroup}) async {
    final cacheKey = _getCacheKey(chatId, chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup);
    _apiLoadedFlags.remove(cacheKey);
    await clearCache(chatId, chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup);
    await loadMessagesFromApi(
      chatId: chatId,
      chatType: chatType,
      apiService: apiService,
      currentUserId: currentUserId,
      userRole: userRole,
      isAttendanceGroup: isAttendanceGroup,
      forceReload: true,
    );
    debugPrint('$TAG 🔄 Force reloaded messages for $cacheKey');
  }
}

/// Background async function to save messages to SQLite
/// Runs asynchronously without blocking UI
Future<void> _saveToDatabaseAsync({
  required List<Message> messages,
  required String chatId,
  required String chatType,
}) async {
  try {
    final dbService = MessageDatabaseService();
    final imageCacheService = ImageCacheService();
    await imageCacheService.initialize();

    // Cache images and persist local_image_path in metadata before SQLite save
    final cachedMessages = await Future.wait(messages.map((msg) async {
      if (msg.type != 'image') return msg;

      // Already has a valid local path — no re-download needed
      final existing = msg.metadata?['local_image_path']?.toString();
      if (existing != null && existing.isNotEmpty && File(existing).existsSync()) {
        return msg;
      }

      // Resolve remote URL from file_path / fileUrl
      final rawUrl = (msg.fileUrl?.isNotEmpty == true ? msg.fileUrl : msg.file_path)?.trim();
      if (rawUrl == null || rawUrl.isEmpty) return msg;

      String imageUrl;
      if (rawUrl.startsWith('http')) {
        imageUrl = rawUrl;
      } else if (rawUrl.startsWith('/storage/') || rawUrl.startsWith('storage/')) {
        imageUrl = '${ApiService.baseUrl}/${rawUrl.replaceFirst(RegExp(r'^/'), '')}';
      } else if (rawUrl.startsWith('/') && File(rawUrl).existsSync()) {
        // Already a local file — store as local_image_path directly
        final meta = Map<String, dynamic>.from(msg.metadata ?? {});
        meta['local_image_path'] = rawUrl;
        return msg.copyWith(metadata: meta);
      } else if (rawUrl.startsWith('/')) {
        imageUrl = '${ApiService.baseUrl}$rawUrl';
      } else {
        imageUrl = '${ApiService.baseUrl}/storage/$rawUrl';
      }

      final localPath = await imageCacheService.downloadAndCache(imageUrl);
      if (localPath != null && localPath != imageUrl) {
        final meta = Map<String, dynamic>.from(msg.metadata ?? {});
        meta['local_image_path'] = localPath;
        meta['remote_image_url'] = imageUrl;
        return msg.copyWith(metadata: meta);
      }
      return msg;
    }));

    await dbService.saveMessages(cachedMessages, chatId, chatType);
    debugPrint('✅ Background: Saved ${cachedMessages.length} messages to SQLite (with image cache)');
  } catch (e) {
    debugPrint('❌ Background SQLite save error: $e');
    // Silently fail - data still in Hive as fallback
  }
}
