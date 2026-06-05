import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../utils/chat_utils.dart';

class FirebaseRealtimeService {
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseDatabase get database => FirebaseDatabase.instance;

  // Send message to Firebase Realtime Database
  static Future<String> getKey(Message message,
      {String? currentUserId, String? otherUserId, String? chatType}) async {
    final chatId = ChatUtils.generateChatId(message.chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType);
    debugPrint(
        'Sending message to Firebase chat ID: ${message.chatId} currentUserId $currentUserId (original: $otherUserId)');

    final messageRef = database.ref('chats/$chatId/messages').push();
    // final messageData = message.toJson();
    // messageData['timestamp'] =
    //     ServerValue.timestamp; // Use server timestamp for ordering
    // messageData['id'] = messageRef.key!;
    // messageData['chatId'] = message.chatId!;
    // messageData['status'] = {'default': 'sent'};
    // messageData['msgId'] =  chatIdServer;
    // await messageRef.set(messageData);
    //
    // // Update last message in chat
    // await database.ref('chats/$chatId').update({
    //   'lastMessage': messageData,
    //   'updatedAt': ServerValue.timestamp,
    // });

    return messageRef.key!;
  }

  // Update message to Firebase Realtime Database
  static Future<void> updateMessage(Message message,
      {String? currentUserId,
      String? otherUserId,
      String? chatType,
      String? chatIdServer,
      String? key}) async {
    final chatId = ChatUtils.generateChatId(message.chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType);

    debugPrint("Ankush api/message/save - check key $key");
    // Only update if key exists to prevent duplicate updates
    if (key == null || key.isEmpty) return;

    try {
      await database.ref('chats/$chatId/messages/$key').update({
        'msgId': chatIdServer,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Error updating message: $e');
    }
  }

  // Update message to Firebase Realtime Database
  static Future<void> updateMessageNew(Message message,
      {String? currentUserId,
      String? otherUserId,
      String? chatType,
      String? chatIdServer,
      String? key}) async {
    final chatId = ChatUtils.generateChatId(message.chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType);
    debugPrint(
        'Sending message to Firebase chat ID: ${message.chatId} currentUserId $currentUserId (original: $otherUserId)');

    // final messageRef = database.ref('chats/$chatId/messages').push();
    final messageData = message.toJson();
    messageData['timestamp'] =
        ServerValue.timestamp; // Use server timestamp for ordering
    messageData['id'] = key!;
    messageData['chatId'] = message.chatId;
    messageData['status'] = {'default': 'sent'};
    messageData['msgId'] = chatIdServer;
    // await messageRef.set(messageData);

    await database.ref('chats/$chatId/messages/$key').update(messageData);
    // Update last message in chat

    await database.ref('chats/$chatId').update({
      'lastMessage': messageData,
      'updatedAt': ServerValue.timestamp,
    });
  }

  // Send message to Firebase Realtime Database
  static Future<String> sendMessage(Message message,
      {String? currentUserId,
      String? otherUserId,
      String? chatType,
      String? chatIdServer}) async {
    final chatId = ChatUtils.generateChatId(message.chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType);

    final messageRef = database.ref('chats/$chatId/messages').push();
    final messageData = message.toJson();
    messageData['timestamp'] = ServerValue.timestamp;
    messageData['firebaseId'] = messageRef.key!;
    messageData['chatId'] = message.chatId;
    messageData['msgId'] = chatIdServer ?? "0";

    // Initialize status for both sender and receiver
    if (chatType == 'group') {
      // For group, only sender has 'sent' status initially
      if (currentUserId != null) {
        messageData['status'] = {currentUserId: 'sent'};
      } else {
        messageData['status'] = {'default': 'sent'};
      }
    } else {
      // For private chat, initialize both sender and receiver status
      final statusMap = <String, String>{};
      if (currentUserId != null) {
        statusMap[currentUserId] = 'sent';
      }
      if (otherUserId != null && otherUserId != '0') {
        statusMap[otherUserId] = 'sent';
      }
      messageData['status'] =
          statusMap.isNotEmpty ? statusMap : {'default': 'sent'};
    }

    try {
      await messageRef.set(messageData);

      database.ref('chats/$chatId').update({
        'lastMessage': messageData,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint("Error sending message: $e");
    }

    return messageRef.key!;
  }

  // Send message to Firebase Realtime Database
  static Future<void> sendMessageSingle(Message message,
      {String? currentUserId, String? otherUserId, String? chatType}) async {
    final chatId = ChatUtils.generateChatId(message.chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType);
    debugPrint(
        'Sending message to Firebase chat ID: ${message.chatId} currentUserId $currentUserId (original: $otherUserId)');

    final messageRef = database.ref('chats/$chatId/messages').push();
    final messageData = message.toJson();
    messageData['timestamp'] =
        ServerValue.timestamp; // Use server timestamp for ordering
    messageData['id'] = messageRef.key!;
    messageData['status'] = {'default': 'sent'};

    await messageRef.set(messageData);

    // Update last message in chat
    await database.ref('chats/$chatId').update({
      'lastMessage': messageData,
      'updatedAt': ServerValue.timestamp,
    });
  }

  // Real-time message stream from Realtime Database with limit
  static Stream<List<Message>> getMessagesStreamLimited(
      String chatId, String chatType, int limit,
      {String? currentUserId, String? otherUserId}) {
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType);

    return database
        .ref('chats/$firebaseChatId/messages')
        .orderByChild('timestamp')
        .limitToLast(limit)
        .onValue
        .map((event) {
      final data = event.snapshot.value;
      if (data == null) return <Message>[];

      try {
        final Map<String, dynamic> messagesMap =
            Map<String, dynamic>.from(data as Map);
        final messages = <Message>[];
        final seenIds = <String>{};

        messagesMap.forEach((key, value) {
          try {
            final messageData = Map<String, dynamic>.from(value);
            final firebaseId = messageData['firebaseId'] ?? key;

            if (!seenIds.contains(firebaseId)) {
              seenIds.add(firebaseId);
              messageData['id'] = firebaseId;

              if (messageData['timestamp'] is int) {
                messageData['timestamp'] = DateTime.fromMillisecondsSinceEpoch(
                        messageData['timestamp'])
                    .toIso8601String();
              }
              messages.add(Message.fromJson(messageData));
            }
          } catch (e) {
            debugPrint('Error parsing message $key: $e');
          }
        });

        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return messages;
      } catch (e) {
        debugPrint('Error processing messages: $e');
        return <Message>[];
      }
    }).handleError((error) {
      debugPrint('Firebase stream error: $error');
      return <Message>[];
    });
  }

  // Get older messages for pagination
  static Future<List<Message>> getOlderMessages(
    String chatId,
    String chatType,
    DateTime beforeTimestamp,
    int limit, {
    String? currentUserId,
    String? otherUserId,
  }) async {
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType);

    try {
      final snapshot =
          await database.ref('chats/$firebaseChatId/messages').get();

      if (!snapshot.exists) return <Message>[];

      final Map<String, dynamic> messagesMap =
          Map<String, dynamic>.from(snapshot.value as Map);
      final messages = <Message>[];
      final seenIds = <String>{};
      final beforeMillis = beforeTimestamp.millisecondsSinceEpoch;

      messagesMap.forEach((key, value) {
        try {
          final messageData = Map<String, dynamic>.from(value);
          final firebaseId = messageData['firebaseId'] ?? key;
          final timestamp = messageData['timestamp'] as int?;

          if (timestamp != null &&
              timestamp < beforeMillis &&
              !seenIds.contains(firebaseId)) {
            seenIds.add(firebaseId);
            messageData['id'] = firebaseId;
            messageData['timestamp'] =
                DateTime.fromMillisecondsSinceEpoch(timestamp)
                    .toIso8601String();
            messages.add(Message.fromJson(messageData));
          }
        } catch (e) {
          debugPrint('Error parsing message $key: $e');
        }
      });

      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return messages.take(limit).toList();
    } catch (e) {

      debugPrint('Error loading older messages: $e');
      return <Message>[];
    }
  }

  // Real-time message stream from Realtime Database
  static Stream<List<Message>> getMessagesStream(String chatId, String chatType,
      {String? currentUserId, String? otherUserId}) {
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType);

    return database.ref('chats/$firebaseChatId/messages').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return <Message>[];

      try {
        final Map<String, dynamic> messagesMap =
            Map<String, dynamic>.from(data as Map);
        final messages = <Message>[];
        final seenIds = <String>{};

        messagesMap.forEach((key, value) {
          try {
            final messageData = Map<String, dynamic>.from(value);
            final firebaseId = messageData['firebaseId'] ?? key;

            if (!seenIds.contains(firebaseId)) {
              seenIds.add(firebaseId);
              messageData['id'] = firebaseId;

              if (messageData['timestamp'] is int) {
                messageData['timestamp'] = DateTime.fromMillisecondsSinceEpoch(
                        messageData['timestamp'])
                    .toIso8601String();
              }
              // debugPrint('Received message: ${messageData.toString()}');
              messages.add(Message.fromJson(messageData));
            }
          } catch (e) {
            debugPrint('Error parsing message $key: $e');
          }
        });

        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return messages;
      } catch (e) {
        debugPrint('Error processing messages: $e');
        return <Message>[];
      }
    }).handleError((error) {
      debugPrint('Firebase stream error: $error');
      return <Message>[];
    });
  }

  // Real-time message stream from Realtime Database
  static Stream<List<Message>> getMessagesStreamSingle(
      String chatId, String chatType,
      {String? currentUserId, String? otherUserId}) {
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType);

    return database.ref('chats/$firebaseChatId/messages').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return <Message>[];

      final Map<String, dynamic> messagesMap =
          Map<String, dynamic>.from(data as Map);
      final messages = <Message>[];

      messagesMap.forEach((key, value) {
        final messageData = Map<String, dynamic>.from(value);
        messageData['id'] = key;

        // Handle timestamp conversion
        if (messageData['timestamp'] is int) {
          messageData['timestamp'] =
              DateTime.fromMillisecondsSinceEpoch(messageData['timestamp'])
                  .toIso8601String();
        }

        messages.add(Message.fromJson(messageData));
      });

      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      debugPrint("Ankush Banawade Messahes debugError Eleven $messages");
      return messages;
    });
  }

  // Update message status (sent/delivered/read)
  static Future<void> updateMessageStatus(
    String chatType,
    String chatId,
    String messageId,
    String userId,
    String status, {
    String? currentUserId,
    String? otherUserId,
    List<dynamic>? groupMembers,
  }) async {
    try {
      final firebaseChatId = ChatUtils.generateChatId(chatId,
          chatType: chatType,
          currentUserId: currentUserId,
          otherUserId: otherUserId);

      await database
          .ref('chats/$firebaseChatId/messages/$messageId/status/$userId')
          .set(status);

      // For group chats, check if all members have read the message
      if (chatType == 'group' && status == 'read' && groupMembers != null) {
        final messageRef =
            database.ref('chats/$firebaseChatId/messages/$messageId');
        final snapshot = await messageRef.get();

        if (snapshot.exists) {
          final messageData = Map<String, dynamic>.from(snapshot.value as Map);
          final senderId = messageData['senderId']?.toString();
          final statusMap = messageData['status'] as Map?;

          if (statusMap != null && senderId != null) {
            bool allRead = true;
            for (final member in groupMembers) {
              final memberId = member['id']?.toString() ?? member.toString();
              if (memberId != senderId) {
                final memberStatus = statusMap[memberId]?.toString() ?? 'sent';
                if (memberStatus != 'read') {
                  allRead = false;
                  break;
                }
              }
            }

            if (allRead) {
              await database
                  .ref('chats/$firebaseChatId/messages/$messageId/allRead')
                  .set(true);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error updating message status: $e');
    }
  }

  // Mark messages as read
  static Future<void> markMessagesAsRead(
      String chatType, String chatId, String userId,
      {String? currentUserId,
      String? otherUserId,
      List<dynamic>? groupMembers}) async {
    try {

      final firebaseChatId = ChatUtils.generateChatId(chatId,
          chatType: chatType,
          currentUserId: currentUserId,
          otherUserId: otherUserId);

      final messagesSnapshot =
          await database.ref('chats/$firebaseChatId/messages').get();


      if (messagesSnapshot.exists) {
        debugPrint("Data Error marking messages as read take ${messagesSnapshot.value}");
        final messages = messagesSnapshot.value as Map<dynamic, dynamic>;
        // final messages = messagesSnapshot.value as List<dynamic>;
      debugPrint("Data Error marking messages as read ${messages.entries}");
        for (final entry in messages.entries) {
          final messageData = entry.value as Map<dynamic, dynamic>;
          final senderId = messageData['senderId']?.toString();

          if (senderId != userId) {
            // Get current status to avoid unnecessary updates
            final currentStatus = messageData['status']?[userId]?.toString();
            if (currentStatus != 'read') {
              debugPrint("Data Error marking messages as read ${firebaseChatId} key ${entry.key}");
              await database
                  .ref(
                      'chats/$firebaseChatId/messages/${entry.key}/status/$userId')
                  .set('read');
            }

            // For group chats, check if all members have read
            if (chatType == 'group' && groupMembers != null) {
              final statusSnapshot = await database
                  .ref('chats/$firebaseChatId/messages/${entry.key}/status')
                  .get();

              if (statusSnapshot.exists) {
                debugPrint("Data Error catch ${Map<String, dynamic>.from(statusSnapshot.value as Map)} key ");
                final statusMap =
                    Map<String, dynamic>.from(statusSnapshot.value as Map);
                bool allRead = true;

                try {
                  for (final member in groupMembers) {

                                    final memberId =
                                        member['id']?.toString() ?? member.toString();
                                    if (memberId != senderId) {
                                      final memberStatus =
                                          statusMap[memberId]?.toString() ?? 'sent';
                                      if (memberStatus != 'read') {
                                        allRead = false;
                                        break;
                                      }
                                    }
                                  }
                } catch (e) {
                  debugPrint("Data Error catch ${e} key ${e.toString()}");
                  print(e);
                }

                if (allRead) {
                  debugPrint("Data Error marking messages as read All  ${firebaseChatId} key ${entry.key}");
                  await database
                      .ref(
                          'chats/$firebaseChatId/messages/${entry.key}/allRead')
                      .set(true);
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  // Online presence management
  static Future<void> setUserOnline(String userId) async {
    await database.ref('presence/$userId').set({
      'isOnline': true,
      'lastSeen': ServerValue.timestamp,
    });

    // Set offline when disconnected
    await database.ref('presence/$userId').onDisconnect().set({
      'isOnline': false,
      'lastSeen': ServerValue.timestamp,
    });
  }

  static Future<void> setUserOffline(String userId) async {
    await database.ref('presence/$userId').set({
      'isOnline': false,
      'lastSeen': ServerValue.timestamp,
    });
  }

  static Stream<Map<String, dynamic>?> getUserPresence(String userId) {
    return database
        .ref('presence/$userId')
        .onValue
        .map((event) => event.snapshot.value as Map<String, dynamic>?);
  }

  // Typing indicator
  static Future<void> setTyping(
      String chatType, String chatId, String userId, bool isTyping,
      {String? currentUserId, String? otherUserId}) async {
    debugPrint("setTyping $chatId $userId $isTyping");
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        chatType: chatType,
        currentUserId: currentUserId,
        otherUserId: otherUserId);
    debugPrint("setTyping $firebaseChatId $userId $isTyping");
    if (isTyping) {
      await database.ref('typing/$firebaseChatId/$userId').set({
        'isTyping': true,
        'timestamp': ServerValue.timestamp,
      });

      // Auto-remove typing after 3 seconds
      Timer(const Duration(seconds: 3), () {
        database.ref('typing/$firebaseChatId/$userId').remove();
      });
    } else {
      await database.ref('typing/$firebaseChatId/$userId').remove();
    }
  }

  static Stream<Map<String, dynamic>> getTypingUsers(
      String chatId, String chatType,
      {String? currentUserId, String? otherUserId}) {
    debugPrint(' getTypingUsers Listening to Firebase chat ID: $otherUserId');
    var firebaseChatId = ChatUtils.generateChatId(
        chatType != 'group' ? otherUserId! : chatId,
        chatType: chatType,
        currentUserId: currentUserId,
        otherUserId: otherUserId);
    debugPrint(
        ' getTypingUsers Listening to Firebase chat ID: $firebaseChatId');
    // firebaseChatId = 'private_4';
    return database.ref('typing/$firebaseChatId').onValue.map((event) {
      final value = event.snapshot.value;

      if (value == null) return <String, dynamic>{};

      try {
        final Map<dynamic, dynamic> rawMap = value as Map<dynamic, dynamic>;
        final Map<String, dynamic> result = {};

        rawMap.forEach((key, val) {
          result[key.toString()] = val;
        });

        return result;
      } catch (e) {
        debugPrint('Error converting typing data: $e');
        return <String, dynamic>{};
      }
    });
  }

  // Group management
  static Future<void> addUserToGroup(String chatId, String userId) async {
    await firestore.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayUnion([userId]),
    });
  }

  static Future<void> removeUserFromGroup(String chatId, String userId) async {
    await firestore.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayRemove([userId]),
    });
  }

  // Create chat in Firebase
  static Future<void> createChat(Chat chat) async {
    await firestore.collection('chats').doc(chat.id).set(chat.toFirestore());
  }

  // Get chat stream
  static Stream<Chat?> getChatStream(String chatId) {
    return firestore
        .collection('chats')
        .doc(chatId)
        .snapshots(includeMetadataChanges: false)
        .handleError((error) {
      debugPrint('Chat stream error: $error');
      return <DocumentSnapshot>[];
    }).map((doc) =>
            doc.exists ? Chat.fromFirestore(doc.data()!, doc.id) : null);
  }

  // Forward message
  static Future<void> forwardMessage(
      Message originalMessage, List<String> chatIds) async {
    final batch = firestore.batch();

    for (final chatId in chatIds) {
      final forwardedMessage = originalMessage.copyWith(
        id: '',
        chatId: chatId,
        timestamp: DateTime.now(),
        isForwarded: true,
        status: {'default': 'sent'},
      );

      final messageRef = firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc();

      batch.set(messageRef, forwardedMessage.toFirestore());

      // Create or update chat document
      final chatRef = firestore.collection('chats').doc(chatId);
      batch.set(
          chatRef,
          {
            'lastMessage': forwardedMessage.toFirestore(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }

    await batch.commit();
  }
}
