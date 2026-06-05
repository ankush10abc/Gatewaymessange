// import 'dart:async';
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:dio/dio.dart';
// import 'package:flutter/services.dart';
//
// class TelemetryService {
//   static final TelemetryService _instance = TelemetryService._internal();
//   factory TelemetryService() => _instance;
//   TelemetryService._internal();
//
//   static const platform = MethodChannel('com.company.gateway/telemetry');
//   final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
//   Timer? _telemetryTimer;
//   bool _isRunning = false;
//   String? _userId;
//   String? _authToken;
//
//   static const String channelId = 'telemetry_service';
//   static const String channelName = 'Telemetry Service';
//   static const int notificationId = 1001;
//
//   Future<void> initialize() async {
//     const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
//     const iosSettings = DarwinInitializationSettings();
//     const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
//     await _notifications.initialize(settings);
//
//     if (Platform.isAndroid) {
//       const androidChannel = AndroidNotificationChannel(
//         channelId,
//         channelName,
//         description: 'Keeps the app running for location tracking',
//         importance: Importance.low,
//       );
//       await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
//           ?.createNotificationChannel(androidChannel);
//     }
//   }
//
//   Future<void> startTelemetry(String userId, String authToken) async {
//     if (_isRunning) return;
//
//     _userId = userId;
//     _authToken = authToken;
//     _isRunning = true;
//
//     if (Platform.isAndroid) {
//       try {
//         await platform.invokeMethod('startForegroundService', {
//           'userId': userId,
//           'authToken': authToken,
//         });
//       } catch (e) {
//         debugPrint('Error starting foreground service: $e');
//       }
//     } else {
//       await _showPersistentNotification();
//       _startPeriodicTelemetry();
//     }
//   }
//
//   Future<void> _showPersistentNotification() async {
//     const androidDetails = AndroidNotificationDetails(
//       channelId,
//       channelName,
//       channelDescription: 'Keeps the app running for location tracking',
//       importance: Importance.low,
//       priority: Priority.low,
//       ongoing: true,
//       autoCancel: false,
//       playSound: false,
//       enableVibration: false,
//       showWhen: false,
//       visibility: NotificationVisibility.public,
//     );
//     const iosDetails = DarwinNotificationDetails(
//       presentAlert: false,
//       presentBadge: false,
//       presentSound: false,
//     );
//     const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
//     await _notifications.show(
//       notificationId,
//       'Gateway Messenger',
//       'Tracking location in background',
//       details,
//     );
//   }
//
//   void _startPeriodicTelemetry() {
//     _telemetryTimer?.cancel();
//     _telemetryTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
//       await _sendTelemetryData();
//     });
//     _sendTelemetryData();
//   }
//
//   Future<void> _sendTelemetryData() async {
//     if (_userId == null || _authToken == null) return;
//
//     try {
//       final serviceEnabled = await Geolocator.isLocationServiceEnabled();
//       if (!serviceEnabled) {
//         debugPrint('Location services disabled');
//         return;
//       }
//
//       final permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
//         debugPrint('Location permission denied');
//         return;
//       }
//
//       final position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//         timeLimit: const Duration(seconds: 10),
//       );
//
//       final dio = Dio();
//       await dio.post(
//         'https://gatewayreports.in/api/telemetry',
//         data: {
//           'user_id': _userId,
//           'latitude': position.latitude,
//           'longitude': position.longitude,
//           'timestamp': DateTime.now().toIso8601String(),
//         },
//         options: Options(
//           headers: {'Authorization': 'Bearer $_authToken'},
//           sendTimeout: const Duration(seconds: 10),
//           receiveTimeout: const Duration(seconds: 10),
//         ),
//       );
//       debugPrint('Telemetry sent: ${position.latitude}, ${position.longitude}');
//     } catch (e) {
//       debugPrint('Telemetry error: $e');
//     }
//   }
//
//   Future<void> stopTelemetry() async {
//     _isRunning = false;
//     _telemetryTimer?.cancel();
//     _telemetryTimer = null;
//
//     if (Platform.isAndroid) {
//       try {
//         await platform.invokeMethod('stopForegroundService');
//       } catch (e) {
//         debugPrint('Error stopping foreground service: $e');
//       }
//     }
//
//     await _notifications.cancel(notificationId);
//   }
// }
