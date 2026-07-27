import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/message_model.dart';
import 'dart:convert';

/// SQLite database service for message storage
/// Handles Firebase messages sync in background isolate
class MessageDatabaseService {
  static final MessageDatabaseService _instance = MessageDatabaseService._internal();
  factory MessageDatabaseService() => _instance;
  MessageDatabaseService._internal();

  Database? _database;
  static const String _dbName = 'messages.db';
  static const int _dbVersion = 4;
  static const String _messagesTable = 'messages';
  bool _isInitialized = false;

  // Initialize database (call this once at app startup)
  static Future<void> initialize() async {
    try {
      final instance = MessageDatabaseService();
      await instance.database;
      debugPrint('✅ SQLite database initialized');
    } catch (e) {
      debugPrint('❌ SQLite initialization error: $e');
    }
  }

  // Get database instance
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    if (!_isInitialized) {
      _database = await _initDatabase();
      _isInitialized = true;
    }
    return _database!;
  }

  // Initialize database
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // Create tables
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_messagesTable (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        chat_type TEXT NOT NULL,
        sender_id TEXT,
        sender_name TEXT,
        message TEXT,
        type TEXT,
        file_path TEXT,
        file_name TEXT,
        file_url TEXT,
        timestamp INTEGER NOT NULL,
        status TEXT,
        is_read INTEGER DEFAULT 0,
        reply_to_id TEXT,
        reply_to_message_json TEXT,
        firebase_id TEXT,
        msg_id TEXT,
        profile_picture_url TEXT,
        metadata TEXT,
        created_at INTEGER,
        updated_at INTEGER,
        UNIQUE(chat_id, chat_type, firebase_id)
      )
    ''');

    // Create indexes for faster queries
    await db.execute('''
      CREATE INDEX idx_chat_timestamp ON $_messagesTable(chat_id, chat_type, timestamp DESC)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_firebase_id ON $_messagesTable(firebase_id)
    ''');

    // Index for getReadMessageIds() and markMessagesAsRead() fast-path:
    // avoids full table scan when filtering by is_read flag.
    await db.execute('''
      CREATE INDEX idx_chat_read ON $_messagesTable(chat_id, chat_type, is_read)
    ''');

    debugPrint('\u{1F4BE} Database created successfully');
  }

  // Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: Add reply_to_message_json column
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE $_messagesTable ADD COLUMN reply_to_message_json TEXT');
      debugPrint('\u{1F4BE} DB v$oldVersion\u2192v2: Added reply_to_message_json');
    }
    // v2 → v3: Add composite index for read-status fast-path queries.
    if (oldVersion < 3) {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_chat_read ON $_messagesTable(chat_id, chat_type, is_read)');
      debugPrint('\u{1F4BE} DB v2\u2192v3: Added idx_chat_read index');
    }
    // v3 → v4: Add index on msg_id for fast duplicate-row cleanup in _upsertMessage.
    if (oldVersion < 4) {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_msg_id ON $_messagesTable(chat_id, chat_type, msg_id)');
      // Clean up existing duplicate rows: keep the firebaseId-keyed row,
      // delete the stale msgId-keyed row for each logical message.
      await db.execute('''
        DELETE FROM $_messagesTable
        WHERE rowid NOT IN (
          SELECT MIN(rowid) FROM $_messagesTable
          GROUP BY chat_id, chat_type,
            COALESCE(NULLIF(firebase_id,''), NULLIF(msg_id,''), id)
        )
      ''');
      debugPrint('\u{1F4BE} DB v3\u2192v4: Added idx_msg_id, cleaned duplicate rows');
    }
  }

  // Save single message to database
  Future<void> saveMessage(Message message, String chatId, String chatType) async {
    try {
      final db = await database;
      await _upsertMessage(db, message, chatId, chatType);
      debugPrint('💾 Saved message ${message.firebaseId ?? message.id} to SQLite');
    } catch (e) {
      debugPrint('❌ Error saving message to SQLite: $e');
      if (e.toString().contains('database') || e.toString().contains('closed')) {
        _isInitialized = false;
        _database = null;
      }
    }
  }

  // Save multiple messages in batch
  Future<void> saveMessages(List<Message> messages, String chatId, String chatType) async {
    if (messages.isEmpty) return;
    try {
      final db = await database;
      await db.transaction((txn) async {
        for (final message in messages) {
          await _upsertMessage(txn, message, chatId, chatType);
        }
      });
      debugPrint('💾 Saved ${messages.length} messages to SQLite for chat $chatId');
    } catch (e) {
      debugPrint('❌ Error batch saving messages to SQLite: $e');
      if (e.toString().contains('database') || e.toString().contains('closed')) {
        _isInitialized = false;
        _database = null;
      }
    }
  }

  /// Upsert a single message, removing stale duplicate rows keyed by msgId
  /// before inserting the canonical firebaseId-keyed row.
  ///
  /// Problem: a message arrives first from the API with id=msgId (e.g. "501"),
  /// then again from Firebase with id=firebaseId (e.g. "-NxABC"). Both rows
  /// share msg_id="501" but have different PRIMARY KEY values, so SQLite stores
  /// two rows → duplicate messages in the UI.
  ///
  /// Fix: when the incoming message has a firebaseId, delete any existing row
  /// that shares the same msg_id but has a different id (the stale msgId row).
  Future<void> _upsertMessage(
      DatabaseExecutor db, Message message, String chatId, String chatType) async {
    final data = _messageToMap(message, chatId, chatType);
    final newId = data['id'] as String;
    final msgId = message.msgId?.trim();
    final firebaseId = message.firebaseId?.trim();

    // When this message has a firebaseId (canonical key), delete ALL stale rows
    // that represent the same logical message but are keyed differently.
    //
    // Group API flow:  API saves id="501", msgId="",   firebaseId=null
    // Firebase flow:  Firebase saves id="-NxABC", msgId="501", firebaseId="-NxABC"
    // → two rows exist; the API row must be deleted when Firebase row arrives.
    //
    // Private chat flow: same pattern but msgId is populated on the API row too.
    if (firebaseId != null && firebaseId.isNotEmpty) {
      // Case 1: stale row whose msg_id matches our msgId (private chat pattern)
      if (msgId != null && msgId.isNotEmpty && msgId != '0' && msgId != newId) {
        await db.delete(
          _messagesTable,
          where: 'chat_id = ? AND chat_type = ? AND msg_id = ? AND id != ?',
          whereArgs: [chatId, chatType, msgId, newId],
        );
        // Case 2: stale row whose PRIMARY KEY (id) equals our msgId
        // (group API saves id=msgId directly as primary key)
        await db.delete(
          _messagesTable,
          where: 'chat_id = ? AND chat_type = ? AND id = ? AND id != ?',
          whereArgs: [chatId, chatType, msgId, newId],
        );
      }

      // Case 3 (group-specific): API row was saved with id = resolvedId where
      // resolvedId = msgId from the API response "id" field (not "msgId" field).
      // The Firebase message carries msgId = that same resolvedId.
      // We must also delete any row whose id equals our msgId even when
      // message.msgId was empty on the API side.
      // Strategy: delete any row for this chat whose id is a pure numeric string
      // that matches our msgId, and whose firebase_id is NULL (API-only row).
      if (msgId != null && msgId.isNotEmpty && msgId != '0' && msgId != newId) {
        await db.delete(
          _messagesTable,
          where:
              'chat_id = ? AND chat_type = ? AND id = ? AND (firebase_id IS NULL OR firebase_id = \'\') AND id != ?',
          whereArgs: [chatId, chatType, msgId, newId],
        );
      }

      // Case 4: delete any row sharing the same firebase_id but different primary key
      // (shouldn't happen normally but guards against re-keying edge cases)
      await db.delete(
        _messagesTable,
        where:
            'chat_id = ? AND chat_type = ? AND firebase_id = ? AND id != ?',
        whereArgs: [chatId, chatType, firebaseId, newId],
      );
    }

    await db.insert(
      _messagesTable,
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get messages for a chat (with pagination)
  Future<List<Message>> getMessages(
    String chatId,
    String chatType, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final db = await database;
      // Use a raw query that picks the best row per logical message.
      // Partition key: prefer firebase_id grouping, fall back to msg_id, then id.
      // For group messages the API row has msg_id='' but id='501';
      // the Firebase row has firebase_id='-NxABC' and msg_id='501'.
      // COALESCE(NULLIF(firebase_id,''), NULLIF(msg_id,''), id) maps both to '501'
      // only when firebase_id is present on the Firebase row — so we also need
      // to match the API row's id against the Firebase row's msg_id.
      // The simplest correct partition: use msg_id when non-empty, else id.
      // The firebase-keyed row wins (ORDER BY firebase_id presence DESC).
      final results = await db.rawQuery('''
        SELECT * FROM (
          SELECT *,
            ROW_NUMBER() OVER (
              PARTITION BY
                CASE
                  WHEN firebase_id IS NOT NULL AND firebase_id != '' THEN firebase_id
                  WHEN msg_id IS NOT NULL AND msg_id != '' AND msg_id != '0' THEN msg_id
                  ELSE id
                END
              ORDER BY
                CASE WHEN firebase_id IS NOT NULL AND firebase_id != '' THEN 0 ELSE 1 END,
                updated_at DESC
            ) AS rn
          FROM $_messagesTable
          WHERE chat_id = ? AND chat_type = ?
        ) ranked
        WHERE rn = 1
        ORDER BY timestamp DESC
        LIMIT ? OFFSET ?
      ''', [chatId, chatType, limit, offset]);

      return results.map(_mapToMessage).toList();
    } catch (e) {
      // ROW_NUMBER() requires SQLite 3.25+ (Android API 30+). Fall back to
      // simple query + in-memory dedup for older devices.
      debugPrint('⚠️ ROW_NUMBER fallback for getMessages: $e');
      return _getMessagesWithInMemoryDedup(chatId, chatType, limit: limit, offset: offset);
    }
  }

  /// Fallback for SQLite < 3.25 (Android < API 30): load and dedup in memory.
  Future<List<Message>> _getMessagesWithInMemoryDedup(
    String chatId,
    String chatType, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final db = await database;
      // Fetch more rows than needed to account for duplicates being removed
      final results = await db.query(
        _messagesTable,
        where: 'chat_id = ? AND chat_type = ?',
        whereArgs: [chatId, chatType],
        orderBy: 'CASE WHEN firebase_id IS NOT NULL AND firebase_id != \'\' THEN 0 ELSE 1 END, timestamp DESC',
        limit: limit * 3,
        offset: offset,
      );
      // Single seenIds set tracks firebase_id + msg_id + row id together.
      // Group API rows have id='501', msg_id=''; Firebase rows have
      // firebase_id='-NxABC', msg_id='501'. Registering the row id into seenIds
      // means the Firebase row's msg_id='501' matches the API row's id='501'.
      final seenIds = <String>{};
      final deduped = <Message>[];
      for (final map in results) {
        final fbId = map['firebase_id']?.toString().trim() ?? '';
        final mId = map['msg_id']?.toString().trim() ?? '';
        final rowId = map['id']?.toString().trim() ?? '';
        if (fbId.isNotEmpty && seenIds.contains(fbId)) continue;
        if (mId.isNotEmpty && mId != '0' && seenIds.contains(mId)) continue;
        if (rowId.isNotEmpty && seenIds.contains(rowId)) continue;
        if (fbId.isNotEmpty) seenIds.add(fbId);
        if (mId.isNotEmpty && mId != '0') seenIds.add(mId);
        if (rowId.isNotEmpty) seenIds.add(rowId);
        deduped.add(_mapToMessage(map));
        if (deduped.length >= limit) break;
      }
      return deduped;
    } catch (e) {
      debugPrint('❌ Error loading messages from SQLite: $e');
      return [];
    }
  }

  // Get messages after a specific timestamp
  Future<List<Message>> getMessagesAfter(
    String chatId,
    String chatType,
    DateTime afterTimestamp,
  ) async {
    try {
      final db = await database;
      final results = await db.query(
        _messagesTable,
        where: 'chat_id = ? AND chat_type = ? AND timestamp > ?',
        whereArgs: [chatId, chatType, afterTimestamp.millisecondsSinceEpoch],
        orderBy: 'timestamp DESC',
      );
      
      return results.map((map) => _mapToMessage(map)).toList();
    } catch (e) {
      debugPrint('❌ Error loading messages after timestamp: $e');
      return [];
    }
  }

  // Get messages before a specific timestamp (for pagination)
  Future<List<Message>> getMessagesBefore(
    String chatId,
    String chatType,
    DateTime beforeTimestamp, {
    int limit = 50,
  }) async {
    try {
      final db = await database;
      final results = await db.query(
        _messagesTable,
        where: 'chat_id = ? AND chat_type = ? AND timestamp < ?',
        whereArgs: [chatId, chatType, beforeTimestamp.millisecondsSinceEpoch],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
      
      return results.map((map) => _mapToMessage(map)).toList();
    } catch (e) {
      debugPrint('❌ Error loading messages before timestamp: $e');
      return [];
    }
  }

  // Get message by Firebase ID
  Future<Message?> getMessageByFirebaseId(String firebaseId) async {
    try {
      final db = await database;
      final results = await db.query(
        _messagesTable,
        where: 'firebase_id = ?',
        whereArgs: [firebaseId],
        limit: 1,
      );
      
      if (results.isEmpty) return null;
      return _mapToMessage(results.first);
    } catch (e) {
      debugPrint('❌ Error getting message by Firebase ID: $e');
      return null;
    }
  }

  // Update message status
  Future<void> updateMessageStatus(String messageId, String status) async {
    try {
      final db = await database;
      await db.update(
        _messagesTable,
        {'status': status, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ? OR firebase_id = ?',
        whereArgs: [messageId, messageId],
      );
      debugPrint('✅ Updated message $messageId status to $status');
    } catch (e) {
      debugPrint('❌ Error updating message status: $e');
    }
  }

  /// Update per-user status entry in the stored JSON status map.
  /// Used when Firebase delivers a status update (delivered/read) so the
  /// cached message reflects the latest tick state without a full re-save.
  Future<void> updateMessageUserStatus(
      String firebaseId, String userId, String userStatus) async {
    try {
      final db = await database;
      final rows = await db.query(
        _messagesTable,
        columns: ['id', 'status'],
        where: 'firebase_id = ?',
        whereArgs: [firebaseId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final existing = rows.first;
      final statusMap = existing['status'] != null
          ? Map<String, String>.from(
              jsonDecode(existing['status'] as String) as Map)
          : <String, String>{};
      // Use prefixed key — matches how Firebase stores it (prevents array conversion)
      final key = statusKey(userId);
      // Only upgrade status, never downgrade (read > delivered > sent)
      const priority = {'sent': 0, 'delivered': 1, 'read': 2};
      // Check both prefixed and legacy raw key
      final current = statusMap[key] ?? statusMap[userId] ?? 'sent';
      if ((priority[userStatus] ?? 0) > (priority[current] ?? 0)) {
        // Remove legacy raw key if present, write only prefixed key
        statusMap.remove(userId);
        statusMap[key] = userStatus;
        await db.update(
          _messagesTable,
          {
            'status': jsonEncode(statusMap),
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [existing['id']],
        );
        debugPrint('✅ SQLite status updated: $firebaseId[$key]=$userStatus');
      }
    } catch (e) {
      debugPrint('❌ Error updating per-user status in SQLite: $e');
    }
  }

  // Mark message as read
  Future<void> markMessageAsRead(String messageId) async {
    try {
      final db = await database;
      await db.update(
        _messagesTable,
        {'is_read': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ? OR firebase_id = ?',
        whereArgs: [messageId, messageId],
      );
    } catch (e) {
      debugPrint('❌ Error marking message as read: $e');
    }
  }

  /// Returns all message IDs (id + firebase_id) that are already marked as read
  /// for a given chat. Used to seed the in-memory read-tracking set on app restart
  /// so already-read messages are never re-processed as unread.
  Future<Set<String>> getReadMessageIds(String chatId, String chatType) async {
    try {
      final db = await database;
      final rows = await db.rawQuery(
        'SELECT id, firebase_id FROM $_messagesTable '
        'WHERE chat_id = ? AND chat_type = ? AND is_read = 1',
        [chatId, chatType],
      );
      final ids = <String>{};
      for (final row in rows) {
        final id = row['id']?.toString();
        final fbId = row['firebase_id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
        if (fbId != null && fbId.isNotEmpty) ids.add(fbId);
      }
      return ids;
    } catch (e) {
      debugPrint('❌ Error fetching read message IDs: $e');
      return {};
    }
  }

  // Get message count for a chat
  Future<int> getMessageCount(String chatId, String chatType) async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_messagesTable WHERE chat_id = ? AND chat_type = ?',
        [chatId, chatType],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('❌ Error getting message count: $e');
      return 0;
    }
  }

  // Delete messages for a chat
  Future<void> deleteMessages(String chatId, String chatType) async {
    try {
      final db = await database;
      await db.delete(
        _messagesTable,
        where: 'chat_id = ? AND chat_type = ?',
        whereArgs: [chatId, chatType],
      );
      debugPrint('🗑️ Deleted messages for chat $chatId');
    } catch (e) {
      debugPrint('❌ Error deleting messages: $e');
    }
  }

  // Clear all messages
  Future<void> clearAllMessages() async {
    try {
      final db = await database;
      await db.delete(_messagesTable);
      debugPrint('🗑️ Cleared all messages from SQLite');
    } catch (e) {
      debugPrint('❌ Error clearing messages: $e');
    }
  }

  // Convert Message to Map for database
  Map<String, dynamic> _messageToMap(Message message, String chatId, String chatType) {
    // Primary key: firebaseId takes priority (set by syncOldMessagesToFirebaseAndDb)
    // so that api_501 is the stable key, not the raw msgId
    final primaryId = (message.firebaseId?.isNotEmpty == true)
        ? message.firebaseId!
        : (message.msgId?.isNotEmpty == true && message.msgId != '0')
            ? message.msgId!
            : message.id;
    return {
      'id': primaryId,
      'chat_id': chatId,
      'chat_type': chatType,
      'sender_id': message.senderId,
      'sender_name': message.senderName,
      'message': message.text,
      'type': message.type,
      'file_path': message.file_path,
      'file_name': message.fileName,
      'file_url': message.fileUrl,
      'timestamp': message.timestamp.millisecondsSinceEpoch,
      'status': jsonEncode(message.status),
      'is_read': (message.readAt != null && message.readAt!.isNotEmpty) ? 1 : 0,
      'reply_to_id': message.replyToId,
      'reply_to_message_json': message.replyToMessage != null
          ? jsonEncode(message.replyToMessage!.toJson())
          : null,
      'firebase_id': message.firebaseId,
      'msg_id': message.msgId,
      'profile_picture_url': message.profile_picture_url?.toString(),
      'metadata': message.metadata != null ? jsonEncode(message.metadata) : null,
      'created_at': message.timestamp.millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
  }

  // Convert Map to Message
  Message _mapToMessage(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: map['sender_name'] as String?,
      msgId: map['msg_id'] as String?,
      text: map['message'] as String? ?? '',
      type: map['type'] as String? ?? 'text',
      file_path: map['file_path'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      status: map['status'] != null 
        ? parseStatus(jsonDecode(map['status'] as String))
        : {'default': 'sent'},
      fileUrl: map['file_url'] as String?,
      firebaseId: map['firebase_id'] as String?,
      fileName: map['file_name'] as String?,
      replyToId: map['reply_to_id'] as String?,
      replyToMessage: map['reply_to_message_json'] != null
        ? Message.fromJson(jsonDecode(map['reply_to_message_json'] as String) as Map<String, dynamic>)
        : null,
      readAt: (map['is_read'] as int?) == 1 ? DateTime.now().toIso8601String() : null,
      metadata: map['metadata'] != null 
        ? (jsonDecode(map['metadata'] as String) as Map<String, dynamic>)
        : null,
      profile_picture_url: map['profile_picture_url'],
    );
  }

  // Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      debugPrint('💾 Database closed');
    }
  }
}
