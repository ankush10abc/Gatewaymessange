import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/models/chat_model.dart';
import '../../core/models/message_model.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/storage/storage_service.dart';

class ChatState {
  final List<Chat> chats;
  final bool isLoading;
  final String? error;

  ChatState({
    this.chats = const [],
    this.isLoading = false,
    this.error,
  });

  ChatState copyWith({
    List<Chat>? chats,
    bool? isLoading,
    String? error,
  }) {
    return ChatState(
      chats: chats ?? this.chats,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  late final ApiService _apiService;
  final StorageService _storage = StorageService();

  ChatNotifier() : super(ChatState()) {
    final dio = Dio();
    _apiService = ApiService(dio);
  }

  Future<void> loadChatList() async {
    state = state.copyWith(isLoading: true);
    
    try {
      final token = await _storage.getToken();
      if (token != null) {
        _apiService.setAuthToken(token);
      }
      
      final response = await _apiService.getChatList();
      final chats = <Chat>[];
      
      for (final item in response) {
        final itemMap = item as Map<String, dynamic>;
        if (itemMap['type'] == 'group') {
          chats.add(Chat(
            id: itemMap['id'].toString(),
            type: 'group',
            participants: [],
            createdAt: DateTime.tryParse(itemMap['updated_at'] ?? '') ?? DateTime.now(),
            updatedAt: DateTime.tryParse(itemMap['updated_at'] ?? '') ?? DateTime.now(),
            unreadCount: {},
            isPinned: itemMap['is_pinned'] ?? false,
            groupName: itemMap['name'],
            profile_picture: itemMap['profile_picture'],
            attendance_group: itemMap['attendance_group'],
            unread_count: itemMap['unread_count'],
            actual_role: itemMap['actual_role'],
          ));
        } else if (itemMap['type'] == 'user') {
          chats.add(Chat(
            id: itemMap['id'].toString(),
            type: 'user',
            participants: [itemMap['id'].toString()],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            unreadCount: {},
            isPinned: itemMap['is_pinned'] ?? false,
            groupName: itemMap['name'],
            profile_picture: itemMap['profile_picture'],
            attendance_group: itemMap['attendance_group'],
            unread_count: itemMap['unread_count'],
            actual_role: itemMap['actual_role'],
          ));
        }
      }
      
      state = state.copyWith(
        chats: chats,
        isLoading: false,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 || e.response?.statusCode == 401) {
        // Interceptor already handled auth clearing and redirect, just set minimal error
        state = state.copyWith(
          error: null,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          error: e.message ?? 'Failed to load chats',
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
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
