import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/message_model.dart';
import '../../core/services/message_sync_service.dart';

class ChatMessagesState {
  final List<Message> messages;
  final bool isLoading;
  final bool hasMoreMessages;
  final String? error;

  const ChatMessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.hasMoreMessages = true,
    this.error,
  });

  ChatMessagesState copyWith({
    List<Message>? messages,
    bool? isLoading,
    bool? hasMoreMessages,
    String? error,
  }) {
    return ChatMessagesState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
      error: error ?? this.error,
    );
  }
}

class ChatMessagesNotifier extends StateNotifier<ChatMessagesState> {
  final String chatId;
  final String chatType;
  final String? currentUserId;
  final String? userRole;
  final MessageSyncService _syncService = MessageSyncService();

  ChatMessagesNotifier({
    required this.chatId,
    required this.chatType,
    this.currentUserId,
    this.userRole,
  }) : super(const ChatMessagesState()) {
    _init();
  }

  void _init() {
    _syncService.watchMessages(chatId, chatType, currentUserId: currentUserId, userRole: userRole).listen((messages) {
      if (mounted) {
        state = state.copyWith(
          messages: messages,
          isLoading: false,
        );
      }
    });
  }

  void addOptimisticMessage(Message message) {
    state = state.copyWith(
      messages: [message, ...state.messages],
    );
    _syncService.addMessageToCache(chatId, chatType, message, currentUserId: currentUserId, userRole: userRole);
  }

  void updateMessage(String tempId, Message newMessage) {
    final updatedMessages = state.messages.map((msg) {
      if (msg.id == tempId) {
        return newMessage;
      }
      return msg;
    }).toList();
    
    state = state.copyWith(messages: updatedMessages);
    _syncService.addMessageToCache(chatId, chatType, newMessage, currentUserId: currentUserId, userRole: userRole);
  }

  void updateMessageStatus(String messageId, String status) {
    final updatedMessages = state.messages.map((msg) {
      if (msg.id == messageId || msg.firebaseId == messageId) {
        return msg.copyWith(status: {'default': status});
      }
      return msg;
    }).toList();
    
    state = state.copyWith(messages: updatedMessages);
    _syncService.updateMessageInCache(
      chatId,
      chatType,
      messageId,
      {'status': {'default': status}},
      currentUserId: currentUserId,
      userRole: userRole,
    );
  }

  void mergeRealtimeMessages(List<Message> realtimeMessages) {
    final messageMap = <String, Message>{};
    
    // Add existing messages
    for (final message in state.messages) {
      final key = message.firebaseId ?? message.id;
      if (key.isNotEmpty) {
        messageMap[key] = message;
      }
    }
    
    // Merge realtime messages
    for (final message in realtimeMessages) {
      final key = message.firebaseId ?? message.id;
      if (key.isNotEmpty) {
        // Remove temp message if exists
        final tempKey = messageMap.keys.firstWhere(
          (k) => k.startsWith('temp_') && messageMap[k]?.text == message.text,
          orElse: () => '',
        );
        if (tempKey.isNotEmpty) {
          messageMap.remove(tempKey);
        }
        messageMap[key] = message;
      }
    }
    
    final mergedMessages = messageMap.values.toList();
    mergedMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    state = state.copyWith(messages: mergedMessages);
  }

  void setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  @override
  void dispose() {
    super.dispose();
  }
}

final chatMessagesProvider = StateNotifierProvider.autoDispose
    .family<ChatMessagesNotifier, ChatMessagesState, Map<String, String?>>(
  (ref, params) {
    final chatId = params['chatId']!;
    final chatType = params['chatType']!;
    final currentUserId = params['currentUserId'];
    final userRole = params['userRole'];
    
    return ChatMessagesNotifier(
      chatId: chatId,
      chatType: chatType,
      currentUserId: currentUserId,
      userRole: userRole,
    );
  },
);