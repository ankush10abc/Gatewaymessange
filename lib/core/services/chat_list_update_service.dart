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
    required  bool attendanceGroup ,
    String? senderId,
    String? senderName,
  }) async {
    if (_ref == null) {
      debugPrint('⚠️ ChatListUpdateService not initialized');
      return;
    }

    if (_pendingUpdates.contains(chatId)) {
      debugPrint('⏱️ Skipping duplicate update for chat: $chatId');
      return;
    }

    _pendingUpdates.add(chatId);

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
        _pendingUpdates.remove(chatId);
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

    if (_pendingUpdates.contains(chatId)) {
      debugPrint('⏱️ Skipping duplicate update for chat: $chatId');
      return;
    }

    _pendingUpdates.add(chatId);

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
        _pendingUpdates.remove(chatId);
      });
    }
  }

  static void dispose() {
    _ref = null;
    _pendingUpdates.clear();
    _debounceTimer?.cancel();
  }
}
