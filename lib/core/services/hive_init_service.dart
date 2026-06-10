import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_hive_model.dart';
import '../models/chat_hive_model_adapter.dart';

/// Initialize all Hive boxes for offline mode
class HiveInitService {
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    await Hive.initFlutter();

    // Register adapters
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ChatHiveModelAdapter());
    }

    // Open all required boxes
    await Future.wait([
      Hive.openBox('offline_queue'),      // Pending messages queue
      Hive.openBox('messages_cache'),     // Cached messages per chat
      Hive.openBox('chats_cache'),        // Cached chat list
      Hive.openBox('sync_metadata'),      // Last sync timestamps
      Hive.openBox('user_cache'),         // User data cache
      Hive.openBox<ChatHiveModel>('chats_v1'), // Optimized chat cache
      Hive.openBox('chat_metadata'),      // Chat metadata
    ]);

    _isInitialized = true;
    debugPrint('✅ Hive initialized - All boxes ready');
  }

  static Future<void> clearAllCache() async {
    await Hive.box('offline_queue').clear();
    await Hive.box('messages_cache').clear();
    await Hive.box('chats_cache').clear();
    await Hive.box('sync_metadata').clear();
    await Hive.box('user_cache').clear();
    await Hive.box('chats_v1').clear();
    await Hive.box('chat_metadata').clear();
    debugPrint('🗑️ All Hive cache cleared');
  }
}
