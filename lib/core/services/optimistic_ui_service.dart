import 'package:flutter/material.dart';
import '../models/message_model.dart';

/// Service for implementing optimistic UI updates
/// Shows changes instantly before server confirmation
class OptimisticUIService {
  /// Create temporary message that appears instantly in UI
  static Message createOptimisticMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String text,
    String type = 'text',
    String? fileUrl,
    String? fileName,
    int? fileSize,
    Message? replyToMessage,
  }) {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    
    return Message(
      id: tempId,
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      type: type,
      timestamp: DateTime.now(),
      status: {'default': 'sending'},
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      replyToMessage: replyToMessage,
    );
  }

  /// Update message status after API response
  static Message updateMessageStatus(Message message, String status) {
    return message.copyWith(
      status: {'default': status},
    );
  }

  /// Replace temporary message with server message
  static List<Message> replaceTemporaryMessage(
    List<Message> messages,
    String tempId,
    Message serverMessage,
  ) {
    return messages.map((msg) {
      if (msg.id == tempId) {
        return serverMessage;
      }
      return msg;
    }).toList();
  }

  /// Remove failed message
  static List<Message> removeMessage(List<Message> messages, String messageId) {
    return messages.where((msg) => msg.id != messageId).toList();
  }

  /// Check if message is temporary (not yet confirmed by server)
  static bool isTemporaryMessage(Message message) {
    return message.id.startsWith('temp_');
  }

  /// Get all temporary messages
  static List<Message> getTemporaryMessages(List<Message> messages) {
    return messages.where((msg) => isTemporaryMessage(msg)).toList();
  }

  /// Get message status icon without loading spinner
  static Widget getStatusIcon(String status) {
    switch (status) {
      case 'sending':
      case 'pending':
        return const Icon(Icons.access_time, size: 16, color: Colors.grey);
      case 'sent':
        return const Icon(Icons.check, size: 16, color: Colors.grey);
      case 'delivered':
        return const Icon(Icons.done_all, size: 16, color: Colors.grey);
      case 'read':
        return const Icon(Icons.done_all, size: 16, color: Colors.blue);
      case 'failed':
        return const Icon(Icons.error_outline, size: 16, color: Colors.red);
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Helper class for managing optimistic chat list updates
class OptimisticChatListService {
  /// Add new chat instantly before server confirmation
  static List<dynamic> addOptimisticChat(
    List<dynamic> chats,
    Map<String, dynamic> chatData,
  ) {
    return [chatData, ...chats];
  }

  /// Update chat's last message instantly
  static List<dynamic> updateChatLastMessage(
    List<dynamic> chats,
    String chatId,
    Message message,
  ) {
    return chats.map((chat) {
      if (chat['id'].toString() == chatId) {
        return {
          ...chat,
          'last_message': message.text,
          'updated_at': message.timestamp.toIso8601String(),
        };
      }
      return chat;
    }).toList();
  }

  /// Move chat to top instantly when new message sent/received
  static List<dynamic> moveChatToTop(List<dynamic> chats, String chatId) {
    final chatIndex = chats.indexWhere((c) => c['id'].toString() == chatId);
    if (chatIndex == -1) return chats;
    
    final chat = chats[chatIndex];
    final updatedChats = List.from(chats);
    updatedChats.removeAt(chatIndex);
    updatedChats.insert(0, chat);
    
    return updatedChats;
  }

  /// Update unread count instantly
  static List<dynamic> updateUnreadCount(
    List<dynamic> chats,
    String chatId,
    int delta,
  ) {
    return chats.map((chat) {
      if (chat['id'].toString() == chatId) {
        final currentCount = chat['unread_count'] ?? 0;
        return {
          ...chat,
          'unread_count': (currentCount + delta).clamp(0, 999),
        };
      }
      return chat;
    }).toList();
  }

  /// Mark chat as read instantly
  static List<dynamic> markChatAsRead(List<dynamic> chats, String chatId) {
    return chats.map((chat) {
      if (chat['id'].toString() == chatId) {
        return {
          ...chat,
          'unread_count': 0,
        };
      }
      return chat;
    }).toList();
  }
}

/// Extension methods for optimistic UI updates
extension OptimisticMessageList on List<Message> {
  /// Add message instantly at the start of list
  List<Message> addInstant(Message message) {
    return [message, ...this];
  }

  /// Update message status instantly
  List<Message> updateStatus(String messageId, String status) {
    return map((msg) {
      if (msg.id == messageId) {
        return OptimisticUIService.updateMessageStatus(msg, status);
      }
      return msg;
    }).toList();
  }

  /// Remove temporary message instantly
  List<Message> removeTemporary(String messageId) {
    return where((msg) => msg.id != messageId).toList();
  }

  /// Get count of pending messages
  int get pendingCount {
    return where((msg) => 
      msg.status['default'] == 'sending' || 
      msg.status['default'] == 'pending'
    ).length;
  }

  /// Get count of failed messages
  int get failedCount {
    return where((msg) => msg.status['default'] == 'failed').length;
  }
}
