import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class SimpleNotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(initSettings);
      _initialized = true;
      debugPrint('Simple notification service initialized');
    } catch (e) {
      debugPrint('Failed to initialize notifications: $e');
    }
  }

  static Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    if (!_initialized) await initialize();
    
    try {
      const androidDetails = AndroidNotificationDetails(
        'chat_channel',
        'Chat Messages',
        channelDescription: 'Notifications for chat messages',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_launcher',
      );
      
      const iosDetails = DarwinNotificationDetails();
      const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
      
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
      );
    } catch (e) {
      debugPrint('Failed to show notification: $e');
    }
  }
}