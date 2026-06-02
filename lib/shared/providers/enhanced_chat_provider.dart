import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/models/chat_list_model.dart';
import '../../core/models/user_model.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/firebase_service.dart';

class EnhancedChatState {
  final List<ChatModel> chats;
  final List<ChatModel> groups;
  final bool isLoading;
  final String? error;

  EnhancedChatState({
    this.chats = const [],
    this.groups = const [],
    this.isLoading = false,
    this.error,
  });

  EnhancedChatState copyWith({
    List<ChatModel>? chats,
    List<ChatModel>? groups,
    bool? isLoading,
    String? error,
  }) {
    return EnhancedChatState(
      chats: chats ?? this.chats,
      groups: groups ?? this.groups,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class EnhancedChatNotifier extends StateNotifier<EnhancedChatState> {
  late final ApiService _apiService;

  EnhancedChatNotifier() : super(EnhancedChatState()) {
    final dio = Dio();
    _apiService = ApiService(dio);
    loadChats();
  }

  Future<void> loadChats() async {
    state = state.copyWith(isLoading: true);

    try {
      // Load chat list (pinned + message history)
      final chatListResponse = await _apiService.getChatList();
      
      // Convert dynamic response to ChatModel
      final chats = chatListResponse.map((item) {
        final itemMap = item as Map<String, dynamic>;
        return ChatModel.fromJson(itemMap);
      }).toList();

      // Separate pinned and regular chats
      final pinnedChats = chats.where((chat) => chat.isPinned == true).toList();
      final regularChats = chats.where((chat) => chat.isPinned != true).toList();

      // Combine pinned first, then regular
      final sortedChats = [...pinnedChats, ...regularChats];

      state = state.copyWith(
        chats: sortedChats,
        groups: [],
        isLoading: false,
      );

      // Set up Firebase listeners for real-time updates
      _setupFirebaseListeners();
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  void _setupFirebaseListeners() {
    // Listen for new messages to update chat list
    FirebaseService.listenToNewMessages((message) {
      _updateChatWithNewMessage(message);
    });

    // Listen for user online status changes
    FirebaseService.listenToUserStatusChanges((userId, isOnline) {
      _updateUserOnlineStatus(userId, isOnline);
    });
  }

  void _updateChatWithNewMessage(dynamic message) {
    // Update the chat list with new message info
    final updatedChats = state.chats.map((chat) {
      if ((message['receiver_id'] != null && chat.userId == message['receiver_id']) ||
          (message['group_id'] != null && chat.groupId == message['group_id'])) {
        return chat.copyWith(
          lastMessage: message['message'],
          lastMessageTime: DateTime.now(),
          unreadCount: {...?chat.unreadCount, 'total': (chat.unreadCount?['total'] ?? 0) + 1},
        );
      }
      return chat;
    }).toList();

    state = state.copyWith(chats: updatedChats);
  }

  void _updateUserOnlineStatus(int userId, bool isOnline) {
    final updatedChats = state.chats.map((chat) {
      if (chat.userId == userId) {
        return chat.copyWith(isOnline: isOnline);
      }
      return chat;
    }).toList();

    state = state.copyWith(chats: updatedChats);
  }

  Future<void> refreshChats() async {
    await loadChats();
  }

  Future<List<User>> searchUsers(String query) async {
    try {
      return await _apiService.searchUsers(query);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<List<User>> getTeachers() async {
    try {
      return await _apiService.getTeachers();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<List<User>> getParents() async {
    try {
      return await _apiService.getParents();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<List<User>> getChatPermissions() async {
    try {
      return await _apiService.getChatPermissions();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  void markChatAsRead(String chatId) {
    final updatedChats = state.chats.map((chat) {
      if (chat.id == chatId) {
        return chat.copyWith(unreadCount: {});
      }
      return chat;
    }).toList();

    state = state.copyWith(chats: updatedChats);
  }

  void clearError() {
    state = state.copyWith();
  }

  Future<void> createPrivateChat(String userId) async {
    state = state.copyWith(isLoading: true);
    try {
      // Add logic to create private chat
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final enhancedChatProvider = StateNotifierProvider<EnhancedChatNotifier, EnhancedChatState>((ref) {
  return EnhancedChatNotifier();
});
