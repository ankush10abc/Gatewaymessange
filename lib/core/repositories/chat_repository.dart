import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/chat_hive_model.dart';
import '../data/hive_chat_data_source.dart';
import '../services/api_service_simple.dart';
import '../services/image_cache_service.dart';
import '../services/chat_list_sync_service.dart';

enum SyncStatus { idle, syncing, success, error }

class ChatRepository {
  final HiveChatDataSource _localDataSource;
  final ApiService apiService;
  final ImageCacheService _imageCacheService = ImageCacheService();
  final ChatListSyncService _syncService = ChatListSyncService();
  
  SyncStatus _syncStatus = SyncStatus.idle;
  bool _isInitialFetch = false;
  String? _currentUserId;

  ChatRepository(this._localDataSource, this.apiService);

  SyncStatus get syncStatus => _syncStatus;

  Future<void> initialize({String? userId}) async {
    await _localDataSource.initialize(userId: userId);
    await _imageCacheService.initialize();
    _isInitialFetch = _localDataSource.isEmpty();
    debugPrint('📚 Repository initialized. Initial fetch: $_isInitialFetch');
  }

  Future<void> initializeSync(String userId) async {
    _currentUserId = userId;
    await _syncService.initialize(userId);
    debugPrint('🔄 Sync service initialized for user: $userId');
  }

  /// Register the provider callback so Hive-write paths immediately push state
  void setOnChatsUpdated(void Function(List<ChatHiveModel>) callback) {
    _syncService.setOnChatsUpdated(callback);
  }

  List<ChatHiveModel> getCachedChats() {
    return _syncService.getSortedChatList();
  }

  Stream<List<ChatHiveModel>> watchChats() {
    return _syncService.watchChatList();
  }

  bool isCacheEmpty() {
    return _localDataSource.isEmpty();
  }

  DateTime? _lastSyncTime;
  static const _syncCooldown = Duration(seconds: 10);

  Future<bool> syncChatsFromApi({bool force = false}) async {
    if (_syncStatus == SyncStatus.syncing && !force) {
      debugPrint('⚠️ Sync already in progress, skipping...');
      return false;
    }

    // Throttle: skip if last sync was within cooldown window (unless forced)
    if (!force && _lastSyncTime != null &&
        DateTime.now().difference(_lastSyncTime!) < _syncCooldown) {
      debugPrint('⏭️ syncChatsFromApi throttled — last sync ${DateTime.now().difference(_lastSyncTime!).inSeconds}s ago');
      return false;
    }

    try {
      _syncStatus = SyncStatus.syncing;
      debugPrint('🔄 Starting chat sync from API...');

      final response = await apiService.getChatList();
      
      if (response.isEmpty) {
        debugPrint('ℹ️ No chats received from API');
        _syncStatus = SyncStatus.success;
        await _localDataSource.setLastSyncTime(DateTime.now());
        return true;
      }

      final apiChats = response.map((item) => item as Map<String, dynamic>).toList();
      debugPrint('📥 Received ${apiChats.length} chats from API');

      // Use sync service to store in Firebase + Hive
      await _syncService.syncFromApi(apiChats);
      
      await _localDataSource.setLastSyncTime(DateTime.now());
      _lastSyncTime = DateTime.now();
      _syncStatus = SyncStatus.success;
      _isInitialFetch = false;
      
      // Get updated chat list from Hive
      final updatedChats = _syncService.getSortedChatList();
      debugPrint('✅ Sync complete: API → Firebase + Hive (${updatedChats.length} chats available)');
      
      return true;
    } catch (e) {
      debugPrint('\n========================================');
      debugPrint('❌ CHAT SYNC FAILED');
      debugPrint('========================================');
      if (e is DioException) {
        debugPrint('URL: ${e.requestOptions.uri}');
        debugPrint('Method: ${e.requestOptions.method}');
        debugPrint('Status Code: ${e.response?.statusCode}');
        debugPrint('Headers: ${e.requestOptions.headers}');
        debugPrint('Response: ${e.response?.data}');
        debugPrint('Error Type: ${e.type}');
      } else {
        debugPrint('Error: $e');
      }
      debugPrint('========================================\n');
      _syncStatus = SyncStatus.error;
      return false;
    }
  }

  Future<bool> refreshChats() async {
    debugPrint('🔃 Manual refresh triggered');
    return await syncChatsFromApi(force: true);
  }

  ChatHiveModel? getChatById(String id, String type, bool attendanceGroup) {
    return _localDataSource.getChatById(id, type,attendanceGroup);
  }

  Future<void> updateChatWithNewMessage({
    required String chatId,
    required String chatType,
    required bool attendanceGroup,
    required String lastMessage,
    required DateTime lastMessageTime,
    bool isIncoming = false,
  }) async {
    // Use sync service to update Firebase + Hive
    await _syncService.updateChatOnMessage(
      chatId: chatId,
      chatType: chatType,
      attendanceGroup: attendanceGroup,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      incrementUnread: isIncoming,
    );
    debugPrint('⬆️ Chat $chatType/$chatId updated and moved to top');
  }

  Future<void> createOrUpdateChat(ChatHiveModel chat) async {
    await _localDataSource.upsertChat(chat);
  }

  Future<void> markChatAsRead(String chatId, String chatType, bool attendance_group) async {
    await _syncService.markAsRead(chatId, chatType, attendance_group ?? false);
  }

  Future<void> togglePinChat(
    String chatId,
    String chatType,
    bool isPinned, {
    bool attendanceGroup = false,
  }) async {
    await _syncService.togglePin(
      chatId,
      chatType,
      isPinned,
      attendanceGroup: attendanceGroup,
    );
  }

  int getTotalUnreadCount() {
    return _localDataSource.getTotalUnreadCount();
  }

  DateTime? getLastSyncTime() {
    return _localDataSource.getLastSyncTime();
  }

  Future<void> clearAllData() async {
    await _localDataSource.clearAllChats();
    _isInitialFetch = true;
  }

  bool needsInitialFetch() {
    return _isInitialFetch;
  }
}
