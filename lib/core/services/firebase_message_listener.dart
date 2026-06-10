import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_model.dart';
import '../../shared/providers/chat_provider.dart';

class FirebaseMessageListener {
  static WidgetRef? _ref;
  static String? _currentChatId;

  static void init(WidgetRef ref) {
    _ref = ref;
    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleForegroundMessage(message);
    });
    
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleBackgroundMessage(message);
    });
  }

  static void setCurrentChatId(String? chatId) {
    _currentChatId = chatId;
  }

  static void _handleForegroundMessage(RemoteMessage remoteMessage) {
    if (_ref == null) return;

    try {
      final data = remoteMessage.data;
      
      final chatId = data['chat_id']?.toString() ?? data['group_id']?.toString();
      final chatType = data['chat_type'] ?? (data['group_id'] != null ? 'group' : 'user');
      final messageText = data['message'] ?? data['body'] ?? '';
      final senderId = data['sender_id']?.toString() ?? '';
      final senderName = data['sender_name'] ?? '';
      
      if (chatId == null || chatId.isEmpty) return;

      final message = Message(
        id: data['message_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        text: messageText,
        type: data['message_type'] ?? 'text',
        timestamp: DateTime.now(),
        status: {},
      );

      final isChatScreenOpen = _currentChatId == chatId;

      _ref!.read(chatProvider.notifier).onMessageReceived(
        chatId,
        chatType,
        message,
        isChatScreenOpen,
      );

      debugPrint('✅ Updated chat list for incoming message (chat: $chatId, open: $isChatScreenOpen)');
    } catch (e) {
      debugPrint('❌ Error handling foreground message: $e');
    }
  }

  static void _handleBackgroundMessage(RemoteMessage remoteMessage) {
    if (_ref == null) return;

    try {
      final data = remoteMessage.data;
      
      final chatId = data['chat_id']?.toString() ?? data['group_id']?.toString();
      
      if (chatId != null) {
        _ref!.read(chatProvider.notifier).loadChatList();
      }
    } catch (e) {
      debugPrint('❌ Error handling background message: $e');
    }
  }
}
