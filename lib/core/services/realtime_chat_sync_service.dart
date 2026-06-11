import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'chat_list_update_service.dart';

class RealtimeChatSyncService {
  static DatabaseReference? _messagesRef;
  static final Map<String, StreamSubscription<DatabaseEvent>> _listeners = {};

  static Future<void> initialize(List<String> chatIds) async {
    debugPrint('🔄 Initializing RealtimeChatSyncService for ${chatIds.length} chats');
    
    for (final chatId in chatIds) {
      _startListeningToChat(chatId);
    }
  }

  static void _startListeningToChat(String chatId) {
    if (_listeners.containsKey(chatId)) {
      debugPrint('⚠️ Already listening to chat: $chatId');
      return;
    }

    try {
      final ref = FirebaseDatabase.instance.ref('messages/$chatId');
      
      final subscription = ref.limitToLast(1).onChildAdded.listen((event) {
        final data = event.snapshot.value;
        if (data != null && data is Map) {
          final messageData = Map<String, dynamic>.from(data);
          final attendanceGroup = false;
          final messageText = messageData['text']?.toString() ??
                            messageData['message']?.toString() ?? 
                            'New message';
          final timestamp = messageData['timestamp'] as int?;
          final senderId = messageData['senderId']?.toString();
          final senderName = messageData['senderName']?.toString();
          
          if (timestamp != null) {
            ChatListUpdateService.updateOnMessageReceived(
              chatId: chatId,
              chatType: 'group',
              lastMessage: messageText,
              attendanceGroup: attendanceGroup,
              senderId: senderId,
              senderName: senderName,
              incrementUnread: true,
            );
          }
        }
      });

      _listeners[chatId] = subscription;
      debugPrint('👂 Started listening to chat: $chatId');
    } catch (e) {
      debugPrint('❌ Error starting listener for chat $chatId: $e');
    }
  }

  static void stopListeningToChat(String chatId) {
    _listeners[chatId]?.cancel();
    _listeners.remove(chatId);
    debugPrint('🔇 Stopped listening to chat: $chatId');
  }

  static Future<void> dispose() async {
    for (final subscription in _listeners.values) {
      await subscription.cancel();
    }
    _listeners.clear();
    debugPrint('🔇 All RealtimeChatSyncService listeners stopped');
  }
}
