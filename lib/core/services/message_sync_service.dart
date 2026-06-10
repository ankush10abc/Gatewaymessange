import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/message_model.dart';
import 'api_service_simple.dart';
import 'firebase_realtime_service.dart';

/// HIGH-PERFORMANCE MESSAGE CACHING SERVICE
/// 
/// Storage Strategy:
/// - One-to-one chats: messages_user_{chatId}_{currentUserId}_{role}_{attendance}
/// - Group chats: messages_group_{chatId}_{role}_{attendance}
/// 
/// Features:
/// ✅ Instant load from cache (<100ms)
/// ✅ API called only ONCE per conversation
/// ✅ Role-based message separation
/// ✅ Attendance group separation
/// ✅ Automatic background sync
/// ✅ Firebase real-time updates
/// ✅ Offline support
class MessageSyncService {
  static final MessageSyncService _instance = MessageSyncService._internal();
  factory MessageSyncService() => _instance;
  MessageSyncService._internal();

  final Map<String, Box<Map>> _messageBoxes = {};
  final Map<String, StreamSubscription> _firebaseListeners = {};
  final Map<String, bool> _apiLoadedFlags = {}; // Track if API was called
  final Map<String, Timer> _backgroundSyncTimers = {}; // Track background sync timers
  final Map<String, bool> _isSyncingBackground = {}; // Prevent concurrent syncs
  final Map<String, Timer> _firebaseOlderSyncTimers = {}; // Track Firebase older message sync
  final Map<String, bool> _isSyncingFirebaseOlder = {}; // Prevent concurrent Firebase older syncs
  
  /// Get unique cache key based on chat type, IDs, role, and attendance_group
  String _getCacheKey(String chatId, String chatType, {String? currentUserId, String? userRole, bool? isAttendanceGroup}) {
    final role = (userRole ?? 'user').toLowerCase();
    final attendanceSuffix = (isAttendanceGroup == true) ? '_attendance' : '';
    
    if (chatType == 'group') {
      return 'messages_group_${chatId}_${role}$attendanceSuffix';
    } else {
      // For one-to-one: include both user IDs and role for uniqueness
      return 'messages_user_${chatId}_${currentUserId ?? "unknown"}_${role}$attendanceSuffix';
    }
  }

  /// Initialize message cache box for a chat
  Future<Box<Map>> _getMessageBox(String cacheKey) async {
    if (_messageBoxes.containsKey(cacheKey)) {
      return _messageBoxes[cacheKey]!;
    }
    
    final box = await Hive.openBox<Map>(cacheKey);
    _messageBoxes[cacheKey] = box;
    debugPrint('📦 Opened message box: $cacheKey');
    return box;
  }

  /// STEP 1: Get cached messages instantly (0ms delay)
  /// Returns empty list if no cache exists
  Future<List<Message>> getCachedMessages(String chatId, String chatType, {String? currentUserId, String? userRole, bool? isAttendanceGroup}) async {
    try {
      final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);
      
      if (box.isEmpty) {
        debugPrint('💾 No cached messages for $cacheKey (first time load)');
        return [];
      }
      
      final messages = <Message>[];
      for (var entry in box.values) {
        try {
          final msgMap = Map<String, dynamic>.from(entry);
          messages.add(Message.fromJson(msgMap));
        } catch (e) {
          debugPrint('⚠️ Failed to parse cached message: $e');
        }
      }
      
      // Sort based on attendance group flag
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      debugPrint('✅ Loaded ${messages.length} cached messages for $cacheKey (instant, attendance: ${isAttendanceGroup ?? false})');
      return messages;
    } catch (e) {
      debugPrint('❌ Cache load error: $e');
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
    final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    
    // Check if API was already called for this conversation
    if (!forceReload && _apiLoadedFlags[cacheKey] == true) {
      debugPrint('⏭️ API already loaded for $cacheKey, skipping API call');
      final cachedMessages = await getCachedMessages(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
      return {
        'messages': cachedMessages,
        'user': null,
        'has_more': false,
        'from_cache': true,
      };
    }
    
    try {
      debugPrint('🌐 Loading messages from API for $cacheKey (first time)');
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
      
      // Mark as loaded so API won't be called again
      _apiLoadedFlags[cacheKey] = true;
      debugPrint('✅ API loaded and cached for $cacheKey (won\'t call API again, attendance: ${isAttendanceGroup ?? false})');
      
      return result;
    } catch (e) {
      debugPrint('❌ API load error for $cacheKey: $e');
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
        final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
        await _cacheMessages(cacheKey, response.data, append: true);
        debugPrint('📄 Loaded page $page with ${response.data.length} messages (attendance: ${isAttendanceGroup ?? false})');
        return response.data;
      } else {
        final response = await apiService.getConversation(id, page, limit);
        final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
        await _cacheMessages(cacheKey, response.data, append: true);
        debugPrint('📄 Loaded page $page with ${response.data.length} messages (attendance: ${isAttendanceGroup ?? false})');
        return response.data;
      }
    } catch (e) {
      debugPrint('❌ Load more error: $e');
      return [];
    }
  }

  /// Cache messages to Hive
  Future<void> _cacheMessages(String cacheKey, List<Message> messages, {bool append = false}) async {
    try {
      final box = await _getMessageBox(cacheKey);
      
      final Map<String, Map> updates = {};
      for (final message in messages) {
        // Use firebaseId as primary key, fallback to msgId or id
        final key = message.firebaseId ?? message.msgId ?? message.id;
        if (key.isNotEmpty && key != '0') {
          updates[key] = message.toJson();
        }
      }
      
      if (append) {
        await box.putAll(updates);
      } else {
        // First load: clear and write
        await box.clear();
        await box.putAll(updates);
      }
      
      debugPrint('💾 Cached ${updates.length} messages for $cacheKey');
    } catch (e) {
      debugPrint('❌ Cache save error: $e');
    }
  }

  /// Setup Firebase real-time listener with auto-caching (background sync)
  StreamSubscription<List<Message>> setupFirebaseListener({
    required String chatId,
    required String chatType,
    required String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
    String? otherUserId,
    required Function(List<Message>) onMessages,
  }) {
    final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    
    // Cancel existing listener
    _firebaseListeners[cacheKey]?.cancel();
    
    final subscription = FirebaseRealtimeService.getMessagesStreamLimited(
      chatId,
      chatType,
      50,
      currentUserId: currentUserId,
      otherUserId: otherUserId,
    ).listen((messages) {
      // Auto-cache Firebase messages in background without blocking UI
      _cacheMessagesRealtimeBackground(cacheKey, messages);
      onMessages(messages);
    });
    
    _firebaseListeners[cacheKey] = subscription;
    debugPrint('👂 Started Firebase listener for $cacheKey');
    
    return subscription;
  }

  /// Cache Firebase messages in background (non-blocking)
  Future<void> _cacheMessagesRealtimeBackground(String cacheKey, List<Message> messages) async {
    // Update local cache immediately for instant UI updates (non-blocking)
    try {
      final box = await _getMessageBox(cacheKey);
      for (final message in messages) {
        final key = message.firebaseId ?? message.msgId ?? message.id;
        if (key.isNotEmpty && key != '0') {
          box.put(key, message.toJson()); // Non-blocking put
        }
      }
      debugPrint('🔄 Background cached ${messages.length} Firebase messages');
    } catch (e) {
      debugPrint('❌ Realtime cache error: $e');
    }
  }

  /// Add single message to cache (for optimistic updates)
  Future<void> addMessageToCache(String chatId, String chatType, Message message, {String? currentUserId, String? userRole, bool? isAttendanceGroup}) async {
    try {
      final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);
      final key = message.firebaseId ?? message.msgId ?? message.id;
      
      if (key.isNotEmpty) {
        box.put(key, message.toJson()); // Non-blocking
        debugPrint('📝 Added message $key to cache');
      }
    } catch (e) {
      debugPrint('❌ Failed to cache message: $e');
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
    final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    
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
      );
    });
    
    // Start periodic Firebase older messages sync (every 45 seconds)
    _firebaseOlderSyncTimers[cacheKey] = Timer.periodic(const Duration(seconds: 45), (timer) {
      _syncFirebaseOlderMessages(
        chatId: chatId,
        chatType: chatType,
        currentUserId: currentUserId,
        userRole: userRole,
        isAttendanceGroup: isAttendanceGroup,
        otherUserId: otherUserId,
      );
    });
    
    debugPrint('⏰ Started background sync for $cacheKey (API: ${interval.inSeconds}s, Firebase older: 45s)');
  }
  
  /// Sync with API in background (non-blocking)
  Future<void> _syncWithApiBackground({
    required String chatId,
    required String chatType,
    required ApiService apiService,
    String? currentUserId,
    String? userRole,
    bool? isAttendanceGroup,
  }) async {
    final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    
    // Prevent concurrent syncs
    if (_isSyncingBackground[cacheKey] == true) {
      debugPrint('⏭️ Background sync already in progress for $cacheKey');
      return;
    }
    
    _isSyncingBackground[cacheKey] = true;
    
    try {
      final id = int.parse(chatId);
      
      // Fetch latest messages from API
      // List<Message> latestMessages;
      // if (chatType == 'group') {
      //   final response = await apiService.getGroupMessages(id, 1, 20);
      //   latestMessages = response.data;
      // } else {
      //   final response = await apiService.getConversation(id, 1, 20);
      //   latestMessages = response.data;
      // }
      
      // Update cache in background
      final box = await _getMessageBox(cacheKey);
      // for (final message in latestMessages) {
      //   final key = message.firebaseId ?? message.msgId ?? message.id;
      //   if (key.isNotEmpty && key != '0') {
      //     box.put(key, message.toJson()); // Non-blocking
      //   }
      // }
      //
      // debugPrint('🔄 Background synced ${latestMessages.length} messages from API for $cacheKey');
    } catch (e) {
      debugPrint('❌ Background API sync error: $e');
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
    final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    
    // Prevent concurrent Firebase older syncs
    if (_isSyncingFirebaseOlder[cacheKey] == true) {
      debugPrint('⏭️ Firebase older sync already in progress for $cacheKey');
      return;
    }
    
    _isSyncingFirebaseOlder[cacheKey] = true;
    
    try {
      // Get oldest message from cache
      final cachedMessages = await getCachedMessages(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
      
      if (cachedMessages.isEmpty) {
        debugPrint('⏭️ No cached messages for $cacheKey, skipping older sync');
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
        otherUserId: otherUserId ?? '0',
      );
      
      if (olderMessages.isEmpty) {
        debugPrint('✅ No more older messages in Firebase for $cacheKey');
        _isSyncingFirebaseOlder[cacheKey] = false;
        return;
      }
      
      // Cache older messages in background
      final box = await _getMessageBox(cacheKey);
      for (final message in olderMessages) {
        final key = message.firebaseId ?? message.msgId ?? message.id;
        if (key.isNotEmpty && key != '0') {
          box.put(key, message.toJson()); // Non-blocking
        }
      }
      
      debugPrint('🔄 Background synced ${olderMessages.length} older Firebase messages for $cacheKey');
    } catch (e) {
      debugPrint('❌ Firebase older sync error: $e');
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
    final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    
    try {
      // Fetch older messages from Firebase
      final olderMessages = await FirebaseRealtimeService.getOlderMessages(
        chatId,
        chatType,
        beforeTimestamp,
        limit,
        currentUserId: currentUserId,
        otherUserId: otherUserId ?? '0',
      );
      
      if (olderMessages.isEmpty) {
        debugPrint('✅ No more older messages in Firebase for $cacheKey');
        return [];
      }
      
      // Cache older messages immediately
      final box = await _getMessageBox(cacheKey);
      for (final message in olderMessages) {
        final key = message.firebaseId ?? message.msgId ?? message.id;
        if (key.isNotEmpty && key != '0') {
          box.put(key, message.toJson()); // Non-blocking
        }
      }
      
      debugPrint('📥 Synced ${olderMessages.length} older messages from Firebase to cache');
      return olderMessages;
    } catch (e) {
      debugPrint('❌ Sync older Firebase messages error: $e');
      return [];
    }
  }
  
  /// Stop background sync
  void stopBackgroundSync(String chatId, String chatType, {String? currentUserId, String? userRole, bool? isAttendanceGroup}) {
    final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    _backgroundSyncTimers[cacheKey]?.cancel();
    _backgroundSyncTimers.remove(cacheKey);
    _firebaseOlderSyncTimers[cacheKey]?.cancel();
    _firebaseOlderSyncTimers.remove(cacheKey);
    _isSyncingBackground.remove(cacheKey);
    _isSyncingFirebaseOlder.remove(cacheKey);
    debugPrint('🛑 Stopped background sync for $cacheKey');
  }

  /// Update message in cache (e.g., status update)
  Future<void> updateMessageInCache(String chatId, String chatType, String messageKey, Map<String, dynamic> updates, {String? currentUserId, String? userRole, bool? isAttendanceGroup}) async {
    try {
      final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);
      
      final messageData = box.get(messageKey);
      if (messageData != null) {
        final msgMap = Map<String, dynamic>.from(messageData);
        msgMap.addAll(updates);
        box.put(messageKey, msgMap); // Non-blocking
        debugPrint('🔄 Updated message $messageKey in cache');
      }
    } catch (e) {
      debugPrint('❌ Failed to update message: $e');
    }
  }

  /// Watch cache changes for real-time UI updates
  Stream<List<Message>> watchMessages(String chatId, String chatType, {String? currentUserId, String? userRole, bool? isAttendanceGroup}) async* {
    final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    final box = await _getMessageBox(cacheKey);
    
    yield* box.watch().asyncMap((_) async {
      return await getCachedMessages(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    });
  }

  /// Check if messages are cached (to decide whether to show loader)
  Future<bool> hasCachedMessages(String chatId, String chatType, {String? currentUserId, String? userRole, bool? isAttendanceGroup}) async {
    try {
      final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);
      return box.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Clear cache for a specific conversation
  Future<void> clearCache(String chatId, String chatType, {String? currentUserId, String? userRole, bool? isAttendanceGroup}) async {
    try {
      final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);
      await box.clear();
      _apiLoadedFlags.remove(cacheKey);
      debugPrint('🗑️ Cleared cache for $cacheKey');
    } catch (e) {
      debugPrint('❌ Failed to clear cache: $e');
    }
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats(String chatId, String chatType, {String? currentUserId, String? userRole, bool? isAttendanceGroup}) async {
    try {
      final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
      final box = await _getMessageBox(cacheKey);
      final apiLoaded = _apiLoadedFlags[cacheKey] ?? false;
      
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

  /// Cancel Firebase listener for a chat
  void cancelFirebaseListener(String chatId, String chatType, {String? currentUserId, String? userRole, bool? isAttendanceGroup}) {
    final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    _firebaseListeners[cacheKey]?.cancel();
    _firebaseListeners.remove(cacheKey);
    debugPrint('🛑 Cancelled Firebase listener for $cacheKey');
  }

  /// Dispose all listeners and background tasks
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
    _apiLoadedFlags.clear();
    debugPrint('🛑 MessageSyncService disposed');
  }
  
  /// Force reload from API (for manual refresh)
  Future<void> forceReload(String chatId, String chatType, ApiService apiService, {String? currentUserId, String? userRole, bool? isAttendanceGroup}) async {
    final cacheKey = _getCacheKey(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    _apiLoadedFlags.remove(cacheKey);
    await clearCache(chatId, chatType, currentUserId: currentUserId, userRole: userRole, isAttendanceGroup: isAttendanceGroup);
    await loadMessagesFromApi(
      chatId: chatId,
      chatType: chatType,
      apiService: apiService,
      currentUserId: currentUserId,
      userRole: userRole,
      isAttendanceGroup: isAttendanceGroup,
      forceReload: true,
    );
    debugPrint('🔄 Force reloaded messages for $cacheKey');
  }
}
