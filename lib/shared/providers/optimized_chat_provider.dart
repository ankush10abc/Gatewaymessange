import 'dart:async';

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
  String? _chatListSignature;
  StreamSubscription<List<ChatHiveModel>>? _chatSubscription;

  OptimizedChatNotifier(this._repository) : super(OptimizedChatState());

  String _buildChatListSignature(List<ChatHiveModel> chats) {
    return chats.map((chat) {
      final sortTime = chat.sortTime ?? chat.lastMessageTime ?? chat.updatedAt;
      return [
        chat.getUniqueKey(),
        chat.name,
        chat.profilePicture ?? '',
        chat.localImagePath ?? '',
        chat.lastMessage ?? '',
        sortTime.millisecondsSinceEpoch,
        chat.unreadCount,
        chat.isPinned ? 1 : 0,
        chat.lastReadAt?.millisecondsSinceEpoch ?? 0,
      ].join(':');
    }).join('|');
  }

  List<ChatHiveModel>? _dedupeChats(List<ChatHiveModel>? chats) {
    if (chats == null) return null;

    final nextSignature = _buildChatListSignature(chats);
    if (nextSignature == _chatListSignature) return null;

    _chatListSignature = nextSignature;
    return chats;
  }

  void _emit({
    List<ChatHiveModel>? chats,
    bool? isInitialLoading,
    bool? isSyncing,
    String? error,
    bool clearError = false,
    DateTime? lastSyncTime,
  }) {
    final nextChats = _dedupeChats(chats);
    final nextError = clearError ? null : (error ?? state.error);
    final nextState = OptimizedChatState(
      chats: nextChats ?? state.chats,
      isInitialLoading: isInitialLoading ?? state.isInitialLoading,
      isSyncing: isSyncing ?? state.isSyncing,
      error: nextError,
      lastSyncTime: lastSyncTime ?? state.lastSyncTime,
    );

    if (identical(nextState.chats, state.chats) &&
        nextState.isInitialLoading == state.isInitialLoading &&
        nextState.isSyncing == state.isSyncing &&
        nextState.error == state.error &&
        nextState.lastSyncTime == state.lastSyncTime) {
      return;
    }

    state = nextState;
  }

  Future<void> initialize({required String userId}) async {
    // If a different user was previously initialized, reset so new user gets a fresh load
    if (_isInitialized && _currentUserId != userId) {
      debugPrint(
          '🔄 OptimizedChatNotifier: user switch $_currentUserId → $userId, resetting');
      _isInitialized = false;
      _chatListSignature = null;
      unawaited(_chatSubscription?.cancel());
      _chatSubscription = null;
      state = OptimizedChatState();
    }

    if (_isInitialized) return;

    _currentUserId = userId;

    try {
      // Pass userId so HiveChatDataSource opens the correct per-user box
      await _repository.initialize(userId: userId);
      await _repository.initializeSync(userId);

      // Register direct-push callback: every Hive write in ChatListSyncService
      // (unread increment, last-message update, Firebase echo) immediately pushes
      // updated chats into state so HomeScreen rebuilds without waiting for
      // the async Hive watch stream microtask.
      _repository.setOnChatsUpdated((chats) {
        if (mounted) _emit(chats: chats);
      });

      // Watch for real-time updates from repository
      await _chatSubscription?.cancel();
      _chatSubscription = _repository.watchChats().listen((chats) {
        if (mounted) {
          _emit(
            chats: chats,
            lastSyncTime: _repository.getLastSyncTime(),
          );
        }
      });

      final cachedChats = _repository.getCachedChats();

      if (cachedChats.isEmpty) {
        _emit(isInitialLoading: true, clearError: true);
        debugPrint('📱 First launch - no cached data');
      } else {
        _emit(
          chats: cachedChats,
          isInitialLoading: false,
          lastSyncTime: _repository.getLastSyncTime(),
          clearError: true,
        );
        debugPrint('✅ Loaded ${cachedChats.length} chats from cache');
      }

      _isInitialized = true;
      await _syncInBackground();
    } catch (e) {
      debugPrint('❌ Initialize error: $e');

      final cachedChats = _repository.getCachedChats();
      _emit(
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
        _emit(isInitialLoading: false);
        return;
      }

      _repository.apiService.setAuthToken(token);

      _emit(isSyncing: true);

      final success = await _repository.syncChatsFromApi();

      if (success) {
        final updatedChats = _repository.getCachedChats();
        _emit(
          chats: updatedChats,
          isSyncing: false,
          isInitialLoading: false,
          lastSyncTime: _repository.getLastSyncTime(),
          clearError: true,
        );
        debugPrint('✅ Background sync completed: ${updatedChats.length} chats');
      } else {
        final cachedChats = _repository.getCachedChats();
        _emit(
          chats: cachedChats,
          isSyncing: false,
          isInitialLoading: false,
        );
        debugPrint(
            '⚠️ Background sync returned false, loaded ${cachedChats.length} from cache');
      }
    } on DioException catch (e) {
      debugPrint('📴 Network error (possibly offline): ${e.message}');
      final cachedChats = _repository.getCachedChats();
      _emit(
        chats: cachedChats,
        isSyncing: false,
        isInitialLoading: false,
      );
    } catch (e) {
      debugPrint('❌ Background sync error: $e');
      final cachedChats = _repository.getCachedChats();
      _emit(
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

      _emit(isSyncing: true);

      final success = await _repository.refreshChats();

      if (success) {
        final updatedChats = _repository.getCachedChats();
        _emit(
          chats: updatedChats,
          isSyncing: false,
          lastSyncTime: _repository.getLastSyncTime(),
          clearError: true,
        );
      } else {
        _emit(isSyncing: false);
      }
    } catch (e) {
      debugPrint('❌ Refresh error: $e');
      _emit(
        isSyncing: false,
        error: e.toString(),
      );
    }
  }

  /// Directly push a new chat list into state — used by FirebaseMessageListener
  /// for instant badge updates without going through the full async sync chain
  void forceUpdateChats(List<ChatHiveModel> chats) {
    _emit(chats: chats);
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
    _emit(chats: updatedChats);
    debugPrint(
        '⬆️ Chat list updated - $chatType/$chatId | unread badge refreshed instantly');
  }

  Future<void> createChat(ChatHiveModel chat) async {
    await _repository.createOrUpdateChat(chat);

    final updatedChats = _repository.getCachedChats();
    _emit(chats: updatedChats);
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

  Future<void> markAsRead(
      String chatId, String chatType, bool attendance_group) async {
    await _repository.markChatAsRead(chatId, chatType, attendance_group);
    // Refresh state so home screen badge updates immediately
    final updatedChats = _repository.getCachedChats();
    _emit(chats: updatedChats);
    debugPrint('✅ markAsRead: cleared badge for $chatType/$chatId');
  }

  int getTotalUnreadCount() {
    return _repository.getTotalUnreadCount();
  }

  void clearError() {
    _emit(clearError: true);
  }

  @override
  void dispose() {
    unawaited(_chatSubscription?.cancel());
    super.dispose();
  }
}

final optimizedChatProvider =
    StateNotifierProvider<OptimizedChatNotifier, OptimizedChatState>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return OptimizedChatNotifier(repository);
});
