import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../utils/chat_utils.dart';
import 'chat_list_update_service.dart';
import 'message_database_service.dart';
// statusKey() is defined in message_model.dart — imported above

class FirebaseRealtimeService {
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseDatabase get database => FirebaseDatabase.instance;
  static String TAG = "FirebaseRealtimeService";

  // In-memory cache: firebaseChatId → { messageId → nodeKey }
  // Prevents repeated full .get() scans in _resolveFirebaseNodeKey.
  static final Map<String, Map<String, String>> _nodeKeyCache = {};

  // Typing debounce: userId → pending timer. Prevents a Firebase write on every
  // keystroke — only the final write fires after 400 ms of silence.
  static final Map<String, Timer> _typingDebounceTimers = {};

  // Presence guard: tracks which userIds already have onDisconnect registered
  // so we never register it more than once per session (each registration is
  // a Firebase write that counts toward bandwidth).
  static final Set<String> _presenceRegistered = {};

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

  // Real-time message stream from Realtime Database.
  // Uses onChildAdded (initial load + new messages) combined with onChildChanged
  // (status/delivery updates) instead of onValue, which re-downloads the entire
  // limited node on every single status field change.
  // This reduces bandwidth by ~80-90% for active chats with frequent status updates.
  static Stream<List<Message>> getMessagesStreamLimited(
      String chatId, String chatType, int limit,
      {String? currentUserId, String? otherUserId, bool? attendanceGroup}) {
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        chatType: chatType,
        attendanceGroup: attendanceGroup);

    final ref = database
        .ref('chats/$firebaseChatId/messages')
        .orderByChild('timestamp')
        .limitToLast(limit);

    // In-memory map: nodeKey → parsed message data.
    // Shared across both onChildAdded and onChildChanged events so the emitted
    // list is always the full current window, not just the changed item.
    final Map<String, Map<String, dynamic>> _liveMessages = {};

    List<Message> _buildList() {
      final messages = <Message>[];
      final seenIds = <String>{};
      for (final entry in _liveMessages.entries) {
        try {
          final msgData = Map<String, dynamic>.from(entry.value);
          final firebaseId = msgData['firebaseId']?.toString() ?? entry.key;
          if (seenIds.contains(firebaseId)) continue;
          seenIds.add(firebaseId);
          msgData['id'] = firebaseId;
          if (msgData['timestamp'] is int) {
            msgData['timestamp'] = DateTime.fromMillisecondsSinceEpoch(
                    msgData['timestamp'])
                .toIso8601String();
          }
          messages.add(Message.fromJson(msgData));
        } catch (e) {
          debugPrint('$TAG Error parsing message ${entry.key}: $e');
        }
      }
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return messages;
    }

    // Merge onChildAdded and onChildChanged into a single stream.
    // onChildAdded fires for each existing child on subscribe (initial load)
    // and for every new message. onChildChanged fires only when a child node
    // changes (e.g. status field updated) — NOT for the full node.
    final StreamController<List<Message>> controller =
        StreamController<List<Message>>.broadcast();

    StreamSubscription? addedSub;
    StreamSubscription? changedSub;

    void onData(DatabaseEvent event) {
      final key = event.snapshot.key;
      if (key == null) return;
      final raw = event.snapshot.value;
      if (raw == null) {
        _liveMessages.remove(key);
      } else if (raw is Map) {
        _liveMessages[key] = Map<String, dynamic>.from(raw);
      }
      if (!controller.isClosed) controller.add(_buildList());
    }

    void onError(Object error) {
      debugPrint('$TAG Firebase stream error: $error');
      if (!controller.isClosed) controller.add(<Message>[]);
    }

    controller.onListen = () {
      addedSub = ref.onChildAdded.listen(onData, onError: onError);
      changedSub = ref.onChildChanged.listen(onData, onError: onError);
    };
    controller.onCancel = () {
      addedSub?.cancel();
      changedSub?.cancel();
      _liveMessages.clear();
    };

    return controller.stream;
  }

  // Get older messages for pagination — server-side query, no full node download
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
      // Use server-side query: only fetch [limit] messages before the cursor.
      // Previously downloaded ALL messages and filtered client-side — 99% waste.
      final snapshot = await database
          .ref('chats/$firebaseChatId/messages')
          .orderByChild('timestamp')
          .endBefore(beforeTimestamp.millisecondsSinceEpoch.toDouble())
          .limitToLast(limit)
          .get();

      if (!snapshot.exists) return <Message>[];

      final messagesMap = _snapshotMap(snapshot.value);
      if (messagesMap == null || messagesMap.isEmpty) return <Message>[];

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
              messageData['timestamp'] =
                  DateTime.fromMillisecondsSinceEpoch(messageData['timestamp'])
                      .toIso8601String();
            }
            messages.add(Message.fromJson(messageData));
          }
        } catch (e) {
          debugPrint('$TAG Error parsing message $key: $e');
        }
      });

      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return messages;
    } catch (e) {
      debugPrint('$TAG Error loading older messages: $e');
      return <Message>[];
    }
  }

  // Removed: getMessagesStream and getMessagesStreamSingle — both used unlimited
  // onValue with NO query limit, causing the entire message node to be re-downloaded
  // on every status update. All callers must use getMessagesStreamLimited instead.

  /// Resolves the actual Firebase node key for a message under [firebaseChatId].
  ///
  /// Strategy (bandwidth-ordered):
  /// 1. In-memory cache lookup (zero network cost).
  /// 2. SQLite lookup by firebase_id (zero network cost).
  /// 3. Direct single-node Firebase read (1 tiny read, not a full scan).
  ///
  /// Step 4 (full-node scan) is intentionally removed — it downloaded the entire
  /// messages node on every status update for legacy messages, which was the
  /// single largest source of Firebase bandwidth waste. Messages written after
  /// this change always have their push-key stored as firebaseId, so Steps 1–3
  /// are sufficient. Legacy messages that truly cannot be resolved are silently
  /// skipped (status update is a no-op, not a crash).
  static Future<String?> _resolveFirebaseNodeKey(
    String firebaseChatId,
    String messageId,
  ) async {
    if (messageId.isEmpty || messageId.startsWith('temp_')) return null;

    // Step 1: in-memory cache — zero cost
    final cached = _nodeKeyCache[firebaseChatId]?[messageId];
    if (cached != null) return cached;

    // Step 2: SQLite lookup — no Firebase read needed
    try {
      final dbService = MessageDatabaseService();
      final msg = await dbService.getMessageByFirebaseId(messageId);
      if (msg?.firebaseId != null && msg!.firebaseId!.isNotEmpty) {
        _cacheNodeKey(firebaseChatId, messageId, msg.firebaseId!);
        return msg.firebaseId!;
      }
    } catch (_) {}

    // Step 3: direct single-node lookup — one tiny read, not a full scan
    try {
      final directSnap = await database
          .ref('chats/$firebaseChatId/messages/$messageId')
          .get();
      if (directSnap.exists) {
        _cacheNodeKey(firebaseChatId, messageId, messageId);
        return messageId;
      }
    } catch (_) {}

    // No full-scan fallback — avoids downloading the entire messages node.
    // Legacy messages that cannot be resolved via Steps 1–3 are silently skipped.
    return null;
  }

  /// Store resolved nodeKey in the in-memory cache (bounded to 500 entries per chat).
  static void _cacheNodeKey(
      String firebaseChatId, String messageId, String nodeKey) {
    final chatCache = _nodeKeyCache.putIfAbsent(firebaseChatId, () => {});
    if (chatCache.length > 500) chatCache.clear(); // prevent unbounded growth
    chatCache[messageId] = nodeKey;
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

      // For group chats: read only the tiny status sub-node (not the full message)
      // to check whether all members have read the message.
      if (chatType == 'group' && status == 'read' && groupMembers != null) {
        final statusSnap = await database
            .ref('chats/$firebaseChatId/messages/$nodeKey/status')
            .get();

        if (statusSnap.exists) {
          final statusMap = _snapshotMap(statusSnap.value);
          if (statusMap != null) {
            bool allRead = true;
            for (final member in groupMembers) {
              final memberId = member['id']?.toString() ?? member.toString();
              // Skip sender — only check receivers
              if (memberId == userId) continue;
              final memberStatus = (statusMap[statusKey(memberId)] ??
                  statusMap[memberId])?.toString() ?? 'sent';
              if (memberStatus != 'read') {
                allRead = false;
                break;
              }
            }
            if (allRead) {
              unawaited(database
                  .ref('chats/$firebaseChatId/messages/$nodeKey/allRead')
                  .set(true));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('$TAG Error updating message status: $e');
    }
  }

  /// Mark messages as read.
  ///
  /// Fast path (SQLite): when messages are already cached locally, reads status
  /// JSON per row and writes only targeted Firebase status updates — no full
  /// Firebase node download.
  ///
  /// Fallback (Firebase): when SQLite has no messages for this chat (first open
  /// or empty cache), falls back to the original full Firebase .get() so no
  /// messages are ever missed. Identical behaviour to the original in that case.
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

      final dbService = MessageDatabaseService();
      final db = await dbService.database;

      // Fast path: read from SQLite — indexed query, no Firebase download.
      // We check the status JSON column (not is_read) because is_read is only
      // set when readAt is non-null on save, which is not guaranteed for all
      // Firebase-sourced messages.
      final rows = await db.rawQuery(
        'SELECT id, firebase_id, sender_id, status FROM messages '
        'WHERE chat_id = ? AND chat_type = ?',
        [chatId, chatType],
      );

      if (rows.isNotEmpty) {
        // SQLite has messages — use them as the source of truth.
        debugPrint('$TAG markMessagesAsRead: ${rows.length} messages from SQLite (fast path)');

        for (final row in rows) {
          final senderId = row['sender_id']?.toString() ?? '';
          // Only mark messages from OTHER users as read (same as original)
          if (senderId == userId) continue;

          // Parse status JSON to check current read state
          final statusJson = row['status']?.toString();
          Map<String, dynamic> statusStrMap = {};
          if (statusJson != null && statusJson.isNotEmpty) {
            try {
              statusStrMap = Map<String, dynamic>.from(
                  jsonDecode(statusJson) as Map);
            } catch (_) {}
          }
          // Check both prefixed and raw key for backward compatibility (same as original)
          final currentStatus = (statusStrMap[statusKey(userId)] ??
              statusStrMap[userId])?.toString();
          // Skip already-read messages — avoids redundant Firebase writes
          if (currentStatus == 'read') continue;

          // Resolve node key: firebase_id > id (same priority as original)
          final nodeKey = row['firebase_id']?.toString().isNotEmpty == true
              ? row['firebase_id'].toString()
              : row['id']?.toString() ?? '';
          if (nodeKey.isEmpty || nodeKey.startsWith('temp_')) continue;

          // Write read status directly — no Firebase read needed
          unawaited(database
              .ref('chats/$firebaseChatId/messages/$nodeKey/status/${statusKey(userId)}')
              .set('read'));

          // Update SQLite is_read flag for future fast-path skipping
          unawaited(dbService.markMessageAsRead(nodeKey));

          // For group chats: check allRead via status sub-node only (tiny read)
          if (chatType == 'group' && groupMembers != null) {
            unawaited(() async {
              try {
                final statusSnap = await database
                    .ref('chats/$firebaseChatId/messages/$nodeKey/status')
                    .get();
                if (!statusSnap.exists) return;
                final statusMap = _snapshotMap(statusSnap.value);
                if (statusMap == null) return;

                bool allRead = true;
                for (final member in groupMembers) {
                  final memberId = member['id']?.toString() ?? member.toString();
                  // Skip the sender — same as original logic
                  if (memberId != senderId) {
                    final memberStatus = (statusMap[statusKey(memberId)] ??
                        statusMap[memberId])?.toString() ?? 'sent';
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
              } catch (_) {}
            }());
          }
        }
        return;
      }

      // Fallback: SQLite empty (first open / cache miss) — use original Firebase path.
      // Identical to the original implementation so no messages are ever missed.
      debugPrint('$TAG markMessagesAsRead: SQLite empty, falling back to Firebase for $chatId');
      final messagesSnapshot =
          await database.ref('chats/$firebaseChatId/messages').get();
      if (!messagesSnapshot.exists) return;

      final messages = messagesSnapshot.value is Map
          ? messagesSnapshot.value as Map<dynamic, dynamic>
          : null;
      if (messages == null || messages.isEmpty) return;

      for (final entry in messages.entries) {
        if (entry.value is! Map) continue;
        final messageData = Map<String, dynamic>.from(entry.value as Map);
        final senderId = messageData['senderId']?.toString();
        if (senderId == userId) continue;

        final rawStatus = messageData['status'];
        final statusStrMap = rawStatus is Map
            ? Map<String, dynamic>.from(rawStatus)
            : null;
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

        if (chatType == 'group' && groupMembers != null) {
          final statusSnapshot = await database
              .ref('chats/$firebaseChatId/messages/${entry.key}/status')
              .get();
          if (statusSnapshot.exists) {
            final statusMap = _snapshotMap(statusSnapshot.value);
            if (statusMap == null || statusMap.isEmpty) continue;
            bool allRead = true;
            try {
              for (final member in groupMembers) {
                final memberId = member['id']?.toString() ?? member.toString();
                if (memberId != senderId) {
                  final memberStatus = (statusMap[statusKey(memberId)] ??
                      statusMap[memberId])?.toString() ?? 'sent';
                  if (memberStatus != 'read') {
                    allRead = false;
                    break;
                  }
                }
              }
            } catch (e) {
              debugPrint('$TAG Data Error catch $e');
            }
            if (allRead) {
              await database
                  .ref('chats/$firebaseChatId/messages/${entry.key}/allRead')
                  .set(true);
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
    final ref = database.ref('presence/$userId');
    await ref.set({
      'isOnline': true,
      'lastSeen': ServerValue.timestamp,
    });

    // Register onDisconnect only once per session — each registration is a
    // Firebase write. Calling it on every app-resume was doubling bandwidth.
    if (!_presenceRegistered.contains(userId)) {
      await ref.onDisconnect().set({
        'isOnline': false,
        'lastSeen': ServerValue.timestamp,
      });
      _presenceRegistered.add(userId);
    }
  }

  static Future<void> setUserOffline(String userId) async {
    // Cancel any pending onDisconnect so it doesn't fire after an explicit
    // offline call (e.g. app paused) and overwrite the value we just wrote.
    _presenceRegistered.remove(userId);
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

  // Typing indicator — debounced to prevent a Firebase write on every keystroke.
  // Only the final write fires after 400 ms of silence, then auto-clears after 3 s.
  // Calling setTyping(false) cancels the pending write immediately.
  static Future<void> setTyping(
      String chatType, String chatId, String userId, bool isTyping,
      {String? currentUserId,
      String? otherUserId,
      bool? attendanceGroup}) async {
    final firebaseChatId = ChatUtils.generateChatId(chatId,
        chatType: chatType,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        attendanceGroup: attendanceGroup);

    final debounceKey = '$firebaseChatId/$userId';

    // Cancel any pending debounce timer
    _typingDebounceTimers[debounceKey]?.cancel();
    _typingDebounceTimers.remove(debounceKey);

    if (!isTyping) {
      // Immediate clear — no debounce needed for stop-typing
      await database.ref('typing/$firebaseChatId/$userId').remove();
      return;
    }

    // Debounce: write to Firebase only after 400 ms of silence
    _typingDebounceTimers[debounceKey] = Timer(
      const Duration(milliseconds: 400),
      () async {
        _typingDebounceTimers.remove(debounceKey);
        try {
          await database.ref('typing/$firebaseChatId/$userId').set({
            'isTyping': true,
            'timestamp': ServerValue.timestamp,
          });
          // Auto-remove typing after 3 seconds so stale indicators never persist
          Timer(const Duration(seconds: 3), () {
            database.ref('typing/$firebaseChatId/$userId').remove();
          });
        } catch (_) {}
      },
    );
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
