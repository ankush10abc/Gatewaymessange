import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';

/// High-performance cache manager for instant data access
class CacheManager {
  static Box? _chatBox;
  static Box? _messageBox;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      _chatBox = await Hive.openBox('chat_cache');
      _messageBox = await Hive.openBox('message_cache');
      _initialized = true;
      debugPrint('✅ Cache initialized');
    } catch (e) {
      debugPrint('CacheManager init error: $e');
    }
  }

  // Chat List Caching - instant load
  static Future<void> saveChatList(List<Chat> chats) async {
    if (!_initialized || _chatBox == null) return;
    try {
      final data = chats.map((c) => c.toJson()).toList();
      await _chatBox!.put('chats', data);
      await _chatBox!.put('chats_timestamp', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Save chat list error: $e');
    }
  }

  static List<Chat> getCachedChatList() {
    if (!_initialized || _chatBox == null) return [];
    try {
      final cached = _chatBox!.get('chats');
      if (cached == null) return [];
      return (cached as List).map((e) => Chat.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      debugPrint('Get cached chats error: $e');
      return [];
    }
  }

  // Message Caching - instant load per chat
  static Future<void> saveMessages(String chatId, List<Message> messages) async {
    if (!_initialized || _messageBox == null) return;
    try {
      final key = 'messages_$chatId';
      final data = messages.take(100).map((m) => m.toJson()).toList();
      await _messageBox!.put(key, data);
      await _messageBox!.put('${key}_timestamp', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Save messages error: $e');
    }
  }

  static List<Message> getCachedMessages(String chatId) {
    if (!_initialized || _messageBox == null) return [];
    try {
      final cached = _messageBox!.get('messages_$chatId');
      if (cached == null) return [];
      return (cached as List).map((e) => Message.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      debugPrint('Get cached messages error: $e');
      return [];
    }
  }

  // Clear old cache (>7 days)
  static Future<void> clearOldCache() async {
    if (!_initialized || _messageBox == null) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sevenDays = 7 * 24 * 60 * 60 * 1000;
      
      for (var key in _messageBox!.keys) {
        if (key.toString().endsWith('_timestamp')) {
          final timestamp = _messageBox!.get(key) as int?;
          if (timestamp != null && (now - timestamp) > sevenDays) {
            final dataKey = key.toString().replaceAll('_timestamp', '');
            await _messageBox!.delete(dataKey);
            await _messageBox!.delete(key);
          }
        }
      }
    } catch (e) {
      debugPrint('Clear old cache error: $e');
    }
  }
}
