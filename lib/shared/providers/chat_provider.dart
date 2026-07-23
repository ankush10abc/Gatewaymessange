import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/models/chat_model.dart';
import '../../core/models/message_model.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/chat_list_manager.dart';
import '../../core/storage/storage_service.dart';
import 'package:hive/hive.dart';

class ChatState {
  final List<Chat> chats;
  final bool isLoading;
  final String? error;
  final DateTime? lastSyncTime;

  ChatState({
    this.chats = const [],
    this.isLoading = false,
    this.error,
    this.lastSyncTime,
  });

  ChatState copyWith({
    List<Chat>? chats,
    bool? isLoading,
    String? error,
    DateTime? lastSyncTime,
  }) {
    return ChatState(
      chats: chats ?? this.chats,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  late final ApiService _apiService;
  final StorageService _storage = StorageService();
  String? _currentUserId;

  ChatNotifier() : super(ChatState()) {
    final dio = Dio();
    _apiService = ApiService(dio);
    _initializeChatManager();
  }

  Future<void> _initializeChatManager() async {
    final userId = await _storage.getUserId();
    if (userId != null) {
      _currentUserId = userId;
      await ChatListManager.init(userId);
    }
  }

  Future<void> loadChatList() async {
    final cachedChats = ChatListManager.getSortedChatList();
    if (cachedChats.isNotEmpty) {
      state = state.copyWith(chats: cachedChats, isLoading: false);
    }
    
    _syncInBackground();
  }

  Future<void> _syncInBackground() async {
    try {
      final token = await _storage.getToken();
      if (token == null) return;
      
      _apiService.setAuthToken(token);
      
      final response = await _apiService.getChatList();
      final chats = <Chat>[];
      
      for (final item in response) {
        final itemMap = item as Map<String, dynamic>;
        chats.add(Chat.fromJson(itemMap));
      }
      
      await ChatListManager.syncFromAPI(chats);
      
      final sortedChats = ChatListManager.getSortedChatList();
      state = state.copyWith(
        chats: sortedChats,
        isLoading: false,
        lastSyncTime: DateTime.now(),
      );
    } catch (e) {

      debugPrint('Background sync failed: $e');
      if (state.chats.isEmpty) {
        state = state.copyWith(error: e.toString(), isLoading: false);
      }
    }
  }

  Future<void> onMessageSent(String chatId, String chatType, Message message) async {
    if (_currentUserId == null) return;
    
    await ChatListManager.onMessageSent(
      chatId: chatId,
      chatType: chatType,
      message: message,
      currentUserId: _currentUserId!,
    );
    
    final sortedChats = ChatListManager.getSortedChatList();
    state = state.copyWith(chats: sortedChats);
  }

  /// Called when a message is received. If isChatScreenOpen is true,
  /// the message is immediately marked as read and unread count stays at 0.
  Future<void> onMessageReceived(String chatId, String chatType, Message message, bool isChatScreenOpen) async {
    if (_currentUserId == null) return;
    
    await ChatListManager.onMessageReceived(
      chatId: chatId,
      chatType: chatType,
      message: message,
      currentUserId: _currentUserId!,
      isChatScreenOpen: isChatScreenOpen, // When true, unread count stays at 0
    );
    
    final sortedChats = ChatListManager.getSortedChatList();
    state = state.copyWith(chats: sortedChats);
  }

  Future<void> resetUnreadCount(String chatId) async {
    if (_currentUserId == null) return;
    
    await ChatListManager.resetUnreadCount(chatId, _currentUserId!);
    
    final sortedChats = ChatListManager.getSortedChatList();
    state = state.copyWith(chats: sortedChats);
  }

  void loadUserChats(String userId) {
    state = state.copyWith(isLoading: true);

    FirebaseService.getUserChats(userId).listen(
      (chats) {
        state = state.copyWith(
          chats: chats,
          isLoading: false,
        );
      },
      onError: (error) {
        state = state.copyWith(
          error: error.toString(),
          isLoading: false,
        );
      },
    );
  }

  Future<void> pinChat(String chatId, bool isPinned) async {
    try {
      await FirebaseService.pinChat(chatId, isPinned);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<String> createPrivateChat(String otherUserId, String currentUserId) async {
    try {
      final chat = Chat(
        id: '',
        type: 'private',
        participants: [currentUserId, otherUserId],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        unreadCount: {},
      );

      return await FirebaseService.createChat(chat);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<String> createGroupChat({
    required String name,
    required String description,
    required List<String> members,
    required String creatorId,
  }) async {
    try {
      final chat = Chat(
        id: '',
        type: 'group',
        participants: members,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        unreadCount: {},
        groupName: name,
        groupDescription: description,
        groupRoles: {creatorId: 'admin'},
      );

      return await FirebaseService.createChat(chat);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  void clearError() {
    state = state.copyWith();
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier();
});
