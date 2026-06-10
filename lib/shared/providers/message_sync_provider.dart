import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/models/message_model.dart';
import '../../core/storage/storage_service.dart';

class MessageSyncState {
  final List<Message> messages;
  final bool isSyncing;
  final String? error;
  final DateTime? lastSyncTime;

  MessageSyncState({
    this.messages = const [],
    this.isSyncing = false,
    this.error,
    this.lastSyncTime,
  });

  MessageSyncState copyWith({
    List<Message>? messages,
    bool? isSyncing,
    String? error,
    DateTime? lastSyncTime,
  }) {
    return MessageSyncState(
      messages: messages ?? this.messages,
      isSyncing: isSyncing ?? this.isSyncing,
      error: error,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

class MessageSyncNotifier extends StateNotifier<MessageSyncState> {
  late final SyncService _syncService;
  final StorageService _storage = StorageService();

  MessageSyncNotifier() : super(MessageSyncState()) {
    final dio = Dio();
    final apiService = ApiService(dio);
    _syncService = SyncService(apiService);
  }

  /// Load messages for a chat (instant from cache, then sync)
  Future<void> loadMessages({
    required String chatId,
    required String chatType,
  }) async {
    // INSTANT: Load from cache
    final cached = await _syncService.getCachedMessages('${chatType}_$chatId');
    if (cached.isNotEmpty) {
      state = state.copyWith(messages: cached, isSyncing: false);
    }

    // Background sync
    await syncMessages(chatId: chatId, chatType: chatType);
  }

  /// Sync messages incrementally (background)
  Future<void> syncMessages({
    required String chatId,
    required String chatType,
  }) async {
    try {
      final token = await _storage.getToken();
      if (token == null) return;

      final dio = Dio();
      final apiService = ApiService(dio);
      apiService.setAuthToken(token);

      final messages = await _syncService.syncChatMessages(
        chatId: chatId,
        chatType: chatType,
      );

      state = state.copyWith(
        messages: messages,
        isSyncing: false,
        lastSyncTime: DateTime.now(),
      );
    } catch (e) {
      debugPrint('❌ Message sync error: $e');
      state = state.copyWith(error: e.toString(), isSyncing: false);
    }
  }

  /// Send message offline-first
  Future<void> sendMessage({
    required String chatId,
    required String chatType,
    required String message,
    required String type,
    required String senderId,
    required String senderName,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? replyToMessageId,
  }) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final firebaseKey = 'fb_$tempId';

    // Create temp message
    final tempMessage = Message(
      id: tempId,
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      text: message,
      type: type,
      timestamp: DateTime.now(),
      status: {'default': 'pending'},
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
    );

    // Optimistic UI update
    final updatedMessages = [tempMessage, ...state.messages];
    state = state.copyWith(messages: updatedMessages);

    // Queue for offline
    final pendingMessage = PendingMessage(
      tempId: tempId,
      chatId: chatId,
      chatType: chatType,
      message: message,
      type: type,
      firebaseKey: firebaseKey,
      clientTimestamp: DateTime.now(),
      filePath: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      replyToMessageId: replyToMessageId,
    );

    await OfflineQueueService.queueMessage(pendingMessage);

    // Update message status to 'sending'
    _updateMessageStatus(tempId, 'sending');
  }

  /// Update message status in UI
  void _updateMessageStatus(String messageId, String status) {
    final updated = state.messages.map((msg) {
      if (msg.id == messageId || msg.firebaseId == messageId) {
        return msg.copyWith(status: {'default': status});
      }
      return msg;
    }).toList();

    state = state.copyWith(messages: updated);
  }

  /// Batch mark messages as read
  Future<void> batchMarkAsRead({
    required List<int> messageIds,
    required String chatId,
    required String chatType,
  }) async {
    try {
      await _syncService.batchMarkAsRead(
        messageIds: messageIds,
        chatId: chatId,
        chatType: chatType,
      );
    } catch (e) {
      debugPrint('❌ Batch mark as read failed: $e');
    }
  }
}

final messageSyncProvider =
    StateNotifierProvider.autoDispose<MessageSyncNotifier, MessageSyncState>(
        (ref) {
  return MessageSyncNotifier();
});
