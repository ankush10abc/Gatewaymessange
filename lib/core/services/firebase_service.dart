import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';
import '../models/user_model.dart';

class FirebaseService {
  static final DatabaseReference _database = FirebaseDatabase.instance.ref();
  static final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;

  // User presence management
  static Future<void> setUserOnline(String userId) async {
    try {
      await _database.child('users/$userId').update({
            'isOnline': true,
            'lastSeen': ServerValue.timestamp,
          });

      // Set offline when disconnected
      _database.child('users/$userId').onDisconnect().update({
            'isOnline': false,
            'lastSeen': ServerValue.timestamp,
          });
    } catch (e) {
      print("ERROR VALUE ONE$e");
    }
  }

  static Future<void> setUserOffline(String userId) async {
    await _database.child('users/$userId').update({
      'isOnline': false,
      'lastSeen': ServerValue.timestamp,
    });
  }

  // Typing indicators
  static Future<void> setTyping(String chatId, String userId, bool isTyping) async {
    debugPrint("setTyping $chatId $userId $isTyping");
    if (isTyping) {
      await _database.child('users/$userId/typing/$chatId').set(true);
    } else {
      await _database.child('users/$userId/typing/$chatId').remove();
    }
  }

  static Stream<bool> getTypingStatus(String chatId, String userId) {
    return _database
        .child('users/$userId/typing/$chatId')
        .onValue
        .map((event) => event.snapshot.value as bool? ?? false);
  }

  // Message management
  static Future<void> sendMessage(Message message) async {
    final messageRef = _database.child('chats/${message.chatId}/messages').push();
    final messageWithId = message.copyWith(id: messageRef.key!);
    
    await messageRef.set(messageWithId.toJson());
    
    // Update last message in chat
    await _database.child('chats/${message.chatId}').update({
      'lastMessage': messageWithId.toJson(),
      'updatedAt': ServerValue.timestamp,
    });
  }

  static Stream<List<Message>> getMessages(String chatId) {
    return _database
        .child('chats/$chatId/messages')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <Message>[];
      
      return data.entries
          .map((entry) => Message.fromJson(Map<String, dynamic>.from(entry.value)))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
  }

  static Future<void> updateMessageStatus(
    String chatId,
    String messageId,
    String userId,
    String status,
  ) async {
    await _database
        .child('chats/$chatId/messages/$messageId/status/$userId')
        .set(status);
  }

  // Chat management
  static Future<String> createChat(Chat chat) async {
    final chatRef = _database.child('chats').push();
    final chatWithId = chat.copyWith(id: chatRef.key!);
    
    await chatRef.set(chatWithId.toJson());
    return chatRef.key!;
  }

  static Stream<List<Chat>> getUserChats(String userId) {
    return _database
        .child('chats')
        .orderByChild('updatedAt')
        .onValue
        .map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <Chat>[];
      
      return data.entries
          .map((entry) => Chat.fromJson(Map<String, dynamic>.from(entry.value)))
          .where((chat) => chat.participants.contains(userId))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    });
  }

  static Future<void> pinChat(String chatId, bool isPinned) async {
    await _database.child('chats/$chatId').update({'isPinned': isPinned});
  }

  // User management
  static Future<void> updateUserProfile(User user) async {
    await _database.child('users/${user.id}').set(user.toJson());
  }

  static Stream<User?> getUser(String userId) {
    return _database.child('users/$userId').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return null;
      return User.fromJson(Map<String, dynamic>.from(data));
    });
  }

  static Stream<List<User>> searchUsers(String query, String currentUserId) {
    return _database.child('users').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <User>[];
      
      return data.entries
          .map((entry) => User.fromJson(Map<String, dynamic>.from(entry.value)))
          .where((user) => 
              user.id != currentUserId &&
              user.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  static void listenToNewMessages(Function(dynamic) callback) {
    // Implementation for listening to new messages
  }

  static void listenToUserStatusChanges(Function(int, bool) callback) {
    // Implementation for listening to user status changes
  }
}