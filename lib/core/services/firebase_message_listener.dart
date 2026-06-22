import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hive_chat_data_source.dart';
import '../models/chat_hive_model.dart';
import '../../shared/providers/optimized_chat_provider.dart';

class FirebaseMessageListener {
  static WidgetRef? _ref;
  static String? _currentChatId;

  // Throttle background-open full API refresh
  static DateTime? _lastRefreshTime;
  static const _refreshCooldown = Duration(seconds: 10);

  static void init(WidgetRef ref) {
    _ref = ref;

    // Single foreground listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('📥 [FML] Foreground notification: ${message.data}');
      try {
        await ref.read(optimizedChatProvider.notifier).refresh();
      } catch (e) {
        print(e);
      }
      _handleMessage(message.data, openedFromBackground: false);

    });

    // Background-opened: user tapped notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔔 [FML] Notification opened app: ${message.data}');
      _handleMessage(message.data, openedFromBackground: true);
    });
  }

  static void setCurrentChatId(String? chatId) {
    _currentChatId = chatId;
  }

  static void _handleMessage(
    Map<String, dynamic> data, {
    required bool openedFromBackground,
  }) {
    if (_ref == null) return;

    try {
      // Parse chatId — FCM payload uses different field names for group vs user chats
      final chatId = _parseChatId(data);
      if (chatId == null || chatId.isEmpty) {
        debugPrint('⚠️ [FML] No chatId found in payload: $data');
        return;
      }

      // Parse chatType
      final chatType = _parseChatType(data);

      // Parse message text
      final messageText = data['message']?.toString() ??
          data['body']?.toString() ??
          data['notification_body']?.toString() ??
          '';

      // Parse attendanceGroup — FCM payload may send group_type instead of attendance_group
      final attendanceGroup = _parseAttendanceGroup(data);

      // Whether to increment unread: only if this chat is not currently open
      final isIncoming = _currentChatId != chatId;

      debugPrint('📬 [FML] chatId=$chatId type=$chatType attendance=$attendanceGroup incoming=$isIncoming msg="$messageText"');

      // Update Hive + provider state immediately
      _updateUnreadBadge(
        chatId: chatId,
        chatType: chatType,
        attendanceGroup: attendanceGroup,
        messageText: messageText,
        isIncoming: isIncoming,
      );

      // On background-open tap, do one throttled API refresh for full sync
      if (openedFromBackground) {
        _throttledRefresh();
      }
    } catch (e) {
      debugPrint('❌ [FML] Error: $e');
    }
  }

  /// Parse chatId from all known FCM payload field names
  static String? _parseChatId(Map<String, dynamic> data) {
    // Explicit chat_id takes priority
    final chatId = data['chat_id']?.toString();
    if (chatId != null && chatId.isNotEmpty && chatId != 'null') return chatId;

    // Group messages use group_id
    final groupId = data['group_id']?.toString();
    if (groupId != null && groupId.isNotEmpty && groupId != 'null') return groupId;

    // User/private messages — use sender_id as chatId (the other user's id)
    final senderId = data['sender_id']?.toString();
    if (senderId != null && senderId.isNotEmpty && senderId != 'null') return senderId;

    // Fallback fields
    return data['receiver_id']?.toString().isNotEmpty == true
        ? data['receiver_id'].toString()
        : null;
  }

  /// Parse chatType from all known FCM payload field names
  static String _parseChatType(Map<String, dynamic> data) {
    final explicit = data['chat_type']?.toString();
    if (explicit != null && explicit.isNotEmpty && explicit != 'null') {
      return explicit;
    }
    // If group_id is present it's a group message
    final groupId = data['group_id']?.toString();
    if (groupId != null && groupId.isNotEmpty && groupId != 'null') {
      return 'group';
    }
    return 'user';
  }

  /// Parse attendanceGroup — checks attendance_group field AND group_type field
  /// because FCM payloads for attendance groups send group_type: attendance_group
  static bool _parseAttendanceGroup(Map<String, dynamic> data) {
    // Explicit attendance_group field takes priority
    final explicit = data['attendance_group'];
    if (explicit != null) {
      return ChatHiveModel.parseAttendanceGroup(explicit);
    }
    // Derive from group_type: attendance_group means it IS an attendance group
    final groupType = data['group_type']?.toString().toLowerCase();
    return groupType == 'attendance_group' || groupType == 'attendance';
  }

  static void _updateUnreadBadge({
    required String chatId,
    required String chatType,
    required bool attendanceGroup,
    required String messageText,
    required bool isIncoming,
  }) {
    if (_ref == null) return;

    final hive = HiveChatDataSource();

    // Try exact key first, then fallback to the opposite attendanceGroup value.
    // This handles cases where FCM payload attendance_group differs from stored key.
    ChatHiveModel? existing = hive.getChatById(chatId, chatType, attendanceGroup);
    bool resolvedAttendance = attendanceGroup;

    if (existing == null) {
      // Try opposite attendanceGroup — FCM may omit the field for attendance groups
      existing = hive.getChatById(chatId, chatType, !attendanceGroup);
      if (existing != null) {
        resolvedAttendance = !attendanceGroup;
        debugPrint('🔄 [FML] Resolved with attendanceGroup=$resolvedAttendance for chat $chatId');
      }
    }

    if (existing == null) {
      debugPrint('⚠️ [FML] Chat $chatId/$chatType not in Hive — using provider updateChatWithMessage');
      _ref!.read(optimizedChatProvider.notifier).updateChatWithMessage(
            chatId: chatId,
            chatType: chatType,
            attendanceGroup: attendanceGroup,
            lastMessage: messageText,
            lastMessageTime: DateTime.now(),
            isIncoming: isIncoming,
          );
      return;
    }

    // Chat found — update unread count and last message directly in Hive
    final newUnread = isIncoming ? existing.unreadCount + 1 : existing.unreadCount;

    final updated = ChatHiveModel(
      id: existing.id,
      type: existing.type,
      name: existing.name,
      profilePicture: existing.profilePicture,
      localImagePath: existing.localImagePath,
      lastMessage: messageText.isNotEmpty ? messageText : existing.lastMessage,
      lastMessageTime: DateTime.now(),
      unreadCount: newUnread,
      isPinned: existing.isPinned,
      attendanceGroup: existing.attendanceGroup,
      actualRole: existing.actualRole,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
      lastReadAt: existing.lastReadAt,
      memberCount: existing.memberCount,
      groupType: existing.groupType,
      role: existing.role,
      mobile: existing.mobile,
      className: existing.className,
      sectionName: existing.sectionName,
      sortTime: DateTime.now(),
    );

    hive.upsertChat(updated).then((_) {
      if (_ref != null) {
        final allChats = hive.getAllChats();
        _ref!.read(optimizedChatProvider.notifier).forceUpdateChats(allChats);
        debugPrint('✅ [FML] Badge updated: $chatId unread=$newUnread attendance=$resolvedAttendance');
      }
    });
  }

  static void _throttledRefresh() {
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < _refreshCooldown) {
      return;
    }
    _lastRefreshTime = now;
    _ref?.read(optimizedChatProvider.notifier).refresh();
  }
}
