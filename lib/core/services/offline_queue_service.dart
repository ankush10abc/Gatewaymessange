import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

class OfflineQueueService {
  static late Box _queueBox;
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (!_isInitialized) {
      _queueBox = await Hive.openBox('offline_queue');
      _isInitialized = true;
      _processQueue();
    }
  }

  static Future<void> addToQueue(Map<String, dynamic> request) async {
    await _queueBox.add({
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'request': request,
    });
  }

  static Future<void> _processQueue() async {
    final connectivity = Connectivity();
    connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _executeQueuedRequests();
      }
    });
  }

  static Future<void> _executeQueuedRequests() async {
    final queuedItems = _queueBox.values.toList();

    for (int i = 0; i < queuedItems.length; i++) {
      try {
        final item = queuedItems[i];
        final request = item['request'] as Map<String, dynamic>;

        // Execute the request
        await _executeRequest(request);

        // Remove from queue on success
        await _queueBox.deleteAt(i);
      } catch (e) {
        // Keep in queue for retry
        print('Failed to execute queued request: $e');
      }
    }
  }

  static Future<void> _executeRequest(Map<String, dynamic> request) async {
    // TODO: Implement actual API call based on request type
    switch (request['type']) {
      case 'send_message':
        // Execute send message API
        break;
      case 'mark_read':
        // Execute mark as read API
        break;
      case 'upload_file':
        // Execute file upload API
        break;
    }
  }

  static Future<bool> isOnline() async {
    final connectivity = Connectivity();
    final result = await connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }
}
