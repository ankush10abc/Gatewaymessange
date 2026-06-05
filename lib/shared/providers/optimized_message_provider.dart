import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import '../../core/models/message_model.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/firebase_realtime_service.dart';
import '../../core/storage/storage_service.dart';
import 'dart:async';

class MessageState {
  final List<Message> messages;
  final bool isLoading;
  final String? error;
  final Map<String, bool> typingUsers;
  final DateTime? lastSyncTime;

  MessageState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.typingUsers = const {},
    this.lastSyncTime,
  });

  MessageState copyWith({
    List<Message>? messages,
    bool? isLoading,
    String? error,
    Map<String, bool>? typingUsers,
    DateTime? lastSyncTime,
  }) {
    return MessageState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      typingUsers: typingUsers ?? this.typingUsers,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

class MessageNotifier extends StateNotifier<MessageState> {
  final String chatId;
  final String chatType;
  
  late final ApiService _apiService;
  final StorageService _storage = StorageService();
  late Box _messageCacheBox;
  
  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;

  MessageNotifier({
    required this.chatId,
    required this.chatType,
  }) : super(MessageState()) {
    final dio = Dio();
    _apiService = ApiService(dio);
    _initializeCache();
  }

  Future<void> _initializeCache() async {
    _messageCacheBox = await Hive.openBox('messages_cache_$chatId');
  }

  /// Load messages with cache-first approach - NO loading indicator
  Future<void> loadMessages({String? currentUserId}) async {
    // 1. Load from cache INSTANTLY
    final cached = await _loadCachedMessages();
    if (cached.isNotEmpty) {
      state = state.copyWith(messages: cached, isLoading: false);
    }

    // 2. Setup Firebase real-time listener
    if (currentUserId != null) {
      _setupRealtimeListeners(currentUserId);
    }

    // 3. Fetch from API in background
    try {
      final token = await _storage.getToken();
      if (token != null) {
        _apiService.setAuthToken(token);
      }

      final int id = int.parse(chatId);
      final response = chatType == 'group'
          ? await _apiService.getGroupMessages(id, 1, 50)
          : await _apiService.getConversation(id, 1, 50);

      final messages = response.data
          .map<Message>((msgData) => Message.fromJson(msgData.toJson()))
          .toList();

      // Update state and cache silently
      state = state.copyWith(
        messages: messages,
        isLoading: false,
        lastSyncTime: DateTime.now(),
      );

      await _saveCachedMessages(messages);
    } catch (e) {
      debugPrint('❌ Message load error (showing cached): $e');
      // Keep showing cached messages
      if (state.messages.isEmpty) {
        state = state.copyWith(error: e.toString(), isLoading: false);
      }
    }
  }

  /// Setup Firebase real-time listeners for instant updates
  void _setupRealtimeListeners(String currentUserId) {
    // Listen to new messages
    _messagesSubscription = FirebaseRealtimeService.getMessagesStreamLimited(
      chatId,
      chatType,
      50,
      currentUserId: currentUserId,
    ).listen((realtimeMessages) {
      if (realtimeMessages.isNotEmpty) {
        final mergedMessages = _mergeMessages(state.messages, realtimeMessages);
        state = state.copyWith(messages: mergedMessages);
        _saveCachedMessages(mergedMessages);
      }
    });

    // Listen to typing indicators
    _typingSubscription = FirebaseRealtimeService.getTypingUsers(
      chatId,
      chatType,
      otherUserId: currentUserId,
    ).listen((typingData) {
      final typingUsers = <String, bool>{};
      typingData.forEach((userId, data) {
        if (data is Map && data['isTyping'] == true && userId != currentUserId) {
          typingUsers[userId] = true;
        }
      });
      state = state.copyWith(typingUsers: typingUsers);
    });
  }

  /// Send message with optimistic UI update
  Future<void> sendMessage({
    required String text,
    required String senderId,
    required String senderName,
    String type = 'text',
    String? fileUrl,
    String? fileName,
    int? fileSize,
    Message? replyToMessage,
  }) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    
    // Create optimistic message
    final optimisticMessage = Message(
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

    // INSTANT UI update - show message immediately
    state = state.copyWith(
      messages: [optimisticMessage, ...state.messages],
    );

    try {
      // Send to Firebase
      final firebaseKey = await FirebaseRealtimeService.sendMessage(
        optimisticMessage,
        chatType: chatType,
        currentUserId: senderId,
      );

      // Send to API
      final sentMessage = chatType == 'group'
          ? await _apiService.sendMessage(
              message: text,
              groupId: chatId,
              messageType: type,
              filePath: fileUrl,
              fileName: fileName,
              fileSize: fileSize,
              firebaseKey: firebaseKey,
              replyToMessageId: replyToMessage?.msgId,
            )
          : await _apiService.sendMessage(
              message: text,
              receiverId: chatId,
              messageType: type,
              filePath: fileUrl,
              fileName: fileName,
              fileSize: fileSize,
              firebaseKey: firebaseKey,
              replyToMessageId: replyToMessage?.msgId,
            );

      // Update with server message
      final updatedMessages = state.messages.map((msg) {
        if (msg.id == tempId) {
          return sentMessage;
        }
        return msg;
      }).toList();

      state = state.copyWith(messages: updatedMessages);
      await _saveCachedMessages(updatedMessages);
    } catch (e) {
      debugPrint('❌ Send failed: $e');
      // Update to failed status
      final updatedMessages = state.messages.map((msg) {
        if (msg.id == tempId) {
          return msg.copyWith(status: {'default': 'failed'});
        }
        return msg;
      }).toList();
      state = state.copyWith(messages: updatedMessages);
    }
  }

  /// Merge API and Firebase messages
  List<Message> _mergeMessages(
    List<Message> apiMessages,
    List<Message> realtimeMessages,
  ) {
    final messageMap = <String, Message>{};

    for (final message in apiMessages) {
      final key = message.firebaseId ?? message.id;
      if (key.isNotEmpty) {
        messageMap[key] = message;
      }
    }

    for (final message in realtimeMessages) {
      final firebaseId = message.firebaseId;
      if (firebaseId != null && firebaseId.isNotEmpty) {
        messageMap[firebaseId] = message;
      } else if (message.id.startsWith('temp_')) {
        messageMap[message.id] = message;
      }
    }

    final mergedList = messageMap.values.toList();
    mergedList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return mergedList;
  }

  Future<List<Message>> _loadCachedMessages() async {
    try {
      final cached = _messageCacheBox.get('messages');
      if (cached != null && cached is List) {
        return cached.map((item) {
          final map = Map<String, dynamic>.from(item);
          return Message.fromJson(map);
        }).toList();
      }
    } catch (e) {
      debugPrint('Cache load error: $e');
    }
    return [];
  }

  Future<void> _saveCachedMessages(List<Message> messages) async {
    try {
      final jsonList = messages.map((m) => m.toJson()).toList();
      await _messageCacheBox.put('messages', jsonList);
    } catch (e) {
      debugPrint('Cache save error: $e');
    }
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _typingSubscription?.cancel();
    super.dispose();
  }
}

final messageProvider = StateNotifierProvider.family<MessageNotifier, MessageState, Map<String, String>>(
  (ref, params) {
    return MessageNotifier(
      chatId: params['chatId']!,
      chatType: params['chatType']!,
    );
  },
);
