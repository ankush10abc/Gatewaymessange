import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../services/api_service_simple.dart';
import 'dart:async';

class PendingMessage {
  final String tempId;
  final String chatId;
  final String chatType;
  final String message;
  final String type;
  final String firebaseKey;
  final DateTime clientTimestamp;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? replyToMessageId;
  final String status;
  final int retryCount;

  PendingMessage({
    required this.tempId,
    required this.chatId,
    required this.chatType,
    required this.message,
    required this.type,
    required this.firebaseKey,
    required this.clientTimestamp,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.replyToMessageId,
    this.status = 'pending',
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'temp_id': tempId,
    'chat_id': chatId,
    'chat_type': chatType,
    'message': message,
    'type': type,
    'firebase_key': firebaseKey,
    'client_timestamp': clientTimestamp.toIso8601String(),
    'file_path': filePath,
    'file_name': fileName,
    'file_size': fileSize,
    'reply_to_message_id': replyToMessageId,
    'status': status,
    'retry_count': retryCount,
  };

  factory PendingMessage.fromJson(Map<String, dynamic> json) => PendingMessage(
    tempId: json['temp_id'],
    chatId: json['chat_id'],
    chatType: json['chat_type'],
    message: json['message'],
    type: json['type'],
    firebaseKey: json['firebase_key'],
    clientTimestamp: DateTime.parse(json['client_timestamp']),
    filePath: json['file_path'],
    fileName: json['file_name'],
    fileSize: json['file_size'],
    replyToMessageId: json['reply_to_message_id'],
    status: json['status'] ?? 'pending',
    retryCount: json['retry_count'] ?? 0,
  );

  PendingMessage copyWith({
    String? status,
    int? retryCount,
  }) => PendingMessage(
    tempId: tempId,
    chatId: chatId,
    chatType: chatType,
    message: message,
    type: type,
    firebaseKey: firebaseKey,
    clientTimestamp: clientTimestamp,
    filePath: filePath,
    fileName: fileName,
    fileSize: fileSize,
    replyToMessageId: replyToMessageId,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
  );
}

class OfflineQueueService {
  static Box? _queueBox;
  static bool _isInitialized = false;
  static ApiService? _apiService;
  static const int maxQueueSize = 1000;
  static const int maxRetries = 3;
  static const int batchSize = 50;
  static bool _isProcessing = false;

  static Future<void> initialize(ApiService apiService) async {
    if (_isInitialized) return;
    _apiService = apiService;
    try {
      _queueBox = await Hive.openBox('offline_queue');
      _isInitialized = true;
      _startConnectivityListener();
      await _processQueue();
    } catch (e) {
      debugPrint('OfflineQueueService init error: $e');
    }
  }

  /// Add message to offline queue
  static Future<void> queueMessage(PendingMessage message) async {
    if (!_isInitialized || _queueBox == null) {
      debugPrint('⚠️ Queue not initialized');
      return;
    }
    
    final queueCount = _queueBox!.length;
    if (queueCount >= maxQueueSize) {
      throw Exception('Queue full: $maxQueueSize messages limit reached');
    }

    await _queueBox!.put(message.tempId, message.toJson());
    debugPrint('✅ Queued message: ${message.tempId}');
    
    if (await isOnline()) {
      await _processQueue();
    }
  }

  /// Get queue statistics
  static Map<String, dynamic> getQueueStats() {
    if (!_isInitialized || _queueBox == null) return {'total': 0, 'pending': 0, 'failed': 0};
    
    try {
      final allMessages = _queueBox!.values.map((e) => PendingMessage.fromJson(Map<String, dynamic>.from(e))).toList();
      final pending = allMessages.where((m) => m.status == 'pending').length;
      final failed = allMessages.where((m) => m.status == 'failed').length;
      final oldestTimestamp = allMessages.isNotEmpty ? allMessages.map((m) => m.clientTimestamp).reduce((a, b) => a.isBefore(b) ? a : b) : null;

      return {
        'total': allMessages.length,
        'pending': pending,
        'failed': failed,
        'oldest_timestamp': oldestTimestamp?.toIso8601String(),
        'is_full': allMessages.length >= maxQueueSize,
      };
    } catch (e) {
      debugPrint('Queue stats error: $e');
      return {'total': 0, 'pending': 0, 'failed': 0};
    }
  }

  /// Process queued messages
  static Future<void> _processQueue() async {
    if (!_isInitialized || _isProcessing || _apiService == null || _queueBox == null) return;
    if (!await isOnline()) return;

    _isProcessing = true;
    debugPrint('🔄 Processing offline queue...');

    try {
      final allMessages = _queueBox!.values
          .map((e) => PendingMessage.fromJson(Map<String, dynamic>.from(e)))
          .where((m) => m.status != 'sending' && m.retryCount < maxRetries)
          .toList();

      if (allMessages.isEmpty) {
        debugPrint('✅ Queue empty');
        return;
      }

      for (int i = 0; i < allMessages.length; i += batchSize) {
        final batch = allMessages.skip(i).take(batchSize).toList();
        await _sendBatch(batch);
      }

      debugPrint('✅ Queue processing complete');
    } catch (e) {
      debugPrint('❌ Queue processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Send batch of messages
  static Future<void> _sendBatch(List<PendingMessage> messages) async {
    if (_apiService == null || _queueBox == null) return;

    final batchData = messages.map((m) => {
      'temp_id': m.tempId,
      'chat_id': m.chatId,
      'chat_type': m.chatType,
      'message': m.message,
      'type': m.type,
      'firebase_key': m.firebaseKey,
      'client_timestamp': m.clientTimestamp.toIso8601String(),
      if (m.filePath != null) 'file_path': m.filePath,
      if (m.fileName != null) 'file_name': m.fileName,
      if (m.fileSize != null) 'file_size': m.fileSize,
      if (m.replyToMessageId != null) 'reply_to_message_id': m.replyToMessageId,
    }).toList();

    try {
      final response = await _apiService!.batchSendMessages(batchData);
      final sent = response['data']['sent'] as List? ?? [];
      final failed = response['data']['failed'] as List? ?? [];

      for (final item in sent) {
        final tempId = item['temp_id'];
        await _queueBox!.delete(tempId);
        debugPrint('✅ Sent: $tempId');
      }

      for (final item in failed) {
        final tempId = item['temp_id'];
        final message = messages.firstWhere((m) => m.tempId == tempId);
        final updated = message.copyWith(
          status: 'failed',
          retryCount: message.retryCount + 1,
        );
        await _queueBox!.put(tempId, updated.toJson());
        debugPrint('❌ Failed: $tempId - ${item['error']}');
      }
    } catch (e) {
      debugPrint('❌ Batch send error: $e');
      for (final message in messages) {
        final updated = message.copyWith(
          status: 'failed',
          retryCount: message.retryCount + 1,
        );
        await _queueBox!.put(message.tempId, updated.toJson());
      }
    }
  }

  /// Listen for connectivity changes
  static void _startConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      if (result != ConnectivityResult.none) {
        debugPrint('🌐 Connection restored, processing queue...');
        _processQueue();
      }
    });
  }

  /// Check if device is online
  static Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Clear queue
  static Future<void> clearQueue() async {
    if (!_isInitialized || _queueBox == null) return;
    await _queueBox!.clear();
    debugPrint('🗑️ Queue cleared');
  }

  /// Get pending messages for chat
  static List<PendingMessage> getPendingMessagesForChat(String chatId) {
    if (!_isInitialized || _queueBox == null) return [];
    try {
      return _queueBox!.values
          .map((e) => PendingMessage.fromJson(Map<String, dynamic>.from(e)))
          .where((m) => m.chatId == chatId)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Remove from queue
  static Future<void> removeFromQueue(String tempId) async {
    if (!_isInitialized || _queueBox == null) return;
    await _queueBox!.delete(tempId);
    debugPrint('🗑️ Removed from queue: $tempId');
  }
}
