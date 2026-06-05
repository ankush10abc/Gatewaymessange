import 'package:flutter/material.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/utils/internet_checker.dart';

/// Widget to show offline mode status and queue info
class OfflineStatusWidget extends StatefulWidget {
  const OfflineStatusWidget({Key? key}) : super(key: key);

  @override
  State<OfflineStatusWidget> createState() => _OfflineStatusWidgetState();
}

class _OfflineStatusWidgetState extends State<OfflineStatusWidget> {
  bool _isOnline = true;
  Map<String, dynamic> _queueStats = {};

  @override
  void initState() {
    super.initState();
    _checkStatus();
    // Refresh every 5 seconds
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 5));
      if (mounted) {
        _checkStatus();
        return true;
      }
      return false;
    });
  }

  Future<void> _checkStatus() async {
    final isOnline = await InternetChecker.hasInternet();
    final stats = OfflineQueueService.getQueueStats();
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
        _queueStats = stats;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _queueStats['total'] ?? 0;
    final pending = _queueStats['pending'] ?? 0;
    final failed = _queueStats['failed'] ?? 0;

    if (_isOnline && total == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _isOnline ? Colors.blue.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isOnline ? Colors.blue : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isOnline ? Icons.cloud_queue : Icons.cloud_off,
            size: 16,
            color: _isOnline ? Colors.blue : Colors.orange,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _isOnline
                  ? 'Syncing $pending message${pending != 1 ? 's' : ''}...'
                  : 'Offline - $total message${total != 1 ? 's' : ''} queued',
              style: TextStyle(
                fontSize: 12,
                color: _isOnline ? Colors.blue.shade800 : Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (failed > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$failed failed',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Helper to queue message for offline sending
class OfflineMessageHelper {
  static Future<void> queueMessage({
    required String chatId,
    required String chatType,
    required String message,
    required String type,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? replyToMessageId,
  }) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final firebaseKey = 'fb_$tempId';

    final pendingMessage = PendingMessage(
      tempId: tempId,
      chatId: chatId,
      chatType: chatType,
      message: message,
      type: type,
      firebaseKey: firebaseKey,
      clientTimestamp: DateTime.now(),
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      replyToMessageId: replyToMessageId,
    );

    try {
      await OfflineQueueService.queueMessage(pendingMessage);
      debugPrint('✅ Message queued for offline sending');
    } catch (e) {
      debugPrint('❌ Failed to queue message: $e');
      rethrow;
    }
  }

  static bool isQueueFull() {
    final stats = OfflineQueueService.getQueueStats();
    return stats['is_full'] == true;
  }

  static int getPendingCount() {
    final stats = OfflineQueueService.getQueueStats();
    return stats['pending'] ?? 0;
  }
}
