import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

class NotificationHandler {
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static final Set<String> _processedNotifications = {};
  static GoRouter? _router;

  static void setRouter(GoRouter router) {
    _router = router;
  }

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      const androidSettings = AndroidInitializationSettings('ic_launcher');
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
      
      // Handle background message clicks
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationClick);
      
      // Handle initial message when app is opened from terminated state
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationClick(initialMessage);
      }
      
      _initialized = true;
      debugPrint('✅ Notification handler initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize notifications: $e');
    }
  }

  static void _onNotificationTap(NotificationResponse response) {
    debugPrint('🔔 Local notification tapped: ${response.payload}');
    
    if (response.payload != null) {
      final parts = response.payload!.split(',');
      debugPrint('🔄 Navigating from local notification: $parts ');
      if (parts.length >= 3) {
        final chatId = parts[0];
        final chatName = parts[1];
        final chatType = parts[2];
        
        debugPrint('🔄 Navigating from local notification: $chatName (ID: $chatId)');
        _navigateToChat(chatId, chatType, chatName);
      }
    }
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('🔔 FOREGROUND MESSAGE RECEIVED:');
    debugPrint('📱 Message ID: ${message.messageId}');
    debugPrint('📝 Title: ${message.notification?.title}');
    debugPrint('📄 Body: ${message.notification?.body}');
    debugPrint('📊 Data: ${message.data}');

    // Check for duplicates
    if (_processedNotifications.contains(message.messageId)) {
      debugPrint('⚠️ Duplicate notification ignored: ${message.messageId}');
      return;
    }
    _processedNotifications.add(message.messageId!);

    // Show local notification for foreground
    await _showLocalNotification(
      title: message.notification?.title ?? 'New Message',
      body: message.notification?.body ?? 'You have a new message',
      data: message.data,
    );
  }

  static Future<void> _handleNotificationClick(RemoteMessage message) async {
    debugPrint('👆 NOTIFICATION CLICKED:');
    debugPrint('📱 Message ID: ${message.messageId}');
    debugPrint('📊 Data: ${message.data}');
    
    if (message.data['type'] == 'chat') {
      // Handle group chat navigation
      if (message.data['group_id'] != null && message.data['group_id'].toString().isNotEmpty) {
        final groupId = message.data['group_id'].toString();
        final groupName = message.data['group_name'] ?? 'Group Chat';
        
        debugPrint('🔄 Navigating to group chat: $groupName (ID: $groupId)');
        _navigateToChat(groupId, 'group', groupName);
      }
      // Handle private conversation navigation
      else if (message.data['receiver_id'] != null) {
        final senderId = message.data['sender_id'].toString();
        final senderName = message.data['sender_name'] ?? 'User';
        
        debugPrint('🔄 Navigating to private chat: $senderName (ID: $senderId)');
        _navigateToChat(senderId, 'private', senderName);
      }
    }
  }

  static void _navigateToChat(String chatId, String chatType, String chatName) {
    // Use GoRouter for navigation
    debugPrint("Ankush banawade $chatId $chatType $chatName");
    if (_router != null) {
      _router!.go(
        '/chat/$chatId?type=$chatType&name=${Uri.encodeComponent(chatName)}',
      );
      // _router!.go('/chat/:chatId', extra: {
      //   'chatId': chatId,
      //   'chatType': chatType,
      //   'chatName': chatName,
      // });
    }
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'chat_messages',
        'Chat Messages',
        channelDescription: 'Notifications for chat messages',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_launcher',
        showWhen: true,
        autoCancel: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
        payload: data?['group_id']?.toString().isNotEmpty == true 
            ? '${data?['group_id']},${data?['group_name']},group'
            : '${data?['sender_id']},${data?['sender_name']},private',
      );

      debugPrint('✅ Local notification shown: $title');
    } catch (e) {
      debugPrint('❌ Failed to show local notification: $e');
    }
  }

  // Background message handler (must be top-level function)
  static Future<void> backgroundMessageHandler(RemoteMessage message) async {
    debugPrint('🌙 BACKGROUND MESSAGE RECEIVED:');
    debugPrint('📱 Message ID: ${message.messageId}');
    debugPrint('📝 Title: ${message.notification?.title}');
    debugPrint('📄 Body: ${message.notification?.body}');
    debugPrint('📊 Data: ${message.data}');
  }
}