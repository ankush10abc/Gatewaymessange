import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message_model.dart';
import 'message_database_service.dart';

/// Background Firebase sync service.
///
/// BANDWIDTH NOTE: This service intentionally does NOT open its own Firebase
/// listener. MessageSyncService.setupFirebaseListener() already holds the
/// single authoritative onValue listener per chat and calls
/// _cacheMessagesRealtimeBackground() to persist every batch to SQLite.
/// Opening a second listener here would double every Firebase message download.
///
/// All methods that previously started a duplicate listener are now no-ops or
/// delegate to the SQLite layer directly.
class FirebaseSyncIsolateService {
  static final FirebaseSyncIsolateService _instance = FirebaseSyncIsolateService._internal();
  factory FirebaseSyncIsolateService() => _instance;
  FirebaseSyncIsolateService._internal();

  final MessageDatabaseService _dbService = MessageDatabaseService();

  /// No-op: MessageSyncService already holds the single Firebase listener.
  /// Calling this would open a duplicate onValue stream and double bandwidth.
  Future<void> startSync({
    required String chatId,
    required String chatType,
    String? currentUserId,
    String? otherUserId,
    bool? isAttendanceGroup,
  }) async {
    // Intentional no-op — see class doc above.
    debugPrint('⏭️ FirebaseSyncIsolateService.startSync skipped — MessageSyncService listener is active');
  }

  /// No-op: nothing to stop since startSync is a no-op.
  Future<void> stopSync(String chatId, String chatType, bool? isAttendanceGroup) async {}

  /// No-op.
  Future<void> stopAllSyncs() async {}

  String _getSyncKey(String chatId, String chatType, bool? isAttendanceGroup) {
    final suffix = isAttendanceGroup == true ? 'true' : '';
    return '${chatType}_${chatId}$suffix';
  }

  /// One-time SQLite read — no Firebase download.
  /// Callers that need a full Firebase sync should use
  /// MessageSyncService.syncRecentFirebaseMessages() instead.
  Future<void> syncAllMessages({
    required String chatId,
    required String chatType,
    String? currentUserId,
    String? otherUserId,
    bool? isAttendanceGroup,
    int limit = 500,
  }) async {
    // No-op: MessageSyncService handles all Firebase → SQLite syncing.
    debugPrint('⏭️ FirebaseSyncIsolateService.syncAllMessages skipped — use MessageSyncService');
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
