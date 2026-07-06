import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/chat_hive_model.dart';

class HiveChatDataSource {
  // Box names are per-user so switching accounts never leaks another user's chats
  static String _chatBoxName(String userId) => 'chats_v1_$userId';
  static String _metadataBoxName(String userId) => 'chat_metadata_$userId';

  Box<ChatHiveModel>? _chatBox;
  Box? _metadataBox;
  String? _userId; // Track which user's box is currently open

  static final HiveChatDataSource _instance = HiveChatDataSource._internal();
  factory HiveChatDataSource() => _instance;
  HiveChatDataSource._internal();

  Future<void> initialize({String? userId}) async {
    final targetUserId = userId ?? _userId;
    if (targetUserId == null) {
      debugPrint('⚠️ HiveChatDataSource.initialize called without userId');
      return;
    }

    // If switching user — close old box first so we never mix data
    if (_userId != null && _userId != targetUserId) {
      debugPrint(
          '🔄 User switch detected: $_userId → $targetUserId, closing old box');
      await close();
    }

    _userId = targetUserId;

    if (_chatBox == null || !_chatBox!.isOpen) {
      _chatBox = await Hive.openBox<ChatHiveModel>(_chatBoxName(targetUserId));
      debugPrint(
          '📦 Chat box opened for user $targetUserId: ${_chatBox!.length} chats');
      await _cleanupDuplicates();
    }

    if (_metadataBox == null || !_metadataBox!.isOpen) {
      _metadataBox = await Hive.openBox(_metadataBoxName(targetUserId));
    }
  }

  /// Clear all chats for the given user and close the box (called on logout)
  Future<void> clearForUser(String userId) async {
    final boxName = _chatBoxName(userId);
    final metaBoxName = _metadataBoxName(userId);
    try {
      // Close if currently open
      if (_chatBox != null && _chatBox!.isOpen && _userId == userId) {
        await _chatBox!.clear();
        await _chatBox!.close();
        _chatBox = null;
      } else if (await Hive.boxExists(boxName)) {
        final box = await Hive.openBox<ChatHiveModel>(boxName);
        await box.clear();
        await box.close();
      }
      if (_metadataBox != null && _metadataBox!.isOpen && _userId == userId) {
        await _metadataBox!.clear();
        await _metadataBox!.close();
        _metadataBox = null;
      } else if (await Hive.boxExists(metaBoxName)) {
        final box = await Hive.openBox(metaBoxName);
        await box.clear();
        await box.close();
      }
      _userId = null;
      debugPrint('🧹 Cleared Hive chat data for user $userId');
    } catch (e) {
      debugPrint('❌ clearForUser error: $e');
    }
  }

  /// Remove duplicate chat entries (same chat with different keys)
  Future<void> _cleanupDuplicates() async {
    final seenChats = <String, String>{}; // chatId_type -> hive_key
    final keysToDelete = <String>[];

    for (final key in _chatBox!.keys) {
      final chat = _chatBox!.get(key);
      if (chat != null) {
        final uniqueKey = chat.getUniqueKey();

        if (seenChats.containsKey(uniqueKey)) {
          // Duplicate found - delete this one
          if (key != uniqueKey) {
            keysToDelete.add(key.toString());
            debugPrint('⚠️ Found duplicate: $key (keeping $uniqueKey)');
          }
        } else {
          seenChats[uniqueKey] = key.toString();
        }
      }
    }

    if (keysToDelete.isNotEmpty) {
      await _chatBox!.deleteAll(keysToDelete);
      debugPrint('🧹 Cleaned up ${keysToDelete.length} duplicate entries');
    }
  }

  List<ChatHiveModel> getAllChats() {
    _ensureInitialized();

    // Get all chats and deduplicate by unique key
    final chatMap = <String, ChatHiveModel>{};
    for (final chat in _chatBox!.values) {
      final key = chat.getUniqueKey();
      // Keep the most recent version if duplicate exists
      if (!chatMap.containsKey(key) ||
          chatMap[key]!.updatedAt.isBefore(chat.updatedAt)) {
        chatMap[key] = chat;
      }
    }

    final chats = chatMap.values.toList();

    chats.sort((a, b) {
      // Pinned chats always at top
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;

      // Use sort_time first, fallback to last_message_time, then updatedAt
      final aTime = a.sortTime ?? a.lastMessageTime ?? a.updatedAt;
      final bTime = b.sortTime ?? b.lastMessageTime ?? b.updatedAt;

      // Sort in descending order (most recent first)
      return bTime.compareTo(aTime);
    });

    if (kDebugMode) {
      debugPrint(
          '📊 getAllChats: Retrieved ${chats.length} unique chats from ${_chatBox!.length} total entries');
    }

    return chats;
  }

  ChatHiveModel? getChatById(String id, String type, dynamic attendance_group) {
    _ensureInitialized();
    final key = ChatHiveModel.buildKey(
      id: id,
      type: type,
      attendanceGroup: attendance_group,
    );
    return _chatBox!.get(key);
  }

  Future<void> saveChat(ChatHiveModel chat) async {
    _ensureInitialized();

    final key = chat.getUniqueKey();
    final existing = _chatBox!.get(key);

    if (existing == null) {
      await _chatBox!.put(key, chat);
      debugPrint('➕ Added chat: ${chat.name} (key: $key)');
    } else if (existing.needsUpdate(chat)) {
      await _chatBox!.put(key, chat);
      debugPrint('🔄 Updated chat: ${chat.name} (key: $key)');
    } else {
      debugPrint('⏭️ Skipped unchanged chat: ${chat.name}');
    }
  }

  Future<Map<String, int>> saveChatsBatch(List<ChatHiveModel> chats) async {
    _ensureInitialized();

    int added = 0;
    int updated = 0;
    int skipped = 0;

    final Map<String, ChatHiveModel> updates = {};

    for (final chat in chats) {
      final key = chat.getUniqueKey();
      final existing = _chatBox!.get(key);

      if (existing == null) {
        updates[key] = chat;
        added++;
      } else {
        // Resolve unread count:
        // If the user has already read this chat locally (lastReadAt is set and
        // is >= the API chat's lastMessageTime), keep 0 — do NOT restore the
        // badge from the API response on every sync/app-resume.
        // Otherwise use the API value (source of truth for new messages).
        int resolvedUnread;
        final localReadAt = existing.lastReadAt;
        final apiMsgTime = chat.lastMessageTime ?? chat.updatedAt;
        // lastReadAt >= lastMessageTime is the sole source of truth for read state.
        // Do NOT also require existing.unreadCount == 0 — that condition caused
        // the badge to resurrect when the API returned a stale non-zero count
        // after the user had already read the chat.
        if (localReadAt != null && !localReadAt.isBefore(apiMsgTime)) {
          // User already read up to this point — keep 0
          resolvedUnread = 0;
        } else {
          // Trust API count (source of truth for messages we haven't seen)
          resolvedUnread = chat.unreadCount;
        }

        // Preserve the most recent sortTime — local may be newer than API
        // (e.g. a message was received via Firebase after the API snapshot).
        // Using stale API sort_time would push the chat back in the list.
        final localSortTime =
            existing.sortTime ?? existing.lastMessageTime ?? existing.updatedAt;
        final apiSortTime =
            chat.sortTime ?? chat.lastMessageTime ?? chat.updatedAt;
        final resolvedSortTime =
            localSortTime.isAfter(apiSortTime) ? localSortTime : apiSortTime;

        final merged = ChatHiveModel(
          id: chat.id,
          type: chat.type,
          name: chat.name,
          profilePicture: chat.profilePicture,
          localImagePath: chat.localImagePath ?? existing.localImagePath,
          lastMessage: chat.lastMessage,
          lastMessageTime: chat.lastMessageTime,
          unreadCount: resolvedUnread,
          isPinned: chat.isPinned,
          attendanceGroup: chat.attendanceGroup,
          actualRole: chat.actualRole,
          createdAt: chat.createdAt,
          updatedAt: chat.updatedAt,
          // Preserve local lastReadAt — never overwrite with null from API
          lastReadAt: existing.lastReadAt ?? chat.lastReadAt,
          memberCount: chat.memberCount,
          groupType: chat.groupType,
          role: chat.role,
          mobile: chat.mobile,
          className: chat.className,
          sectionName: chat.sectionName,
          sortTime: resolvedSortTime,
        );
        if (existing.needsUpdate(merged)) {
          updates[key] = merged;
          updated++;
        } else {
          skipped++;
        }
      }
    }

    if (updates.isNotEmpty) {
      await _chatBox!.putAll(updates);
    }

    debugPrint(
        '💾 Batch save: $added added, $updated updated, $skipped skipped');

    return {
      'added': added,
      'updated': updated,
      'skipped': skipped,
    };
  }

  Future<void> updateChatLastMessage({
    required String chatId,
    required String chatType,
    required String lastMessage,
    required bool attendanceGroup,
    required DateTime lastMessageTime,
    bool incrementUnread = false,
  }) async {
    _ensureInitialized();

    final key = ChatHiveModel.buildKey(
      id: chatId,
      type: chatType,
      attendanceGroup: attendanceGroup,
    );
    final chat = _chatBox!.get(key);
    if (chat != null) {
      final newUnreadCount =
          incrementUnread ? chat.unreadCount + 1 : chat.unreadCount;
      final updated = chat.copyWith(
        lastMessage: lastMessage,
        lastMessageTime: lastMessageTime,
        unreadCount: newUnreadCount,
        updatedAt: DateTime.now(),
      );
      final updatedWithSort = ChatHiveModel(
        id: updated.id,
        type: updated.type,
        name: updated.name,
        profilePicture: updated.profilePicture,
        localImagePath: updated.localImagePath,
        lastMessage: updated.lastMessage,
        lastMessageTime: updated.lastMessageTime,
        unreadCount: updated.unreadCount,
        isPinned: updated.isPinned,
        attendanceGroup: updated.attendanceGroup,
        actualRole: updated.actualRole,
        createdAt: updated.createdAt,
        updatedAt: updated.updatedAt,
        lastReadAt: updated.lastReadAt,
        memberCount: updated.memberCount,
        groupType: chat.groupType,
        role: chat.role,
        mobile: chat.mobile,
        className: chat.className,
        sectionName: chat.sectionName,
        sortTime: lastMessageTime,
      );
      await _chatBox!.put(key, updatedWithSort);
      debugPrint(
          '📬 Updated $key | sortTime: $lastMessageTime | Unread: $newUnreadCount');
    } else {
      debugPrint('⚠️ Chat $key not found');
    }
  }

  Future<void> upsertChat(ChatHiveModel chat) async {
    _ensureInitialized();
    final key = chat.getUniqueKey();
    await _chatBox!.put(key, chat);
    debugPrint('💬 Upserted chat: ${chat.name} (key: $key)');
  }

  Future<void> updateUnreadCount(String chatId, String chatType, int count,
      dynamic attendance_group) async {
    _ensureInitialized();

    final key = ChatHiveModel.buildKey(
      id: chatId,
      type: chatType,
      attendanceGroup: attendance_group,
    );
    final chat = _chatBox!.get(key);
    if (chat != null) {
      // When clearing to 0 (marking as read), stamp lastReadAt with now so
      // saveChatsBatch can detect the read state survives app restarts.
      final readAt = count == 0 ? DateTime.now() : chat.lastReadAt;
      final updated = ChatHiveModel(
        id: chat.id,
        type: chat.type,
        name: chat.name,
        profilePicture: chat.profilePicture,
        localImagePath: chat.localImagePath,
        lastMessage: chat.lastMessage,
        lastMessageTime: chat.lastMessageTime,
        unreadCount: count,
        isPinned: chat.isPinned,
        attendanceGroup: chat.attendanceGroup,
        actualRole: chat.actualRole,
        createdAt: chat.createdAt,
        updatedAt: DateTime.now(),
        lastReadAt: readAt,
        memberCount: chat.memberCount,
        groupType: chat.groupType,
        role: chat.role,
        mobile: chat.mobile,
        className: chat.className,
        sectionName: chat.sectionName,
        sortTime: chat.sortTime,
      );
      await _chatBox!.put(key, updated);
      debugPrint('💬 updateUnreadCount $key → $count (lastReadAt=$readAt)');
    }
  }

  Future<void> togglePinChat(
    String chatId,
    String chatType,
    bool isPinned, {
    dynamic attendanceGroup = false,
  }) async {
    _ensureInitialized();

    final key = ChatHiveModel.buildKey(
      id: chatId,
      type: chatType,
      attendanceGroup: attendanceGroup,
    );
    final chat = _chatBox!.get(key);
    if (chat != null) {
      final updated = chat.copyWith(isPinned: isPinned);
      await _chatBox!.put(key, updated);
      debugPrint('📌 ${isPinned ? "Pinned" : "Unpinned"} chat: ${chat.name}');
    }
  }

  Future<void> deleteChat(String id, String type) async {
    _ensureInitialized();
    final regularKey = ChatHiveModel.buildKey(
      id: id,
      type: type,
      attendanceGroup: false,
    );
    final attendanceKey = ChatHiveModel.buildKey(
      id: id,
      type: type,
      attendanceGroup: true,
    );
    await _chatBox!.deleteAll([regularKey, attendanceKey]);
    debugPrint('🗑️ Deleted chat: $regularKey / $attendanceKey');
  }

  Future<void> deleteChatsBatch(List<String> keys) async {
    _ensureInitialized();
    await _chatBox!.deleteAll(keys);
    debugPrint('🗑️ Deleted ${keys.length} chats');
  }

  int getTotalUnreadCount() {
    _ensureInitialized();
    return _chatBox!.values.fold(0, (sum, chat) => sum + chat.unreadCount);
  }

  bool isEmpty() {
    _ensureInitialized();
    return _chatBox!.isEmpty;
  }

  int getChatCount() {
    _ensureInitialized();
    return _chatBox!.length;
  }

  Stream<List<ChatHiveModel>> watchAllChats() {
    _ensureInitialized();
    late final StreamController<List<ChatHiveModel>> controller;
    StreamSubscription? subscription;
    Timer? debounceTimer;

    void scheduleEmit() {
      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(milliseconds: 120), () {
        if (!controller.isClosed) {
          controller.add(getAllChats());
        }
      });
    }

    controller = StreamController<List<ChatHiveModel>>(
      onListen: () {
        subscription = _chatBox!.watch().listen(
          (_) => scheduleEmit(),
          onError: (error, stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
        );
      },
      onCancel: () async {
        debounceTimer?.cancel();
        await subscription?.cancel();
      },
    );

    return controller.stream;
  }

  DateTime? getLastSyncTime() {
    final timestamp = _metadataBox?.get('last_sync_time');
    return timestamp != null ? DateTime.tryParse(timestamp) : null;
  }

  Future<void> setLastSyncTime(DateTime time) async {
    await _metadataBox?.put('last_sync_time', time.toIso8601String());
  }

  Future<void> clearAllChats() async {
    _ensureInitialized();
    await _chatBox!.clear();
    debugPrint('🧹 Cleared all chats');
  }

  Future<void> close() async {
    await _chatBox?.close();
    await _metadataBox?.close();
    _chatBox = null;
    _metadataBox = null;
  }

  void _ensureInitialized() {
    if (_chatBox == null || !_chatBox!.isOpen) {
      throw Exception(
          'HiveChatDataSource not initialized. Call initialize() first.');
    }
  }
}
