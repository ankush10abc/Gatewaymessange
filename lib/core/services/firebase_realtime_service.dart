import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../utils/chat_utils.dart';
import 'chat_list_update_service.dart';
// statusKey() is defined in message_model.dart — imported above

class FirebaseRealtimeService {
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseDatabase get database => FirebaseDatabase.instance;
  static String TAG = "FirebaseRealtimeService";
  static Map<dynamic, dynamic>? _snapshotMap(dynamic value) {
    if (value is! Map) return null;
    return Map<dynamic, dynamic>.from(value);
  }

  // Send message to Firebase Realtime Database
  static Future<String> getKey(Message message,
      {String? currentUserId,
      String? otherUserId,
      String? chatType,
      bool? attendanceGroup}) async {
    final chatId = ChatUtils.generateChatId(message.chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
        attendanceGroup: attendanceGroup);
    // debugPrint(
    //     '$TAG Sending message to Firebase chat ID: ${message.chatId} currentUserId $currentUserId (original: $otherUserId)');

    final messageRef = database.ref('chats/$chatId/messages').push();

    return messageRef.key!;
  }

  // Update message to Firebase Realtime Database
  static Future<void> updateMessage(Message message,
      {String? currentUserId,
      String? otherUserId,
      String? chatType,
      String? chatIdServer,
      String? key,
      bool? attendanceGroup}) async {
    final chatId = ChatUtils.generateChatId(message.chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
        attendanceGroup: attendanceGroup);

    // debugPrint("$TAG Ankush api/message/save - check key $key");
    // Only update if key exists to prevent duplicate updates
    if (key == null || key.isEmpty) return;

    try {
      await database.ref('chats/$chatId/messages/$key').update({
        'msgId': chatIdServer,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('$TAG Error updating message: $e');
    }
  }

  // Update message to Firebase Realtime Database
  static Future<void> updateMessageNew(Message message,
      {String? currentUserId,
      String? otherUserId,
      String? chatType,
      String? chatIdServer,
      String? key,
      bool? attendanceGroup}) async {
    final chatId = ChatUtils.generateChatId(message.chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
        attendanceGroup: attendanceGroup);

    final messageData = message.toJson();
    messageData['timestamp'] = ServerValue.timestamp;
    messageData['id'] = key!;
    messageData['chatId'] = message.chatId;
    messageData['msgId'] = chatIdServer;

    // Preserve per-user status map — never overwrite with {'default': 'sent'}
    // which would break double-tick tracking for private chats.
    // Only set status if not already a per-user map.
    final existingStatus = message.status;
    final hasPerUserStatus = existingStatus.isNotEmpty &&
        !existingStatus.containsKey('default');
    if (!hasPerUserStatus) {
      // Build per-user status map with prefixed keys to prevent Firebase array conversion
      final statusMap = <String, String>{};
      if (currentUserId != null && currentUserId.isNotEmpty) {
        statusMap[statusKey(currentUserId)] = 'sent';
      }
      if (chatType != 'group' &&
          otherUserId != null &&
          otherUserId.isNotEmpty &&
          otherUserId != '0') {
        statusMap[statusKey(otherUserId)] = 'sent';
      }
      messageData['status'] =
          statusMap.isNotEmpty ? statusMap : {'default': 'sent'};
    } else {
      messageData['status'] = existingStatus;
    }

    await database.ref('chats/$chatId/messages/$key').update(messageData);

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
      bool? attendanceGroup,
      String? chatIdServer}) async {
    final chatId = ChatUtils.generateChatId(message.chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
        attendanceGroup: attendanceGroup);

    final messageRef = database.ref('chats/$chatId/messages').push();
    final messageData = message.toJson();
    messageData['timestamp'] = ServerValue.timestamp;
    messageData['firebaseId'] = messageRef.key!;
    messageData['chatId'] = message.chatId;
    messageData['msgId'] = chatIdServer ?? "0";

    // Initialize status for both sender and receiver.
    // Use statusKey() prefix so Firebase never converts the map to an array
    // (Firebase converts maps with small consecutive integer keys like {1:x,3:x}
    // to arrays — prefixing with 'u' prevents this entirely).
    if (chatType == 'group') {
      if (currentUserId != null) {
        messageData['status'] = {statusKey(currentUserId): 'sent'};
      } else {
        messageData['status'] = {'default': 'sent'};
      }
    } else {
      final resolvedOtherUserId =
          (otherUserId != null && otherUserId.isNotEmpty && otherUserId != '0')
              ? otherUserId
              : message.chatId;
      final statusMap = <String, String>{};
      if (currentUserId != null && currentUserId.isNotEmpty) {
        statusMap[statusKey(currentUserId)] = 'sent';
      }
      if (resolvedOtherUserId.isNotEmpty &&
          resolvedOtherUserId != currentUserId) {
        statusMap[statusKey(resolvedOtherUserId)] = 'sent';
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

      // Trigger chat list update for sender
      ChatListUpdateService.updateOnMessageSent(
        chatId: message.chatId,
        chatType: chatType ?? 'group',
        attendanceGroup: attendanceGroup ?? false,
        lastMessage: message.text,
      );
    } catch (e) {
      debugPrint("$TAG Error sending message: $e");
    }

    return messageRef.key!;
  }

  // Send message to Firebase Realtime Database
  static Future<void> sendMessageSingle(Message message,
      {String? currentUserId,
      String? otherUserId,
      String? chatType,
      bool? attendanceGroup}) async {
    final chatId = ChatUtils.generateChatId(message.chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
        attendanceGroup: attendanceGroup);
    // debugPrint(
    //     '$TAG Sending message to Firebase chat ID: ${message.chatId} currentUserId $currentUserId (original: $otherUserId)');

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
      {String? currentUserId, String? otherUserId, bool? attendanceGroup}) {
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
        attendanceGroup: attendanceGroup);

    // debugPrint("$TAG  ✅ Loaded 6 cached messages for $firebaseChatId");
    return database
        .ref('chats/$firebaseChatId/messages')
        .orderByChild('timestamp')
        .limitToLast(limit)
        .onValue
        .map((event) {
      final data = event.snapshot.value;
      if (data == null) return <Message>[];

      try {
        debugPrint(
            "$TAG ✅ Fiver 6 cached messages for messageData coming data $data");
        final messagesMap = _snapshotMap(data);
        if (messagesMap == null || messagesMap.isEmpty) {
          return <Message>[];
        }

        final messages = <Message>[];
        final seenIds = <String>{};

        messagesMap.forEach((key, value) {
          try {
            final messageData = _snapshotMap(value);
            if (messageData == null) return;
            final firebaseId = messageData['firebaseId'] ?? key;

            if (!seenIds.contains(firebaseId)) {
              seenIds.add(firebaseId);
              messageData['id'] = firebaseId;

              if (messageData['timestamp'] is int) {
                messageData['timestamp'] = DateTime.fromMillisecondsSinceEpoch(
                        messageData['timestamp'])
                    .toIso8601String();
              }
              debugPrint(
                  "$TAG ✅ Fiver 6 cached messages for messageData $messageData");
              messages.add(Message.fromJson(messageData));
            }
          } catch (e) {
            debugPrint('$TAG Error parsing message $key: $e');
          }
        });

        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return messages;
      } catch (e) {
        debugPrint('$TAG Error processing messages: $e');
        return <Message>[];
      }
    }).handleError((error) {
      debugPrint('$TAG Firebase stream error: $error');
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
    bool? attendanceGroup,
  }) async {
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
        attendanceGroup: attendanceGroup);

    try {
      final snapshot =
          await database.ref('chats/$firebaseChatId/messages').get();

      if (!snapshot.exists) return <Message>[];

      final messagesMap = _snapshotMap(snapshot.value);
      if (messagesMap == null || messagesMap.isEmpty) return <Message>[];

      final messages = <Message>[];
      final seenIds = <String>{};
      final beforeMillis = beforeTimestamp.millisecondsSinceEpoch;

      messagesMap.forEach((key, value) {
        try {
          final messageData = _snapshotMap(value);
          if (messageData == null) return;
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
          debugPrint('$TAG Error parsing message $key: $e');
        }
      });

      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return messages.take(limit).toList();
    } catch (e) {
      debugPrint('$TAG Error loading older messages: $e');
      return <Message>[];
    }
  }

  // Real-time message stream from Realtime Database
  static Stream<List<Message>> getMessagesStream(String chatId, String chatType,
      {String? currentUserId, String? otherUserId, bool? attendanceGroup}) {
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
        attendanceGroup: attendanceGroup);

    return database.ref('chats/$firebaseChatId/messages').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return <Message>[];

      try {
        final messagesMap = _snapshotMap(data);
        if (messagesMap == null || messagesMap.isEmpty) {
          return <Message>[];
        }

        final messages = <Message>[];
        final seenIds = <String>{};

        messagesMap.forEach((key, value) {
          try {
            final messageData = _snapshotMap(value);
            if (messageData == null) return;
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
            debugPrint('$TAG Error parsing message $key: $e');
          }
        });

        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return messages;
      } catch (e) {
        debugPrint('$TAG Error processing messages: $e');
        return <Message>[];
      }
    }).handleError((error) {
      debugPrint('$TAG Firebase stream error: $error');
      return <Message>[];
    });
  }

  // Real-time message stream from Realtime Database
  static Stream<List<Message>> getMessagesStreamSingle(
      String chatId, String chatType,
      {String? currentUserId, String? otherUserId, bool? attendanceGroup}) {
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
        attendanceGroup: attendanceGroup);

    return database.ref('chats/$firebaseChatId/messages').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return <Message>[];

      final messagesMap = _snapshotMap(data);
      if (messagesMap == null || messagesMap.isEmpty) return <Message>[];

      final messages = <Message>[];

      messagesMap.forEach((key, value) {
        try {
          final messageData = _snapshotMap(value);
          if (messageData == null) return;
          messageData['id'] = key;

          // Handle timestamp conversion
          if (messageData['timestamp'] is int) {
            messageData['timestamp'] =
                DateTime.fromMillisecondsSinceEpoch(messageData['timestamp'])
                    .toIso8601String();
          }

          messages.add(Message.fromJson(messageData));
        } catch (e) {
          debugPrint('$TAG Error parsing message $key: $e');
        }
      });

      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      debugPrint("$TAG Ankush Banawade Messahes debugError Eleven $messages");
      return messages;
    }).handleError((error) {
      debugPrint('$TAG Firebase stream error: $error');
      return <Message>[];
    });
  }

  /// Resolves the actual Firebase node key for a message under [firebaseChatId].
  ///
  /// Strategy:
  /// 1. Direct lookup by [messageId] as node key (works for both push keys and numeric IDs).
  /// 2. Scan all nodes matching by firebaseId field stored inside the node.
  /// 3. Scan all nodes matching by msgId / msg_id field.
  ///
  /// Returns the resolved node key, or null if not found.
  static Future<String?> _resolveFirebaseNodeKey(
    String firebaseChatId,
    String messageId,
  ) async {
    if (messageId.isEmpty || messageId.startsWith('temp_')) return null;

    // Step 1: direct lookup — fastest path, works for push keys and numeric IDs
    try {
      final directSnap = await database
          .ref('chats/$firebaseChatId/messages/$messageId')
          .get();
      if (directSnap.exists) return messageId;
    } catch (_) {}

    // Step 2 & 3: scan all nodes for matching firebaseId or msgId field
    try {
      final allSnap =
          await database.ref('chats/$firebaseChatId/messages').get();
      if (!allSnap.exists || allSnap.value is! Map) return null;
      final map = allSnap.value as Map;
      for (final entry in map.entries) {
        final val = entry.value;
        if (val is! Map) continue;
        // Match by firebaseId field stored inside the node
        final storedFirebaseId = val['firebaseId']?.toString();
        if (storedFirebaseId != null && storedFirebaseId == messageId) {
          return entry.key.toString();
        }
        // Match by msgId / msg_id field
        final storedMsgId =
            val['msgId']?.toString() ?? val['msg_id']?.toString();
        if (storedMsgId != null &&
            storedMsgId.isNotEmpty &&
            storedMsgId != '0' &&
            storedMsgId == messageId) {
          return entry.key.toString();
        }
      }
    } catch (_) {}

    return null;
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
    bool? attendanceGroup,
  }) async {
    try {
      final firebaseChatId = ChatUtils.generateChatId(chatId,
          chatType: chatType,
          currentUserId: currentUserId,
          otherUserId: otherUserId,
          attendanceGroup: attendanceGroup);
      // Resolve the correct Firebase node key (handles both push keys and numeric server IDs)
      final nodeKey = await _resolveFirebaseNodeKey(firebaseChatId, messageId);
      if (nodeKey == null) {
        debugPrint('$TAG ⚠️ updateMessageStatus: node not found for messageId=$messageId in $firebaseChatId');
        return;
      }

      debugPrint('$TAG updateMessageStatus: $messageId → nodeKey=$nodeKey status=$status');
      // Use prefixed key so the status node stays a Map in Firebase
      await database
          .ref('chats/$firebaseChatId/messages/$nodeKey/status/${statusKey(userId)}')
          .set(status);

      // For group chats, check if all members have read the message
      if (chatType == 'group' && status == 'read' && groupMembers != null) {
        final messageRef =
            database.ref('chats/$firebaseChatId/messages/$nodeKey');
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
                final statusStrMap = Map<String, dynamic>.from(statusMap);
                // Check both prefixed and raw key for backward compatibility
                final memberStatus = (statusStrMap[statusKey(memberId)] ??
                    statusStrMap[memberId])?.toString() ?? 'sent';
                if (memberStatus != 'read') {
                  allRead = false;
                  break;
                }
              }
            }

            if (allRead) {
              await database
                  .ref('chats/$firebaseChatId/messages/$nodeKey/allRead')
                  .set(true);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('$TAG Error updating message status: $e');
    }
  }

  // Mark messages as read
  static Future<void> markMessagesAsRead(
      String chatType, String chatId, String userId,
      {String? currentUserId,
      String? otherUserId,
      List<dynamic>? groupMembers,
      bool? attendanceGroup}) async {
    try {
      final firebaseChatId = ChatUtils.generateChatId(chatId,
          chatType: chatType,
          currentUserId: currentUserId,
          otherUserId: otherUserId,
          attendanceGroup: attendanceGroup);

      final messagesSnapshot =
          await database.ref('chats/$firebaseChatId/messages').get();

      if (messagesSnapshot.exists) {
        debugPrint(
            "$TAG Data Error marking messages as read take ${messagesSnapshot.value}");
        final messages = messagesSnapshot.value is Map
            ? messagesSnapshot.value as Map<dynamic, dynamic>
            : null;
        if (messages == null || messages.isEmpty) return;
        // final messages = messagesSnapshot.value as List<dynamic>;
        debugPrint("$TAG Data Error marking messages as read ${messages.entries}");
        for (final entry in messages.entries) {
          if (entry.value is! Map) continue;
          final messageData = Map<String, dynamic>.from(entry.value as Map);
          final senderId = messageData['senderId']?.toString();

          if (senderId != userId) {
            // Cast status to Map<String,dynamic> so String key lookup works correctly.
            // Firebase returns Map<dynamic,dynamic> — direct String key lookup returns null.
            final rawStatus = messageData['status'];
            final statusStrMap = rawStatus is Map
                ? Map<String, dynamic>.from(rawStatus)
                : null;
            // Check both prefixed and raw key for backward compatibility
            final currentStatus = (statusStrMap?[statusKey(userId)] ??
                statusStrMap?[userId])?.toString();
            if (currentStatus != 'read') {
              await database
                  .ref('chats/$firebaseChatId/messages/${entry.key}/status/${statusKey(userId)}')
                  .set('read');
              if (messageData['msgId'] != null) {
                await database
                    .ref('chats/$firebaseChatId/messages/${messageData['msgId']}/status/${statusKey(userId)}')
                    .set('read');
              }
            }

            // For group chats, check if all members have read
            if (chatType == 'group' && groupMembers != null) {
              final statusSnapshot = await database
                  .ref('chats/$firebaseChatId/messages/${entry.key}/status')
                  .get();

              if (statusSnapshot.exists) {
                final statusMap = _snapshotMap(statusSnapshot.value);
                if (statusMap == null || statusMap.isEmpty) continue;
                // debugPrint("$TAG Data Error catch $statusMap key ");
                bool allRead = true;

                try {
                  for (final member in groupMembers) {
                    final memberId =
                        member['id']?.toString() ?? member.toString();
                    if (memberId != senderId) {
                      // Check both prefixed and raw key for backward compatibility
                      final memberStatus = (statusMap[statusKey(memberId)] ??
                          statusMap[memberId])?.toString() ?? 'sent';
                      if (memberStatus != 'read') {
                        allRead = false;
                        break;
                      }
                    }
                  }
                } catch (e) {
                  debugPrint("$TAG Data Error catch ${e} key ${e.toString()}");
                  print(e);
                }

                if (allRead) {
                  // debugPrint(
                  //     "$TAG Data Error marking messages as read All  ${firebaseChatId} key ${entry.key}");
                  await database
                      .ref(
                          'chats/$firebaseChatId/messages/${entry.key}/allRead')
                      .set(true);
                  // await database
                  //     .ref(
                  //     'chats/$firebaseChatId/messages/${messageData['msgId']}/allRead')
                  //     .set(true);

                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('$TAG Error marking messages as read: $e');
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
      {String? currentUserId,
      String? otherUserId,
      bool? attendanceGroup}) async {
    // debugPrint("$TAG setTyping $chatId $userId $isTyping");
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        chatType: chatType,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        attendanceGroup: attendanceGroup);
    // debugPrint("$TAG setTyping $firebaseChatId $userId $isTyping");
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
      {String? currentUserId, String? otherUserId, bool? attendanceGroup}) {
    // debugPrint('$TAG getTypingUsers Listening to Firebase chat ID: $otherUserId');
    var firebaseChatId = ChatUtils.generateChatId(
        chatType != 'group' ? otherUserId! : chatId,
        chatType: chatType,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        attendanceGroup: attendanceGroup);
    // debugPrint(
    //     '$TAG getTypingUsers Listening to Firebase chat ID: $firebaseChatId');
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
        debugPrint('$TAG Error converting typing data: $e');
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
  // static Stream<Chat?> getChatStream(String chatId) {
  //   return firestore
  //       .collection('chats')
  //       .doc(chatId)
  //       .snapshots(includeMetadataChanges: false)
  //       .handleError((error) {
  //     debugPrint('Chat stream error: $error');
  //     return <DocumentSnapshot>[];
  //   }).map((doc) =>
  //           doc.exists ? Chat.fromFirestore(doc.data()!, doc.id) : null);
  // }

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
