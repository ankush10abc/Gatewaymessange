import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/notification_handler.dart';
import 'routes/app_router.dart';
import 'theme/app_theme.dart';
import '../core/providers/storage_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class GatewayMessengerApp extends ConsumerStatefulWidget {
  const GatewayMessengerApp({super.key});

  @override
  ConsumerState<GatewayMessengerApp> createState() => _GatewayMessengerAppState();
}

class _GatewayMessengerAppState extends ConsumerState<GatewayMessengerApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final storageInit = ref.watch(storageInitProvider);
    
    // Set router for notifications
    NotificationHandler.setRouter(router);

    return MaterialApp.router(
      title: 'Gateway Messenger',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return storageInit.when(
          data: (_) => child ?? const SizedBox(),
          loading: () =>  MaterialApp(
            navigatorKey: navigatorKey,
            home: Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
          error: (error, stack) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('Error: $error'),
              ),
            ),
          ),
        );
      },
    );
  }
}
