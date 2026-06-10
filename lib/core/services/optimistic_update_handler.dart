import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../services/api_service_simple.dart';
import '../services/firebase_realtime_service.dart';
import '../services/chat_list_sync_service.dart';
import '../services/offline_queue_service.dart';

/// Handles optimistic UI updates - show immediately, sync in background
class OptimisticUpdateHandler {
  final ApiService _apiService;
  final String currentUserId;

  OptimisticUpdateHandler(this._apiService, this.currentUserId);

  /// Send message with optimistic UI (instant display)
  Future<Message> sendMessageOptimistic({
    required Message message,
    required String chatType,
    required String chatId,
    String? otherUserId,
    Function(Message)? onOptimisticUpdate,
    Function(Message)? onSuccess,
    Function(Message, String)? onError,
  }) async {
    // Step 1: Return message immediately for UI (optimistic)
    final optimisticMessage = message.copyWith(
      status: {'default': 'sending'},
    );
    
    if (onOptimisticUpdate != null) {
      onOptimisticUpdate(optimisticMessage);
    }

    // Step 2: Background sync - Firebase first (fast)
    String? firebaseKey;
    try {
      firebaseKey = await FirebaseRealtimeService.sendMessage(
        message,
        chatType: chatType,
        currentUserId: currentUserId,
        otherUserId: otherUserId ?? '0',
      );
      
      // Update status to sent after Firebase
      final sentMessage = message.copyWith(
        firebaseId: firebaseKey,
        status: {'default': 'sent'},
      );
      
      if (onOptimisticUpdate != null) {
        onOptimisticUpdate(sentMessage);
      }
    } catch (e) {
      debugPrint('Firebase error (non-fatal): $e');
    }

    // Step 3: API sync in background (don't wait)
    _syncToAPI(
      message: message,
      chatType: chatType,
      chatId: chatId,
      firebaseKey: firebaseKey,
      onSuccess: onSuccess,
      onError: onError,
    ).catchError((e) {
      debugPrint('Background API sync failed: $e');
      _queueForRetry(message, chatType, chatId, firebaseKey);
    });

    return optimisticMessage;
  }

  /// Background API sync (non-blocking)
  Future<void> _syncToAPI({
    required Message message,
    required String chatType,
    required String chatId,
    String? firebaseKey,
    Function(Message)? onSuccess,
    Function(Message, String)? onError,
  }) async {
    try {
      Message? apiMessage;
      
      if (chatType == 'group') {
        apiMessage = await _apiService.sendMessage(
          message: message.text,
          groupId: chatId,
          messageType: message.type,
          filePath: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          firebaseKey: firebaseKey,
          replyToMessageId: message.replyToMessage?.msgId,
          old_firebase_message_id: message.replyToMessage?.firebaseId,
        );
      } else {
        apiMessage = await _apiService.sendMessage(
          message: message.text,
          receiverId: chatId,
          messageType: message.type,
          filePath: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          firebaseKey: firebaseKey,
          replyToMessageId: message.replyToMessage?.msgId,
          old_firebase_message_id: message.replyToMessage?.firebaseId,
        );
      }

      if (firebaseKey != null && firebaseKey.isNotEmpty) {
        await FirebaseRealtimeService.updateMessage(
          message,
          chatType: chatType,
          currentUserId: currentUserId,
          otherUserId: chatType != 'group' ? chatId : '0',
          chatIdServer: apiMessage.id.toString(),
          key: firebaseKey,
        );
      }

      // Update chat list via sync service
      final syncService = ChatListSyncService();
      await syncService.updateChatOnMessage(
        chatId: chatId,
        chatType: chatType,
        lastMessage: message.text,
        lastMessageTime: message.timestamp,
        senderId: message.senderId,
        senderName: message.senderName,
        incrementUnread: false,
      );

      if (onSuccess != null) {
        onSuccess(apiMessage);
      }
    } catch (e) {
      if (onError != null) {
        onError(message, e.toString());
      }
      rethrow;
    }
  }

  /// Queue message for retry if API fails
  void _queueForRetry(Message message, String chatType, String chatId, String? firebaseKey) {
    try {
      final pending = PendingMessage(
        tempId: message.id,
        chatId: chatId,
        chatType: chatType,
        message: message.text,
        type: message.type,
        firebaseKey: firebaseKey ?? '',
        clientTimestamp: message.timestamp,
        filePath: message.fileUrl,
        fileName: message.fileName,
        fileSize: message.fileSize,
        replyToMessageId: message.replyToMessage?.msgId,
      );
      
      OfflineQueueService.queueMessage(pending).catchError((e) {
        debugPrint('Failed to queue: $e');
      });
    } catch (e) {
      debugPrint('Queue error: $e');
    }
  }
}
