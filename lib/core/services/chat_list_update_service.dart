import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/optimized_chat_provider.dart';
import '../services/chat_list_sync_service.dart';

class ChatListUpdateService {
  static WidgetRef? _ref;
  static final Set<String> _pendingUpdates = {};
  static Timer? _debounceTimer;
  static final ChatListSyncService _syncService = ChatListSyncService();

  static void initialize(WidgetRef ref, {String? userId}) {
    _ref = ref;
    if (userId != null) {
      _syncService.initialize(userId);
    }
    debugPrint('✅ ChatListUpdateService initialized');
  }

  static Future<void> updateOnMessageSent({
    required String chatId,
    required String chatType,
    required String lastMessage,
    required bool attendanceGroup,
    String? senderId,
    String? senderName,
  }) async {
    if (_ref == null) {
      debugPrint('⚠️ ChatListUpdateService not initialized');
      return;
    }

    // Include attendanceGroup + operation type so attendance updates never
    // collide with regular sent-message dedup keys for the same chatId.
    final dedupKey = 'sent_${chatType}_${chatId}_$attendanceGroup';
    if (_pendingUpdates.contains(dedupKey)) {
      debugPrint('⏱️ Skipping duplicate update for chat: $dedupKey');
      return;
    }

    _pendingUpdates.add(dedupKey);

    try {
      await _ref!.read(optimizedChatProvider.notifier).updateChatWithMessage(
        chatId: chatId,
        chatType: chatType,
        lastMessage: lastMessage,
        attendanceGroup: attendanceGroup,
        lastMessageTime: DateTime.now(),
        senderId: senderId,
        senderName: senderName,
        isIncoming: false,
      );
      debugPrint('📤 Chat list updated for outgoing message in chat: $chatId');
    } catch (e) {
      debugPrint('❌ Error updating chat list: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _pendingUpdates.remove(dedupKey);
      });
    }
  }

  static Future<void> updateOnMessageReceived({
    required String chatId,
    required String chatType,
    required String lastMessage,
    required bool attendanceGroup,
    String? senderId,
    String? senderName,
    bool incrementUnread = true,
  }) async {
    if (_ref == null) {
      debugPrint('⚠️ ChatListUpdateService not initialized');
      return;
    }

    // Include attendanceGroup + operation type to avoid cross-contamination
    final dedupKey = 'recv_${chatType}_${chatId}_$attendanceGroup';
    if (_pendingUpdates.contains(dedupKey)) {
      debugPrint('⏱️ Skipping duplicate update for chat: $dedupKey');
      return;
    }

    _pendingUpdates.add(dedupKey);

    try {
      await _ref!.read(optimizedChatProvider.notifier).updateChatWithMessage(
        chatId: chatId,
        chatType: chatType,
        lastMessage: lastMessage,
        attendanceGroup: attendanceGroup,
        lastMessageTime: DateTime.now(),
        senderId: senderId,
        senderName: senderName,
        isIncoming: incrementUnread,
      );
      debugPrint('📥 Chat list updated for incoming message in chat: $chatId');
    } catch (e) {
      debugPrint('❌ Error updating chat list: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _pendingUpdates.remove(dedupKey);
      });
    }
  }

  static void dispose() {
    _ref = null;
    _pendingUpdates.clear();
    _debounceTimer?.cancel();
  }
}
