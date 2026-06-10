import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/models/message_model.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/message_sync_service.dart';
import '../../core/services/firebase_realtime_service.dart';
import '../../core/storage/storage_service.dart';

/// Chat message state
class ChatMessageState {
  final List<Message> messages;
  final Map<String, dynamic>? chatInfo;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int currentPage;

  ChatMessageState({
    this.messages = const [],
    this.chatInfo,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.currentPage = 1,
  });

  ChatMessageState copyWith({
    List<Message>? messages,
    Map<String, dynamic>? chatInfo,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? currentPage,
  }) {
    return ChatMessageState(
      messages: messages ?? this.messages,
      chatInfo: chatInfo ?? this.chatInfo,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      currentPage: currentPage ?? this.currentPage,
    );
  }
}

/// Message notifier for a specific chat
class ChatMessageNotifier extends StateNotifier<ChatMessageState> {
  final String chatId;
  final String chatType;
  final String? currentUserId;
  final String? userRole;
  final ApiService apiService;
  final MessageSyncService syncService;
  final StorageService storage;

  ChatMessageNotifier({
    required this.chatId,
    required this.chatType,
    this.currentUserId,
    this.userRole,
    required this.apiService,
    required this.syncService,
    required this.storage,
  }) : super(ChatMessageState()) {
    _initialize();
  }

  /// Initialize: Load from cache first, then sync from API
  Future<void> _initialize() async {
    try {
      // Phase 1: Load cached messages instantly (0ms)
      final cachedMessages = await syncService.getCachedMessages(
        chatId, 
        chatType,
        currentUserId: currentUserId,
        userRole: userRole,
      );
      if (cachedMessages.isNotEmpty) {
        state = state.copyWith(messages: cachedMessages);
        debugPrint('✅ Displayed ${cachedMessages.length} cached messages instantly');
      } else {
        state = state.copyWith(isLoading: true);
      }

      // Phase 2: Load from API in background
      final token = await storage.getToken();
      if (token != null) {
        apiService.setAuthToken(token);
      }

      final result = await syncService.loadMessagesFromApi(
        chatId: chatId,
        chatType: chatType,
        apiService: apiService,
        currentUserId: currentUserId,
        userRole: userRole,
        page: 1,
        limit: 50,
      );

      state = state.copyWith(
        messages: result['messages'],
        chatInfo: result['user'],
        isLoading: false,
        hasMore: result['has_more'],
        currentPage: 1,
      );

      debugPrint('✅ Loaded ${result['messages'].length} messages from API');
    } catch (e) {
      debugPrint('❌ Initialize error: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Load more messages (pagination)
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final nextPage = state.currentPage + 1;
      final result = await syncService.loadMessagesFromApi(
        chatId: chatId,
        chatType: chatType,
        apiService: apiService,
        currentUserId: currentUserId,
        userRole: userRole,
        page: nextPage,
        limit: 50,
      );

      final newMessages = result['messages'] as List<Message>;
      final allMessages = [...state.messages, ...newMessages];

      state = state.copyWith(
        messages: allMessages,
        isLoadingMore: false,
        hasMore: newMessages.length >= 50,
        currentPage: nextPage,
      );

      debugPrint('✅ Loaded ${newMessages.length} more messages (page $nextPage)');
    } catch (e) {
      debugPrint('❌ Load more error: $e');
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Add message optimistically (for sending)
  void addOptimisticMessage(Message message) {
    final updatedMessages = [message, ...state.messages];
    state = state.copyWith(messages: updatedMessages);
    
    // Cache it immediately
    syncService.addMessageToCache(
      chatId, 
      chatType, 
      message,
      currentUserId: currentUserId,
      userRole: userRole,
    );
  }

  /// Update message after API response
  void updateMessage(String tempId, Message newMessage) {
    final updatedMessages = state.messages.map((msg) {
      if (msg.id == tempId) {
        return newMessage;
      }
      return msg;
    }).toList();
    
    state = state.copyWith(messages: updatedMessages);
    
    // Update cache
    syncService.addMessageToCache(
      chatId, 
      chatType, 
      newMessage,
      currentUserId: currentUserId,
      userRole: userRole,
    );
  }

  /// Update message status
  void updateMessageStatus(String messageId, String status) {
    final updatedMessages = state.messages.map((msg) {
      if (msg.id == messageId || msg.firebaseId == messageId) {
        return msg.copyWith(status: {'default': status});
      }
      return msg;
    }).toList();
    
    state = state.copyWith(messages: updatedMessages);
    
    // Update cache with correct method name
    syncService.updateMessageInCache(
      chatId,
      chatType,
      messageId,
      {'status': {'default': status}},
      currentUserId: currentUserId,
      userRole: userRole,
    );
  }

  /// Merge Firebase real-time messages
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

  /// Refresh messages from API
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, currentPage: 1);
    await _initialize();
  }
}

/// Provider family for chat messages
final chatMessageProvider = StateNotifierProvider.family<ChatMessageNotifier, ChatMessageState, Map<String, String?>>((ref, params) {
  final chatId = params['chatId']!;
  final chatType = params['chatType']!;
  final currentUserId = params['currentUserId'];
  final userRole = params['userRole'];
  
  final dio = Dio();
  final apiService = ApiService(dio);
  final syncService = MessageSyncService();
  final storage = StorageService();

  return ChatMessageNotifier(
    chatId: chatId,
    chatType: chatType,
    currentUserId: currentUserId,
    userRole: userRole,
    apiService: apiService,
    syncService: syncService,
    storage: storage,
  );
});
