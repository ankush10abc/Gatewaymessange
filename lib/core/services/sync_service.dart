import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../services/api_service_simple.dart';
import '../models/message_model.dart';
import '../models/chat_list_model.dart';

/// Service for handling incremental sync with backend
class SyncService {
  final ApiService _apiService;
  static late Box _syncMetaBox;
  static late Box _messagesBox;
  static late Box _chatsBox;
  static bool _isInitialized = false;

  SyncService(this._apiService);

  static Future<void> initialize() async {
    if (!_isInitialized) {
      _syncMetaBox = await Hive.openBox('sync_metadata');
      _messagesBox = await Hive.openBox('messages_cache');
      _chatsBox = await Hive.openBox('chats_cache');
      _isInitialized = true;
    }
  }

  /// Sync messages for a specific chat
  Future<List<Message>> syncChatMessages({
    required String chatId,
    required String chatType,
  }) async {
    try {
      final lastSyncKey = 'last_sync_${chatType}_$chatId';
      final lastSync = _syncMetaBox.get(lastSyncKey);
      final since = lastSync != null 
          ? DateTime.parse(lastSync) 
          : DateTime.now().subtract(const Duration(days: 30));

      debugPrint('🔄 Syncing messages for $chatType:$chatId since ${since.toIso8601String()}');

      final response = await _apiService.syncMessages(
        chatId: chatId,
        chatType: chatType,
        since: since,
        limit: 100,
      );

      final data = response['data'];
      final newMessages = (data['messages'] as List)
          .map((json) => Message.fromJson(json))
          .toList();
      final deletedIds = List<String>.from(data['deleted_message_ids'] ?? []);
      final updatedMessages = (data['updated_messages'] as List)
          .map((json) => Message.fromJson(json))
          .toList();

      // Update local cache
      final cacheKey = '${chatType}_$chatId';
      final cachedMessages = await getCachedMessages(cacheKey);

      // Remove deleted messages
      cachedMessages.removeWhere((m) => deletedIds.contains(m.id));

      // Update existing messages
      for (final updated in updatedMessages) {
        final index = cachedMessages.indexWhere((m) => m.id == updated.id);
        if (index != -1) {
          cachedMessages[index] = updated;
        }
      }

      // Add new messages
      cachedMessages.addAll(newMessages);

      // Sort by timestamp
      cachedMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Save to cache
      await saveCachedMessages(cacheKey, cachedMessages);

      // Update last sync time
      await _syncMetaBox.put(lastSyncKey, data['synced_at']);

      debugPrint('✅ Synced ${newMessages.length} new, ${updatedMessages.length} updated, ${deletedIds.length} deleted');

      return cachedMessages;
    } catch (e) {
      debugPrint('❌ Sync error: $e');
      // Return cached messages on error
      return await getCachedMessages('${chatType}_$chatId');
    }
  }

  /// Sync chat list
  Future<List<ChatModel>> syncChatList() async {
    try {
      final lastSync = _syncMetaBox.get('last_chat_list_sync');
      final since = lastSync != null ? DateTime.parse(lastSync) : null;

      debugPrint('🔄 Syncing chat list ${since != null ? 'since ${since.toIso8601String()}' : '(full sync)'}');

      final response = await _apiService.syncChats(since: since);
      final data = response['data'];

      final newChats = (data['new_chats'] as List)
          .map((json) => ChatModel.fromJson(json))
          .toList();
      final updatedChats = (data['updated_chats'] as List)
          .map((json) => ChatModel.fromJson(json))
          .toList();
      final deletedIds = List<String>.from(data['deleted_chat_ids'] ?? []);

      // Get cached chat list
      final cachedChats = await getCachedChatList();

      // Remove deleted chats
      cachedChats.removeWhere((c) => deletedIds.contains(c.id.toString()));

      // Update existing chats
      for (final updated in updatedChats) {
        final index = cachedChats.indexWhere((c) => c.id == updated.id);
        if (index != -1) {
          cachedChats[index] = updated;
        }
      }

      // Add new chats
      cachedChats.addAll(newChats);

      // Sort by last message time
      cachedChats.sort((a, b) {
        final aTime = a.lastMessageTime ?? DateTime(2000);
        final bTime = b.lastMessageTime ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      // Save to cache
      await _saveCachedChatList(cachedChats);

      // Update last sync time
      await _syncMetaBox.put('last_chat_list_sync', data['synced_at']);

      debugPrint('✅ Synced ${newChats.length} new, ${updatedChats.length} updated, ${deletedIds.length} deleted chats');

      return cachedChats;
    } catch (e) {
      debugPrint('❌ Chat list sync error: $e');
      // Return cached list on error
      return await getCachedChatList();
    }
  }

  /// Get cached messages for a chat (public for external use)
  Future<List<Message>> getCachedMessages(String cacheKey) async {
    final cached = _messagesBox.get(cacheKey);
    if (cached == null) return [];
    
    return (cached as List)
        .map((json) => Message.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  /// Save messages to cache (public for external use)
  Future<void> saveCachedMessages(String cacheKey, List<Message> messages) async {
    final jsonList = messages.map((m) => m.toJson()).toList();
    await _messagesBox.put(cacheKey, jsonList);
  }

  /// Get cached chat list
  Future<List<ChatModel>> getCachedChatList() async {
    final cached = _chatsBox.get('chat_list');
    if (cached == null) return [];
    
    return (cached as List)
        .map((json) => ChatModel.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  /// Save chat list to cache
  Future<void> _saveCachedChatList(List<ChatModel> chats) async {
    final jsonList = chats.map((c) => c.toJson()).toList();
    await _chatsBox.put('chat_list', jsonList);
  }

  /// Batch mark messages as read
  Future<void> batchMarkAsRead({
    required List<int> messageIds,
    required String chatId,
    required String chatType,
  }) async {
    try {
      debugPrint('📖 Marking ${messageIds.length} messages as read');
      await _apiService.batchMarkAsRead(
        messageIds: messageIds,
        chatId: chatId,
        chatType: chatType,
      );
      debugPrint('✅ Messages marked as read');
    } catch (e) {
      debugPrint('❌ Batch mark as read error: $e');
      rethrow;
    }
  }

  /// Get last sync time for a chat
  DateTime? getLastSyncTime(String chatId, String chatType) {
    final lastSyncKey = 'last_sync_${chatType}_$chatId';
    final lastSync = _syncMetaBox.get(lastSyncKey);
    return lastSync != null ? DateTime.parse(lastSync) : null;
  }

  /// Force full resync (clear cache and sync from scratch)
  Future<void> forceFullResync() async {
    debugPrint('🔄 Force full resync...');
    await _syncMetaBox.clear();
    await _messagesBox.clear();
    await _chatsBox.clear();
    await syncChatList();
    debugPrint('✅ Full resync complete');
  }

  /// Clear all cached data
  static Future<void> clearCache() async {
    if (_isInitialized) {
      await _syncMetaBox.clear();
      await _messagesBox.clear();
      await _chatsBox.clear();
      debugPrint('🗑️ Cache cleared');
    }
  }
}
