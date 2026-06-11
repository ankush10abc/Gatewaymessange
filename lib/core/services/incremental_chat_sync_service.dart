import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../services/api_service_simple.dart';
import '../models/chat_hive_model.dart';
import '../data/hive_chat_data_source.dart';
import '../services/image_cache_service.dart';

/// Incremental Chat Sync Service
/// Uses /api/chats/sync to fetch only changed chats since last sync
/// Reduces bandwidth and improves performance compared to full chat list fetch
class IncrementalChatSyncService {
  static final IncrementalChatSyncService _instance = IncrementalChatSyncService._internal();
  factory IncrementalChatSyncService() => _instance;
  IncrementalChatSyncService._internal();

  final HiveChatDataSource _hiveDataSource = HiveChatDataSource();
  final ImageCacheService _imageCacheService = ImageCacheService();
  Box? _metadataBox;

  Future<void> initialize() async {
    await _hiveDataSource.initialize();
    await _imageCacheService.initialize();
    _metadataBox = await Hive.openBox('incremental_sync_metadata');
    debugPrint('✅ IncrementalChatSyncService initialized');
  }

  /// Sync chats incrementally (only fetch changes since last sync)
  Future<bool> syncChats(ApiService apiService) async {
    try {
      // Get last sync time (null = first sync, fetch all)
      final lastSyncTime = _getLastSyncTime();
      
      if (lastSyncTime == null) {
        debugPrint('🔄 First sync - fetching all chats');
      } else {
        final timeSinceSync = DateTime.now().difference(lastSyncTime);
        debugPrint('🔄 Incremental sync - last synced ${timeSinceSync.inMinutes} minutes ago');
      }

      // Call incremental sync API
      final response = await apiService.syncChats(
        since: lastSyncTime,
        limit: 100,
      );

      if (response['success'] != true) {
        debugPrint('❌ Chat sync failed: ${response['message']}');
        return false;
      }

      final data = response['data'];
      final newChats = data['new_chats'] as List? ?? [];
      final updatedChats = data['updated_chats'] as List? ?? [];
      final deletedIds = data['deleted_chat_ids'] as List? ?? [];
      final syncedAt = data['synced_at'];

      debugPrint('📥 Sync result: ${newChats.length} new, ${updatedChats.length} updated, ${deletedIds.length} deleted');

      // Process new chats
      for (final chatJson in newChats) {
        await _processChatData(chatJson, isNew: true);
      }

      // Process updated chats
      for (final chatJson in updatedChats) {
        await _processChatData(chatJson, isNew: false);
      }

      // Delete removed chats
      for (final chatId in deletedIds) {
        await _deleteChatFromHive(chatId.toString());
      }

      // Save sync timestamp
      await _saveLastSyncTime(syncedAt);

      debugPrint('✅ Incremental sync completed successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Incremental sync error: $e');
      return false;
    }
  }

  /// Process and save chat data to Hive
  Future<void> _processChatData(Map<String, dynamic> chatJson, {required bool isNew}) async {
    try {
      final chatId = chatJson['id'].toString();
      final chatType = chatJson['type']?.toString() ?? 'user';
      final attendanceGroup = chatJson['attendance_group'] ?? false;

      // Download and cache profile image if available
      String? localImagePath;
      final profilePicture = chatJson['profile_picture'];
      if (profilePicture != null && profilePicture.toString().isNotEmpty) {
        localImagePath = await _imageCacheService.downloadAndCache(profilePicture);
      }

      // Parse timestamps
      DateTime? lastMessageTime;
      if (chatJson['last_message_time'] != null) {
        try {
          lastMessageTime = DateTime.parse(chatJson['last_message_time']);
        } catch (e) {
          debugPrint('⚠️ Failed to parse last_message_time for chat $chatId');
        }
      }

      DateTime? lastReadAt;
      if (chatJson['last_read_at'] != null) {
        try {
          lastReadAt = DateTime.parse(chatJson['last_read_at']);
        } catch (e) {
          debugPrint('⚠️ Failed to parse last_read_at for chat $chatId');
        }
      }

      DateTime createdAt = DateTime.now();
      if (chatJson['created_at'] != null) {
        try {
          createdAt = DateTime.parse(chatJson['created_at']);
        } catch (e) {
          debugPrint('⚠️ Failed to parse created_at for chat $chatId');
        }
      }

      DateTime updatedAt = DateTime.now();
      if (chatJson['updated_at'] != null) {
        try {
          updatedAt = DateTime.parse(chatJson['updated_at']);
        } catch (e) {
          debugPrint('⚠️ Failed to parse updated_at for chat $chatId');
        }
      }

      // Get existing chat if updating
      ChatHiveModel? existingChat;
      if (!isNew) {
        existingChat = _hiveDataSource.getChatById(chatId, chatType,attendanceGroup);
      }

      // Create ChatHiveModel
      final chat = ChatHiveModel(
        id: chatId,
        type: chatType,
        name: chatJson['name']?.toString() ?? 'Unknown',
        profilePicture: profilePicture?.toString(),
        localImagePath: localImagePath ?? existingChat?.localImagePath,
        lastMessage: chatJson['last_message']?.toString(),
        lastMessageTime: lastMessageTime,
        unreadCount: chatJson['unread_count'] ?? existingChat?.unreadCount ?? 0,
        isPinned: chatJson['is_pinned'] ?? existingChat?.isPinned ?? false,
        attendanceGroup: chatJson['attendance_group'],
        actualRole: chatJson['actual_role']?.toString(),
        createdAt: isNew ? createdAt : (existingChat?.createdAt ?? createdAt),
        updatedAt: updatedAt,
        lastReadAt: lastReadAt ?? existingChat?.lastReadAt,
        memberCount: chatJson['member_count'],
        groupType: chatJson['group_type']?.toString(),
        role: chatJson['role']?.toString(),
        mobile: chatJson['mobile']?.toString(),
        className: chatJson['class_name']?.toString(),
        sectionName: chatJson['section_name']?.toString(),
        sortTime: lastMessageTime ?? updatedAt,
      );

      // Save to Hive
      await _hiveDataSource.upsertChat(chat);
      
      if (isNew) {
        debugPrint('➕ Added new chat: ${chat.name} ($chatType/$chatId)');
      } else {
        debugPrint('🔄 Updated chat: ${chat.name} ($chatType/$chatId)');
      }
    } catch (e) {
      debugPrint('❌ Error processing chat ${chatJson['id']}: $e');
    }
  }

  /// Delete chat from Hive
  Future<void> _deleteChatFromHive(String chatId) async {
    try {
      // Try both user and group types since we don't know the type
      await _hiveDataSource.deleteChat(chatId, 'user');
      await _hiveDataSource.deleteChat(chatId, 'group');
      debugPrint('🗑️ Deleted chat: $chatId');
    } catch (e) {
      debugPrint('❌ Error deleting chat $chatId: $e');
    }
  }

  /// Get last sync timestamp
  DateTime? _getLastSyncTime() {
    final timestamp = _metadataBox?.get('last_incremental_sync');
    if (timestamp == null) return null;
    
    try {
      return DateTime.parse(timestamp);
    } catch (e) {
      debugPrint('⚠️ Failed to parse last sync time: $timestamp');
      return null;
    }
  }

  /// Save sync timestamp
  Future<void> _saveLastSyncTime(String timestamp) async {
    await _metadataBox?.put('last_incremental_sync', timestamp);
    debugPrint('💾 Saved sync timestamp: $timestamp');
  }

  /// Force full resync (clears last sync time)
  Future<void> forceFullResync() async {
    await _metadataBox?.delete('last_incremental_sync');
    debugPrint('🔄 Forced full resync - cleared last sync time');
  }

  /// Get statistics
  Map<String, dynamic> getStats() {
    final lastSync = _getLastSyncTime();
    final chatCount = _hiveDataSource.getChatCount();
    
    return {
      'last_sync': lastSync,
      'minutes_since_sync': lastSync != null 
          ? DateTime.now().difference(lastSync).inMinutes 
          : null,
      'cached_chats': chatCount,
    };
  }
}
