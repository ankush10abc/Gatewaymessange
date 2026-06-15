import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Service to cache and retrieve chat metadata (permissions, user info, etc.)
/// Eliminates API calls for metadata on subsequent chat opens
class ChatMetadataService {
  static final ChatMetadataService _instance = ChatMetadataService._internal();
  factory ChatMetadataService() => _instance;
  ChatMetadataService._internal();

  static const String _boxName = 'chat_metadata';

  Future<Box<Map>> _getBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<Map>(_boxName);
    }
    return await Hive.openBox<Map>(_boxName);
  }

  String _getKey(String chatId, String chatType) {
    return '${chatType}_$chatId';
  }

  /// Save chat metadata to cache
  Future<void> saveMetadata({
    required String chatId,
    required String chatType,
    required Map<String, dynamic> userData,
  }) async {
    try {
      final box = await _getBox();
      final key = _getKey(chatId, chatType);
      
      final metadata = {
        'id': userData['id'],
        'name': userData['name'],
        'profile_picture': userData['profile_picture'],
        'description': userData['description'],
        'is_locked': userData['is_locked'],
        'message_permission': userData['message_permission'],
        'allow_attachments': userData['allow_attachments'],
        'attendance_group': userData['attendance_group'],
        'member_count': userData['member_count'],
        'member_list': userData['member_list'],
        'cached_at': DateTime.now().toIso8601String(),
      };
      
      await box.put(key, metadata);
      debugPrint('💾 Saved metadata for $key');
    } catch (e) {
      debugPrint('❌ Failed to save metadata: $e');
    }
  }

  /// Get cached metadata
  Future<Map<String, dynamic>?> getMetadata({
    required String chatId,
    required String chatType,
  }) async {
    try {
      final box = await _getBox();
      final key = _getKey(chatId, chatType);
      final data = box.get(key);
      
      if (data != null) {
        debugPrint('✅ Loaded metadata from cache for $key');
        return Map<String, dynamic>.from(data);
      }
      
      debugPrint('⚠️ No cached metadata for $key');
      return null;
    } catch (e) {
      debugPrint('❌ Failed to load metadata: $e');
      return null;
    }
  }

  /// Check if metadata exists
  Future<bool> hasMetadata({
    required String chatId,
    required String chatType,
  }) async {
    try {
      final box = await _getBox();
      final key = _getKey(chatId, chatType);
      return box.containsKey(key);
    } catch (e) {
      return false;
    }
  }

  /// Clear metadata for a chat
  Future<void> clearMetadata({
    required String chatId,
    required String chatType,
  }) async {
    try {
      final box = await _getBox();
      final key = _getKey(chatId, chatType);
      await box.delete(key);
      debugPrint('🗑️ Cleared metadata for $key');
    } catch (e) {
      debugPrint('❌ Failed to clear metadata: $e');
    }
  }

  /// Clear all metadata
  Future<void> clearAll() async {
    try {
      final box = await _getBox();
      await box.clear();
      debugPrint('🗑️ Cleared all chat metadata');
    } catch (e) {
      debugPrint('❌ Failed to clear all metadata: $e');
    }
  }
}
