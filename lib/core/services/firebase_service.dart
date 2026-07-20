import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';
import '../models/user_model.dart';

class FirebaseService {
  static final DatabaseReference _database = FirebaseDatabase.instance.ref();
  static final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;

  // Guard: register onDisconnect only once per session to avoid duplicate writes
  static final Set<String> _presenceRegistered = {};

  // User presence management — writes to presence/ node, not users/ node
  static Future<void> setUserOnline(String userId) async {
    try {
      final ref = _database.child('presence/$userId');
      await ref.update({'isOnline': true, 'lastSeen': ServerValue.timestamp});
      if (!_presenceRegistered.contains(userId)) {
        await ref.onDisconnect().update({
          'isOnline': false,
          'lastSeen': ServerValue.timestamp,
        });
        _presenceRegistered.add(userId);
      }
    } catch (e) {
      debugPrint('ERROR setUserOnline: $e');
    }
  }

  static Future<void> setUserOffline(String userId) async {
    _presenceRegistered.remove(userId);
    await _database.child('presence/$userId').update({
      'isOnline': false,
      'lastSeen': ServerValue.timestamp,
    });
  }

  // Debounce map: key → pending timer. Prevents a Firebase write on every keystroke.
  static final Map<String, Timer> _typingTimers = {};

  // Typing indicators — debounced 400 ms, auto-clears after 3 s.
  static Future<void> setTyping(String chatId, String userId, bool isTyping) async {
    debugPrint("setTyping $chatId $userId $isTyping");
    final key = '$chatId/$userId';
    _typingTimers[key]?.cancel();
    _typingTimers.remove(key);

    if (!isTyping) {
      // Immediate clear — no debounce needed for stop-typing
      await _database.child('users/$userId/typing/$chatId').remove();
      return;
    }

    // Debounce: write only after 400 ms of silence
    _typingTimers[key] = Timer(const Duration(milliseconds: 400), () async {
      _typingTimers.remove(key);
      try {
        await _database.child('users/$userId/typing/$chatId').set(true);
        // Auto-clear after 3 s so stale indicators never persist
        Timer(const Duration(seconds: 3), () {
          _database.child('users/$userId/typing/$chatId').remove();
        });
      } catch (_) {}
    });
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

  // Use onChildAdded + onChildChanged — never onValue which re-downloads all
  // N messages on every single status field change (~80-90% bandwidth saving).
  static Stream<List<Message>> getMessages(String chatId, {int limit = 50}) {
    final ref = _database
        .child('chats/$chatId/messages')
        .orderByChild('timestamp')
        .limitToLast(limit);

    // In-memory window: nodeKey → raw data. Shared across both event types.
    final Map<String, Map<String, dynamic>> _live = {};

    List<Message> _build() {
      final list = <Message>[];
      final seen = <String>{};
      for (final e in _live.entries) {
        try {
          final d = Map<String, dynamic>.from(e.value);
          final id = d['firebaseId']?.toString() ?? e.key;
          if (seen.contains(id)) continue;
          seen.add(id);
          d['id'] = id;
          if (d['timestamp'] is int) {
            d['timestamp'] = DateTime.fromMillisecondsSinceEpoch(d['timestamp']).toIso8601String();
          }
          list.add(Message.fromJson(d));
        } catch (_) {}
      }
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return list;
    }

    final controller = StreamController<List<Message>>.broadcast();
    StreamSubscription? addedSub;
    StreamSubscription? changedSub;

    void onEvent(DatabaseEvent event) {
      final key = event.snapshot.key;
      if (key == null) return;
      final raw = event.snapshot.value;
      if (raw == null) {
        _live.remove(key);
      } else if (raw is Map) {
        _live[key] = Map<String, dynamic>.from(raw);
      }
      if (!controller.isClosed) controller.add(_build());
    }

    controller.onListen = () {
      addedSub = ref.onChildAdded.listen(onEvent);
      changedSub = ref.onChildChanged.listen(onEvent);
    };
    controller.onCancel = () {
      addedSub?.cancel();
      changedSub?.cancel();
      _live.clear();
    };
    return controller.stream;
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

  // Use onChildChanged — fires only for the single changed chat entry, not the
  // entire chat_list node. onValue re-downloads ALL chats on every badge update.
  static Stream<List<Chat>> getUserChats(String userId) {
    final ref = _database.child('chat_list/$userId').orderByChild('updatedAt');

    final Map<String, Map<String, dynamic>> _live = {};

    List<Chat> _build() {
      final list = <Chat>[];
      for (final e in _live.entries) {
        try {
          list.add(Chat.fromJson(Map<String, dynamic>.from(e.value)));
        } catch (_) {}
      }
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    }

    final controller = StreamController<List<Chat>>.broadcast();
    StreamSubscription? addedSub;
    StreamSubscription? changedSub;

    void onEvent(DatabaseEvent event) {
      final key = event.snapshot.key;
      if (key == null) return;
      final raw = event.snapshot.value;
      if (raw == null) {
        _live.remove(key);
      } else if (raw is Map) {
        _live[key] = Map<String, dynamic>.from(raw);
      }
      if (!controller.isClosed) controller.add(_build());
    }

    controller.onListen = () {
      // onChildAdded seeds the initial list; onChildChanged handles updates.
      addedSub = ref.onChildAdded.listen(onEvent);
      changedSub = ref.onChildChanged.listen(onEvent);
    };
    controller.onCancel = () {
      addedSub?.cancel();
      changedSub?.cancel();
      _live.clear();
    };
    return controller.stream;
  }

  static Future<void> pinChat(String chatId, bool isPinned) async {
    await _database.child('chats/$chatId').update({'isPinned': isPinned});
  }

  // User management
  static Future<void> updateUserProfile(User user) async {
    // Write only the fields that change — never overwrite the entire user node
    await _database.child('users/${user.id}').update(user.toJson());
  }

  // Presence node only — never read the full user node for online status
  static Stream<User?> getUser(String userId) {
    return _database.child('presence/$userId').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return null;
      return User.fromJson(Map<String, dynamic>.from(data));
    });
  }

  // Search is API-only — never download the entire users node from Firebase
  static Stream<List<User>> searchUsers(String query, String currentUserId) {
    // Return empty stream; callers must use the REST API for user search
    return const Stream.empty();
  }

  static void listenToNewMessages(Function(dynamic) callback) {
    // Implementation for listening to new messages
  }

  static void listenToUserStatusChanges(Function(int, bool) callback) {
    // Implementation for listening to user status changes
  }
}