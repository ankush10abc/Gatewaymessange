import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/chat_list_manager.dart';
import '../../core/services/chat_list_sync_service.dart';
import '../../core/storage/storage_service.dart';
import '../../core/utils/internet_checker.dart';
import '../../shared/providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _animationController.forward();

    // Start chat-list prefetch immediately — runs in background parallel to
    // splash animation. Does NOT block or affect navigation in any way.
    unawaited(_earlyChatListPrefetch());

    _navigateAfterDelay();
  }

  void _navigateAfterDelay() async {
    // Wait for minimum splash duration
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Wait for auth state to be determined
    while (ref.read(authProvider).isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }

    final authState = ref.read(authProvider);
    debugPrint('authState: ${authState.isAuthenticated}');

    if (authState.isAuthenticated) {
      context.go('/home');
    } else {
      context.go('/login');
    }
  }

  /// Starts chat-list prefetch as early as possible — called unawaited from
  /// initState so it runs in parallel with the splash animation and auth check.
  /// By the time the user reaches HomeScreen, Hive already has fresh data.
  /// Only runs when a token + saved user exist (i.e. user was previously logged in).
  Future<void> _earlyChatListPrefetch() async {
    try {
      final storage = StorageService();
      final token = await storage.getToken();
      // No token means not logged in — nothing to prefetch
      if (token == null) return;

      // userId comes from the cached user object (AuthNotifier saves User, not just ID)
      final cachedUser = await storage.getUser();
      if (cachedUser == null) return;
      final userId = cachedUser.id;

      // Skip prefetch if offline — HomeScreen will sync when internet returns
      final hasInternet = await InternetChecker.hasInternet();
      if (!hasInternet) {
        debugPrint('📴 [Splash] Offline — skipping early prefetch');
        return;
      }

      // Open Hive box for this user (idempotent — safe to call multiple times)
      await ChatListManager.init(userId);

      final apiService = ApiService(Dio());
      apiService.setAuthToken(token);

      final response = await apiService.getChatList();
      if (response.isEmpty) return;

      final apiChats =
          response.map((item) => item as Map<String, dynamic>).toList();

      // Same sync pipeline HomeScreen uses — writes unread counts into Hive + Firebase
      final syncService = ChatListSyncService();
      await syncService.initialize(userId);
      await syncService.syncFromApi(apiChats);

      debugPrint(
          '✅ [Splash] Early prefetch done: ${apiChats.length} chats in Hive');
    } catch (e) {
      // Silent fail — HomeScreen will sync on its own
      debugPrint('⚠️ [Splash] Early prefetch failed (non-critical): $e');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.splashcolor,
      body: Center(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Gateway Academy Logo
                    Container(
                      width: 150,
                      height: 150,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Image.asset('assets/icons/ic_logo.png',height: 80,width: 80,)
                      // const Icon(
                      //   Icons.school,
                      //   size: 80,
                      //   color: Color(0xFF1dab61),
                      // ),
                    ),
                    const SizedBox(height: 30),

                    // App Name
                    const Text(
                      'Gateway Academy',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Subtitle
                    const Text(
                      'Parent Communication App ',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 50),

                    // Loading Indicator
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
