import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_realtime_service.dart';
import '../models/message_model.dart';
import '../services/chat_list_update_service.dart';

class SendMessageHelper {
  final WidgetRef ref;

  SendMessageHelper(this.ref);

  Future<void> sendMessage({
    required String chatId,
    required String chatType,
    required String messageText,
    required bool attendanceGroup,
    String? currentUserId,
    String? otherUserId,
    String? replyToMessageId,
  }) async {
    try {
      final message = Message(
        id: '',
        chatId: chatId,
        senderId: currentUserId ?? '0',
        senderName: '',
        text: messageText,
        type: 'text',
        timestamp: DateTime.now(),
        status: {'default': 'sending'},
        replyToId: replyToMessageId,
      );

      final firebaseKey = await FirebaseRealtimeService.sendMessage(
        message,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
      );

      await ChatListUpdateService.updateOnMessageSent(
        chatId: chatId,
        chatType: chatType,
        attendanceGroup: attendanceGroup,
        lastMessage: messageText,
        senderId: currentUserId,
      );

      print('✅ Message sent | Firebase key: $firebaseKey | Chat list updated');
    } catch (e) {
      print('❌ Error sending message: $e');
      rethrow;
    }
  }

  Future<void> sendMessageWithFile({
    required String chatId,
    required String chatType,
    required bool attendanceGroup,
    required String messageText,
    required String filePath,
    required String fileType,
    String? currentUserId,
    String? otherUserId,
  }) async {
    try {
      final message = Message(
        id: '',
        chatId: chatId,
        senderId: currentUserId ?? '0',
        senderName: '',
        text: messageText,
        type: fileType,
        timestamp: DateTime.now(),
        status: {'default': 'sending'},
        fileUrl: filePath,
      );

      final firebaseKey = await FirebaseRealtimeService.sendMessage(
        message,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
      );

      final previewText = _getFilePreviewText(fileType, messageText);
      await ChatListUpdateService.updateOnMessageSent(
        chatId: chatId,
        chatType: chatType,
        attendanceGroup: attendanceGroup,
        lastMessage: previewText,
        senderId: currentUserId,
      );

      print('✅ Message with file sent | Key: $firebaseKey');
    } catch (e) {
      print('❌ Error sending message with file: $e');
      rethrow;
    }
  }

  String _getFilePreviewText(String fileType, String messageText) {
    if (messageText.isNotEmpty) return messageText;
    
    switch (fileType) {
      case 'image':
        return '📷 Photo';
      case 'video':
        return '🎥 Video';
      case 'pdf':
        return '📄 PDF';
      case 'doc':
        return '📝 Document';
      default:
        return '📎 File';
    }
  }
}

extension SendMessageExtension on WidgetRef {
  SendMessageHelper get sendMessageHelper => SendMessageHelper(this);
}
