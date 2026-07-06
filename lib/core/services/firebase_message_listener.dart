import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/optimized_chat_provider.dart';

class FirebaseMessageListener {
  static WidgetRef? _ref;
  static String? _currentChatId;

  // Throttle background-open full API refresh
  static DateTime? _lastRefreshTime;
  static const _refreshCooldown = Duration(seconds: 10);

  static void init(WidgetRef ref) {
    _ref = ref;

    // Foreground FCM: do NOT increment unread here.
    // ChatListSyncService._handleNewMessage (Firebase RTDB onChildAdded) is the
    // single source of truth for unread increments. Incrementing here too causes
    // double-count (+2 per message).
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📥 [FML] Foreground notification received (badge handled by ChatListSyncService)');
    });

    // Background-opened: user tapped notification → throttled API refresh to sync
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔔 [FML] Notification opened app: ${message.data}');
      _throttledRefresh();
    });
  }

  static void setCurrentChatId(String? chatId) {
    _currentChatId = chatId;
  }

  static void _throttledRefresh() {
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < _refreshCooldown) {
      return;
    }
    _lastRefreshTime = now;
    _ref?.read(optimizedChatProvider.notifier).refresh();
  }
}
