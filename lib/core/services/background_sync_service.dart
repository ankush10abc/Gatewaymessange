import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'api_service_simple.dart';
import 'cache_manager.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';

/// Background sync service - syncs data silently without blocking UI
class BackgroundSyncService {
  final ApiService _apiService;
  Timer? _syncTimer;
  StreamSubscription<ConnectivityResult>? _connectivitySub;
  bool _isSyncing = false;
  
  // Sync every 30 seconds when online
  static const Duration syncInterval = Duration(seconds: 30);

  BackgroundSyncService(this._apiService);

  /// Start background sync
  void start() {
    // Immediate sync on start
    _syncAll();
    
    // Periodic sync
    _syncTimer = Timer.periodic(syncInterval, (_) => _syncAll());
    
    // Sync on connectivity change
    _connectivitySub = Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      if (result != ConnectivityResult.none) {
        debugPrint('🌐 Connection restored, syncing...');
        _syncAll();
      }
    });
  }

  /// Stop background sync
  void stop() {
    _syncTimer?.cancel();
    _connectivitySub?.cancel();
  }

  /// Sync all data silently
  Future<void> _syncAll() async {
    if (_isSyncing) return;
    
    _isSyncing = true;
    try {
      await _syncChatList();
    } catch (e) {
      debugPrint('Background sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync chat list in background
  Future<void> _syncChatList() async {
    try {
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
      
      // Save to cache silently
      await CacheManager.saveChatList(chats);
      debugPrint('✅ Background sync: ${chats.length} chats cached');
    } catch (e) {
      debugPrint('❌ Background sync failed: $e');
    }
  }

  /// Sync messages for a specific chat
  Future<void> syncChatMessages(String chatId, String chatType) async {
    try {
      List<Message> messages = [];
      
      final int id = int.parse(chatId);
      if (chatType == 'group') {
        final response = await _apiService.getGroupMessages(id, 1, 50);
        messages = response.data;
      } else {
        final response = await _apiService.getConversation(id, 1, 50);
        messages = response.data;
      }
      
      // Cache messages
      await CacheManager.saveMessages(chatId, messages);
      debugPrint('✅ Cached ${messages.length} messages for chat $chatId');
    } catch (e) {
      debugPrint('❌ Message sync failed for $chatId: $e');
    }
  }
}
