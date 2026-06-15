import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message_model.dart';
import 'firebase_realtime_service.dart';
import 'message_database_service.dart';

/// Background Firebase sync service
/// Syncs Firebase messages to SQLite asynchronously
class FirebaseSyncIsolateService {
  static final FirebaseSyncIsolateService _instance = FirebaseSyncIsolateService._internal();
  factory FirebaseSyncIsolateService() => _instance;
  FirebaseSyncIsolateService._internal();

  final Map<String, StreamSubscription> _messageSubscriptions = {};
  final MessageDatabaseService _dbService = MessageDatabaseService();

  /// Start background sync for a chat
  /// This runs Firebase listener and saves to DB asynchronously
  Future<void> startSync({
    required String chatId,
    required String chatType,
    String? currentUserId,
    String? otherUserId,
    bool? isAttendanceGroup,
  }) async {
    final key = _getSyncKey(chatId, chatType, isAttendanceGroup);
    
    // Cancel existing subscription
    await stopSync(chatId, chatType, isAttendanceGroup);

    try {
      // Get Firebase message stream
      final messageStream = FirebaseRealtimeService.getMessagesStreamLimited(
        chatId,
        chatType,
        100, // Sync last 100 messages
        currentUserId: currentUserId,
        otherUserId: otherUserId ?? (chatType == 'group' ? '0' : chatId),
        attendanceGroup: isAttendanceGroup,
      );

      // Listen to Firebase and save to SQLite asynchronously
      _messageSubscriptions[key] = messageStream.listen(
        (messages) => _handleFirebaseMessages(messages, chatId, chatType),
        onError: (error) => debugPrint('❌ Firebase sync error for $key: $error'),
      );

      debugPrint('🔄 Started background Firebase sync for $key');
    } catch (e) {
      debugPrint('❌ Failed to start Firebase sync for $key: $e');
    }
  }

  /// Handle Firebase messages and save to SQLite asynchronously
  Future<void> _handleFirebaseMessages(
    List<Message> messages,
    String chatId,
    String chatType,
  ) async {
    if (messages.isEmpty) return;

    try {
      // Save to SQLite asynchronously (non-blocking)
      unawaited(_dbService.saveMessages(messages, chatId, chatType));
      debugPrint('✅ Synced ${messages.length} Firebase messages to SQLite for $chatId');
    } catch (e) {
      debugPrint('❌ Error saving Firebase messages to SQLite: $e');
    }
  }

  /// Stop background sync for a chat
  Future<void> stopSync(String chatId, String chatType, bool? isAttendanceGroup) async {
    final key = _getSyncKey(chatId, chatType, isAttendanceGroup);
    
    // Cancel subscription
    await _messageSubscriptions[key]?.cancel();
    _messageSubscriptions.remove(key);
    
    debugPrint('🛑 Stopped Firebase sync for $key');
  }

  /// Stop all syncs
  Future<void> stopAllSyncs() async {
    for (final subscription in _messageSubscriptions.values) {
      await subscription.cancel();
    }
    _messageSubscriptions.clear();
    
    debugPrint('🛑 Stopped all Firebase syncs');
  }

  /// Get unique sync key
  String _getSyncKey(String chatId, String chatType, bool? isAttendanceGroup) {
    final suffix = isAttendanceGroup == true ? 'true' : '';
    return '${chatType}_${chatId}$suffix';
  }

  /// Sync all messages from Firebase to SQLite (one-time full sync)
  Future<void> syncAllMessages({
    required String chatId,
    required String chatType,
    String? currentUserId,
    String? otherUserId,
    bool? isAttendanceGroup,
    int limit = 500,
  }) async {
    try {
      debugPrint('🔄 Starting full Firebase sync for $chatId...');
      
      final messages = await FirebaseRealtimeService.getMessagesStreamLimited(
        chatId,
        chatType,
        limit,
        currentUserId: currentUserId,
        otherUserId: otherUserId ?? (chatType == 'group' ? '0' : chatId),
        attendanceGroup: isAttendanceGroup,
      ).first.timeout(
        const Duration(seconds: 10),
        onTimeout: () => <Message>[],
      );

      if (messages.isNotEmpty) {
        await _dbService.saveMessages(messages, chatId, chatType);
        debugPrint('✅ Full sync completed: ${messages.length} messages saved to SQLite');
      }
    } catch (e) {
      debugPrint('❌ Full Firebase sync error: $e');
    }
  }

  /// Load messages from SQLite (instant, no loader needed)
  Future<List<Message>> loadMessagesFromDatabase(
    String chatId,
    String chatType, {
    int limit = 50,
    int offset = 0,
  }) async {
    return await _dbService.getMessages(chatId, chatType, limit: limit, offset: offset);
  }

  /// Load older messages for pagination
  Future<List<Message>> loadOlderMessages(
    String chatId,
    String chatType,
    DateTime beforeTimestamp, {
    int limit = 50,
  }) async {
    return await _dbService.getMessagesBefore(chatId, chatType, beforeTimestamp, limit: limit);
  }

  /// Check if messages exist in database
  Future<bool> hasMessages(String chatId, String chatType) async {
    final count = await _dbService.getMessageCount(chatId, chatType);
    return count > 0;
  }

  /// Clear messages from database
  Future<void> clearMessages(String chatId, String chatType) async {
    await _dbService.deleteMessages(chatId, chatType);
  }
}
