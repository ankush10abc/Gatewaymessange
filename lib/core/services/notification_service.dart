import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static String TAG = 'NotificationService';
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static BuildContext? _context;

  static Future<void> initialize(BuildContext context) async {
    _context = context;
    debugPrint("$TAG initializeic_launcher ");
    try {
      // Request permission
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Initialize local notifications
      const androidSettings = AndroidInitializationSettings('ic_notification');
      const iosSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      
      // Handle background message taps
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
      
      // Handle terminated app message taps
      _handleTerminatedAppMessage();
    } catch (e) {
      debugPrint('Notification service initialization failed: $e');
    }
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('Foreground message: ${message.data}');
    debugPrint("$TAG initializeic_launcher $message");
    // Show local notification for foreground messages
    // Small icon (white silhouette) + Large icon (colored, preserves original colors)
    const androidDetails = AndroidNotificationDetails(
      'chat_channel',
      'Chat Messages',
      channelDescription: 'Notifications for chat messages',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      // largeIcon: DrawableResourceAndroidBitmap('ic_notification_colored'),
    );
    
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    debugPrint('App opened from terminated state: ${message.notification?.title ?? 'New Message'}');
    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'New Message',
      message.notification?.body ?? 'You have a new message',
      details,
      payload: _createPayload(message.data),
    );
  }

  static void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.data}');
    debugPrint("$TAG initializeic_launcher $message");
    _navigateToChat(message.data);
  }

  static void _onNotificationTap(NotificationResponse response) {
    debugPrint('Local notification tapped: ${response.payload}');
    if (response.payload != null) {
      final data = _parsePayload(response.payload!);
      _navigateToChat(data);
    }
  }

  static Future<void> _handleTerminatedAppMessage() async {
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App opened from terminated state: ${initialMessage.data}');
      // Delay navigation to ensure app is fully loaded
      Future.delayed(const Duration(seconds: 1), () {
        _navigateToChat(initialMessage.data);
      });
    }
  }

  static void _navigateToChat(Map<String, dynamic> data) {
    debugPrint('App opened from terminated state: ${data}');
    if (_context == null) return;
    
    final chatId = data['chat_id'] ?? data['chatId'];
    final chatType = data['chat_type'] ?? data['chatType'] ?? 'user';
    final chatName = data['chat_name'] ?? data['chatName'] ?? 'Chat';
    final attendance_group = data['attendance_group'] ?? data['attendance_group'] ?? 'false';

    if (chatId != null) {
      _context!.push('/chat/$chatId?type=$chatType&attendance_group=$attendance_group&name=${Uri.encodeComponent(chatName)}');
    }
  }

  static String _createPayload(Map<String, dynamic> data) {
    return '${data['chat_id'] ?? ''}|${data['chat_type'] ?? 'user'}|${data['chat_name'] ?? 'Chat'}|${data['attendance_group'] ?? 'false'}';
  }

  static Map<String, dynamic> _parsePayload(String payload) {
    final parts = payload.split('|');
    return {
      'chat_id': parts.isNotEmpty ? parts[0] : null,
      'chat_type': parts.length > 1 ? parts[1] : 'user',
      'chat_name': parts.length > 2 ? parts[2] : 'Chat',
      'attendance_group': parts.length > 3 ? parts[3] : 'false',
    };
  }
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    debugPrint('Background message: ${message.data}');
  } catch (e) {
    debugPrint('Background handler error: $e');
  }
}