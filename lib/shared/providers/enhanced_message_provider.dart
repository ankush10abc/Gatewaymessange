import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/models/message_model.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/firebase_service.dart';
import 'dart:io';

class MessageState {
  final List<Message> messages;
  final bool isLoading;
  final String? error;
  final bool hasMore;
  final int currentPage;

  MessageState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.hasMore = true,
    this.currentPage = 1,
  });

  MessageState copyWith({
    List<Message>? messages,
    bool? isLoading,
    String? error,
    bool? hasMore,
    int? currentPage,
  }) {
    return MessageState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
    );
  }
}

class MessageNotifier extends StateNotifier<MessageState> {
  late final ApiService _apiService;
  final int? chatUserId;
  final int? groupId;

  MessageNotifier({this.chatUserId, this.groupId}) : super(MessageState()) {
    final dio = Dio();
    _apiService = ApiService(dio);
    loadMessages();
  }

  Future<void> loadMessages({bool refresh = false}) async {
    if (state.isLoading) return;
    
    state = state.copyWith(
      isLoading: true,
    );

    try {
      final int page = refresh ? 1 : state.currentPage;
       int limit = ApiService.messageCount;

      final PaginatedResponse<Message> response;
      if (groupId != null) {
        response = await _apiService.getGroupMessages(groupId!, page, limit);
      } else if (chatUserId != null) {
        response = await _apiService.getConversation(chatUserId!, page, limit);
      } else {
        throw Exception('No chat user or group specified');
      }

      final newMessages = response.data;
      final hasMore = newMessages.length == limit;

      state = state.copyWith(
        messages: refresh ? newMessages : [...state.messages, ...newMessages],
        isLoading: false,
        hasMore: hasMore,
        currentPage: page + 1,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  Future<void> sendTextMessage({
    required String content,
    Message? replyToMessage,
  }) async {
    try {
      // Send to API
      final message = await _apiService.sendMessage(
        message: content,
        receiverId: chatUserId?.toString(),
        groupId: groupId?.toString(),
        messageType: 'text',
        replyToMessageId: replyToMessage?.id,
      );
      
      // Send to Firebase for real-time
      await FirebaseService.sendMessage(message);

      // Add to local state
      state = state.copyWith(
        messages: [message, ...state.messages],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> sendMediaMessage({
    required File file,
    required String messageType,
    String? caption,
    Message? replyToMessage,
  }) async {
    try {
      // Upload file first
      final uploadResponse = await _apiService.uploadFile(file, messageType);
      
      // Send to API
      final message = await _apiService.sendMessage(
        message: caption ?? '',
        receiverId: chatUserId?.toString(),
        groupId: groupId?.toString(),
        messageType: messageType,
        filePath: uploadResponse.filePath,
        fileName: uploadResponse.fileName,
        replyToMessageId: replyToMessage?.id,
      );
      
      // Send to Firebase for real-time
      await FirebaseService.sendMessage(message);

      // Add to local state
      state = state.copyWith(
        messages: [message, ...state.messages],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> markMessageAsRead(int messageId) async {
    try {
      await _apiService.markMessageAsRead(messageId);
    } catch (e) {
      // Ignore errors for read receipts
    }
  }

  Future<void> markMessageAsDelivered(int messageId) async {
    try {
      await _apiService.markMessageAsDelivered(messageId);
    } catch (e) {
      // Ignore errors for delivery receipts
    }
  }

  void clearError() {
    state = state.copyWith(error: '');
  }

  void addMessage(Message message) {
    state = state.copyWith(
      messages: [message, ...state.messages],
    );
  }

  void updateMessage(Message updatedMessage) {
    final messages = state.messages.map((msg) {
      return msg.id == updatedMessage.id ? updatedMessage : msg;
    }).toList();
    
    state = state.copyWith(messages: messages);
  }
}

// Provider factory for different chats
final messageProvider = StateNotifierProvider.family<MessageNotifier, MessageState, Map<String, int?>>(
  (ref, params) => MessageNotifier(
    chatUserId: params['userId'],
    groupId: params['groupId'],
  ),
);