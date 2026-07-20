import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/routes/app_router.dart';
import 'core/services/api_service_simple.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/hive_init_service.dart';
import 'core/services/image_cache_service.dart';
import 'core/services/message_database_service.dart';
import 'core/services/notification_handler.dart';
import 'core/services/offline_queue_service.dart';
import 'core/services/sync_service.dart';
import 'core/services/update_service.dart';
import 'core/utils/helpers.dart';

// Top-level background message handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
      options: const FirebaseOptions(
          apiKey: 'AIzaSyA2qeQyT5BTYvFOt3ruL-ufeK1dkL_NGvQ',
          appId: '1:335214113602:android:d4ef30b1fa628b93228edb',
          messagingSenderId: '335214113602',
          projectId: 'reportgateway-28186'));
  await NotificationHandler.backgroundMessageHandler(message);
}

final _appLinks = AppLinks();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase
    await Firebase.initializeApp(
        options: const FirebaseOptions(
            apiKey: 'AIzaSyA2qeQyT5BTYvFOt3ruL-ufeK1dkL_NGvQ',
            appId: '1:335214113602:android:d4ef30b1fa628b93228edb',
            messagingSenderId: '335214113602',
            projectId: 'reportgateway-28186'));

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
      cacheSizeBytes: 1048576,
    );

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await NotificationHandler.initialize();

    // Initialize Hive for offline mode
    await HiveInitService.initialize();

    // Initialize SQLite database for messages
    await MessageDatabaseService.initialize();

    // Initialize image cache
    await ImageCacheService().initialize();

    // Initialize offline queue service
    final dio = Dio();
    final apiService = ApiService(dio);
    await OfflineQueueService.initialize(apiService);

    // Initialize sync service
    await SyncService.initialize();

    debugPrint('✅ All services initialized');
  } catch (e) {
    debugPrint('❌ Initialization error: $e');
  }

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    // Check for updates 2 seconds after app starts
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    try {
      final dio = Dio();
      final apiService = ApiService(dio);
      final updateService = UpdateService(apiService);
      await updateService.checkAndShowUpdate(context);
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  void _initDeepLinks() {
    // Handle cold-start deep link (app launched from a link while not running)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        debugPrint('Deep link cold-start: $uri');
        _handleDeepLink(uri);
      }
    });

    // Handle warm/hot deep links (app already running)
    _appLinks.uriLinkStream.listen((uri) {
      debugPrint('Deep link stream: $uri');
      _handleDeepLink(uri);
    }, onError: (e) {
      debugPrint('Deep link stream error: $e');
    });
  }

  void _handleDeepLink(Uri uri) {
    String? message;
    
    // HTTPS: https://gatewayreports.in/send/app?message=...
    if (uri.host == 'gatewayreports.in' && uri.path.startsWith('/send/app')) {
      message = uri.queryParameters['message'];
    }
    // Custom scheme for Firefox: gateway://send?message=...
    else if (uri.scheme == 'gateway') {
      message = uri.queryParameters['message'];
    }
    
    if (message != null && message.isNotEmpty) {
      DeepLinkService.setPendingMessage(message);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final router = ref.read(routerProvider);
        router.go('/chat-selection?message=${Uri.encodeComponent(message!)}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return  GatewayMessengerApp();
  }
}
