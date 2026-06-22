import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/models/chat_hive_model.dart';
import '../../core/data/hive_chat_data_source.dart';
import '../../core/repositories/chat_repository.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/storage/storage_service.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final dio = Dio();
  final apiService = ApiService(dio);
  final localDataSource = HiveChatDataSource();
  
  return ChatRepository(localDataSource, apiService);
});

class OptimizedChatState {
  final List<ChatHiveModel> chats;
  final bool isInitialLoading;
  final bool isSyncing;
  final String? error;
  final DateTime? lastSyncTime;

  OptimizedChatState({
    this.chats = const [],
    this.isInitialLoading = false,
    this.isSyncing = false,
    this.error,
    this.lastSyncTime,
  });

  OptimizedChatState copyWith({
    List<ChatHiveModel>? chats,
    bool? isInitialLoading,
    bool? isSyncing,
    String? error,
    DateTime? lastSyncTime,
  }) {
    return OptimizedChatState(
      chats: chats ?? this.chats,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      error: error,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

class OptimizedChatNotifier extends StateNotifier<OptimizedChatState> {
  final ChatRepository _repository;
  final StorageService _storage = StorageService();
  bool _isInitialized = false;
  String? _currentUserId;

  OptimizedChatNotifier(this._repository) : super(OptimizedChatState());

  Future<void> initialize({required String userId}) async {
    // If a different user was previously initialized, reset so new user gets a fresh load
    if (_isInitialized && _currentUserId != userId) {
      debugPrint('🔄 OptimizedChatNotifier: user switch $_currentUserId → $userId, resetting');
      _isInitialized = false;
      state = OptimizedChatState();
    }

    if (_isInitialized) return;

    _currentUserId = userId;

    try {
      // Pass userId so HiveChatDataSource opens the correct per-user box
      await _repository.initialize(userId: userId);
      await _repository.initializeSync(userId);

      // Watch for real-time updates from repository
      _repository.watchChats().listen((chats) {
        if (mounted) {
          state = state.copyWith(
            chats: chats,
            lastSyncTime: _repository.getLastSyncTime(),
          );
        }
      });

      final cachedChats = _repository.getCachedChats();
      
      if (cachedChats.isEmpty) {
        state = state.copyWith(isInitialLoading: true);
        debugPrint('📱 First launch - no cached data');
      } else {
        state = state.copyWith(
          chats: cachedChats,
          isInitialLoading: false,
          lastSyncTime: _repository.getLastSyncTime(),
        );
        debugPrint('✅ Loaded ${cachedChats.length} chats from cache');
      }

      _isInitialized = true;
      await _syncInBackground();
    } catch (e) {
      debugPrint('❌ Initialize error: $e');
      
      final cachedChats = _repository.getCachedChats();
      state = state.copyWith(
        chats: cachedChats,
        error: cachedChats.isEmpty ? e.toString() : null,
        isInitialLoading: false,
      );
    }
  }

  Future<void> _syncInBackground() async {
    try {
      final token = await _storage.getToken();
      if (token == null) {
        debugPrint('⚠️ No token available, skipping sync');
        state = state.copyWith(isInitialLoading: false);
        return;
      }

      _repository.apiService.setAuthToken(token);

      state = state.copyWith(isSyncing: true);

      final success = await _repository.syncChatsFromApi();

      if (success) {
        final updatedChats = _repository.getCachedChats();
        state = state.copyWith(
          chats: updatedChats,
          isSyncing: false,
          isInitialLoading: false,
          lastSyncTime: _repository.getLastSyncTime(),
        );
        debugPrint('✅ Background sync completed: ${updatedChats.length} chats');
      } else {
        final cachedChats = _repository.getCachedChats();
        state = state.copyWith(
          chats: cachedChats,
          isSyncing: false,
          isInitialLoading: false,
        );
        debugPrint('⚠️ Background sync returned false, loaded ${cachedChats.length} from cache');
      }
    } on DioException catch (e) {
      debugPrint('📴 Network error (possibly offline): ${e.message}');
      final cachedChats = _repository.getCachedChats();
      state = state.copyWith(
        chats: cachedChats,
        isSyncing: false,
        isInitialLoading: false,
      );
    } catch (e) {
      debugPrint('❌ Background sync error: $e');
      final cachedChats = _repository.getCachedChats();
      state = state.copyWith(
        chats: cachedChats,
        isSyncing: false,
        isInitialLoading: false,
      );
    }
  }

  Future<void> refresh() async {
    try {
      final token = await _storage.getToken();
      if (token == null) {
        debugPrint('⚠️ No token available, cannot refresh');
        return;
      }

      _repository.apiService.setAuthToken(token);

      state = state.copyWith(isSyncing: true);

      final success = await _repository.refreshChats();

      if (success) {
        final updatedChats = _repository.getCachedChats();
        state = state.copyWith(
          chats: updatedChats,
          isSyncing: false,
          lastSyncTime: _repository.getLastSyncTime(),
        );
      } else {
        state = state.copyWith(isSyncing: false);
      }
    } catch (e) {
      debugPrint('❌ Refresh error: $e');
      state = state.copyWith(
        isSyncing: false,
        error: e.toString(),
      );
    }
  }

  /// Directly push a new chat list into state — used by FirebaseMessageListener
  /// for instant badge updates without going through the full async sync chain
  void forceUpdateChats(List<ChatHiveModel> chats) {
    state = state.copyWith(chats: chats);
  }

  Future<void> updateChatWithMessage({
    required String chatId,
    required String chatType,
    required String lastMessage,
    required bool attendanceGroup,
    required DateTime lastMessageTime,
    String? senderId,
    String? senderName,
    bool isIncoming = false,
  }) async {
    await _repository.updateChatWithNewMessage(
      chatId: chatId,
      chatType: chatType,
      lastMessage: lastMessage,
      attendanceGroup: attendanceGroup,
      lastMessageTime: lastMessageTime,
      isIncoming: isIncoming,
    );

    // Immediately push updated Hive data into state so UI rebuilds
    // without waiting for the Hive watch stream event
    final updatedChats = _repository.getCachedChats();
    state = state.copyWith(chats: updatedChats);
    debugPrint('⬆️ Chat list updated - $chatType/$chatId | unread badge refreshed instantly');
  }

  Future<void> createChat(ChatHiveModel chat) async {
    await _repository.createOrUpdateChat(chat);
    
    final updatedChats = _repository.getCachedChats();
    state = state.copyWith(chats: updatedChats);
    debugPrint('➕ New chat created: ${chat.name}');
  }

  Future<void> togglePin(
    String chatId,
    String chatType,
    bool isPinned, {
    bool attendanceGroup = false,
  }) async {
    await _repository.togglePinChat(
      chatId,
      chatType,
      isPinned,
      attendanceGroup: attendanceGroup,
    );
  }

  Future<void> markAsRead(String chatId, String chatType, bool attendance_group) async {
    await _repository.markChatAsRead(chatId, chatType, attendance_group);
    // Refresh state so home screen badge updates immediately
    final updatedChats = _repository.getCachedChats();
    state = state.copyWith(chats: updatedChats);
    debugPrint('✅ markAsRead: cleared badge for $chatType/$chatId');
  }

  int getTotalUnreadCount() {
    return _repository.getTotalUnreadCount();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final optimizedChatProvider = StateNotifierProvider<OptimizedChatNotifier, OptimizedChatState>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return OptimizedChatNotifier(repository);
});
