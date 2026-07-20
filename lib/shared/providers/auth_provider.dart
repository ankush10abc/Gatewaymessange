import 'package:check_setting/app/app.dart' show navigatorKey;
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/hive_chat_data_source.dart';
import '../../core/models/user_model.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/simple_notification_service.dart';
import '../../core/services/verification_check_controller.dart';
import '../../core/storage/storage_service.dart';
import '../../core/utils/internet_checker.dart';

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;

  AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  late final ApiService _apiService;
  final StorageService _storage = StorageService();

  AuthNotifier() : super(AuthState(isLoading: true)) {
    final dio = Dio();
    _apiService = ApiService(dio);

    // Case 2 / generic 401: ping succeeded + retry still 401 → confirmed logout
    ApiService.onUnauthorized = () async {
      bool hasinternet = await InternetChecker.hasInternet();
      if (hasinternet) _handle401Unauthorized();
    };

    // Case 1: session_displaced — intentional server-side session kill.
    // Clear token, show dialog, navigate to login.
    ApiService.onSessionDisplaced = () async {
      await _handleSessionDisplaced();
    };

    // Defer auth check to prevent initialization errors

    Future.microtask(() async {
      // Always load cached credentials first
      final token = await _storage.getToken();
      final cachedUser = await _storage.getUser();

      if (token != null && cachedUser != null) {
        _apiService.setAuthToken(token);
        // Set authenticated with cached data immediately
        state = state.copyWith(
          user: cachedUser,
          isAuthenticated: true,
          isLoading: false,
        );

        // Then verify token with server if internet available
        bool hasinternet = await InternetChecker.hasInternet();
        if (hasinternet) {
          try {
            final user = await _apiService.getCurrentUser();
            state = state.copyWith(user: user);
            await FirebaseService.setUserOnline(user.id);
            await _apiService.setOnlineStatus();
          } on DioException catch (e) {
            if (e.response?.statusCode == 401 ||
                e.response?.statusCode == 403) {
              // await _handleAuthFailure();
            }
          } catch (_) {
            // Keep cached user on any other error
          }
        }
      } else {
        state = state.copyWith(isLoading: false);
      }
    });
  }

  Future<void> _checkAuthStatus() async {
    state = state.copyWith(isLoading: true);

    try {
      final token = await _storage.getToken();

      if (token != null) {
        _apiService.setAuthToken(token);

        try {
          final user = await _apiService.getCurrentUser();
          state = state.copyWith(
            user: user,
            isAuthenticated: true,
            isLoading: false,
          );
          await FirebaseService.setUserOnline(user.id);
          await _apiService.setOnlineStatus();
        } on DioException catch (e) {
          if (e.response?.statusCode == 401) {
            // Confirmed invalid token — logout
            bool hasInternet = await InternetChecker.hasInternet();
            if (hasInternet) await _handleAuthFailure();
          } else {
            // Network error, timeout, server error — keep user logged in with cached data
            final cachedUser = await _storage.getUser();
            state = state.copyWith(
              user: cachedUser,
              isAuthenticated: true,
              isLoading: false,
            );
          }
        } catch (_) {
          // Any other error — keep user logged in with cached data
          final cachedUser = await _storage.getUser();
          state = state.copyWith(
            user: cachedUser,
            isAuthenticated: true,
            isLoading: false,
          );
        }
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  // MethodChannel: location foreground service notification
  static const _locationChannel =
      MethodChannel('com.company.gateway/location_service');

  // Start both location + telemetry notifications on login
  Future<void> _startAllServices() async {
    try {
      await _locationChannel.invokeMethod('startLocationService');
    } catch (_) {}
    await VerificationCheckController.start(); // Start telemetry notification
  }

  // Remove both location + telemetry notifications on logout / 401
  Future<void> _stopAllServices() async {
    try {
      await _locationChannel.invokeMethod('stopLocationService');
    } catch (_) {}
    await VerificationCheckController.stop(); // Stop telemetry notification
  }

  Future<void> _handleAuthFailure() async {
    final userId = state.user?.id;
    // await _stopAllServices(); // Remove all notifications on forced logout
    // await _storage.clearAll();
    // _apiService.clearAuthToken();
    // if (userId != null) await HiveChatDataSource().clearForUser(userId);
    // state = AuthState();
  }

  void _handle401Unauthorized() async {
    final userId = state.user?.id;
    await _stopAllServices(); // Remove all notifications on 401
    await _storage.clearAll();
    _apiService.clearAuthToken();
    if (userId != null) await HiveChatDataSource().clearForUser(userId);
    state = AuthState();
  }

  /// Case 1: session_displaced — user logged in on another device.
  /// Show an informational dialog, then clear state and navigate to login.
  Future<void> _handleSessionDisplaced() async {
    final userId = state.user?.id;
    await _stopAllServices();
    await _storage.clearAll();
    _apiService.clearAuthToken();
    if (userId != null) await HiveChatDataSource().clearForUser(userId);
    state = AuthState();

    // Show dialog using the global navigator key so we don’t need a BuildContext
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Logged Out'),
          content: const Text(
            'You have been logged in on another device. '
            'This session has been ended.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<bool> login(String mobile, String password, [var fcmToken]) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Always fetch a fresh FCM token — never rely on the passed value
      // which may be empty if Firebase wasn't ready when the login screen loaded.
      String fcmToken1 = fcmToken == null || fcmToken.toString().isEmpty ? "" : fcmToken;
      try {
        fcmToken1 = await FirebaseMessaging.instance.getToken() ?? '';
        debugPrint('FCM Token: $fcmToken1');
      } catch (e) {
        debugPrint('Failed to get FCM token: $e');
      }

      // Clear any stale auth token before login so it is never injected
      // into the login request headers, which causes PHP to reject valid credentials.
      _apiService.clearAuthToken();

      final request =
          LoginRequest(mobile: mobile, password: password, fcmToken: fcmToken1);
      final response = await _apiService.login(request);

      // Store credentials securely
      await _storage.saveToken(response.token);
      await _storage.saveUser(response.user);
      debugPrint("Ankush Banawade ${response.user.role}");
      debugPrint("Ankush Banawade ${response.token}");
      state = state.copyWith(
        user: response.user,
        isAuthenticated: true,
        isLoading: false,
        error: null,
      );


      // Set user online in Firebase and API
      await FirebaseService.setUserOnline(response.user.id);
      await _apiService.setOnlineStatus();

      // Start location + telemetry foreground services — shows persistent background notifications
      await _startAllServices();

      // Initialize simple notifications
      await SimpleNotificationService.initialize();

      return true;
    } catch (e) {
      debugPrint('Login error in auth provider: $e');

      // api_service_simple.login() always throws Exception(message) with the
      // server's human-readable message already extracted. Strip the prefix.
      String errorMessage = 'Login failed';
      if (e is Exception) {
        final msg = e.toString();
        errorMessage = msg.startsWith('Exception: ') ? msg.substring(11) : msg;
      }

      state = state.copyWith(
        isAuthenticated: false,
        isLoading: false,
        error: errorMessage,
      );
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    final loggedOutUserId = state.user?.id;

    try {
      if (state.user != null) {
        await FirebaseService.setUserOffline(state.user!.id);
        await _apiService.setOfflineStatus();
      }

      await _apiService.logout();
      await _stopAllServices(); // Remove all background notifications on logout
      await _storage.clearAll();

      // Clear this user's Hive chat cache so the next user never sees stale data
      if (loggedOutUserId != null) {
        await HiveChatDataSource().clearForUser(loggedOutUserId);
      }

      state = AuthState();
    } catch (e) {
      await _stopAllServices(); // Ensure all notifications removed even on error
      await _storage.clearAll();
      if (loggedOutUserId != null) {
        await HiveChatDataSource().clearForUser(loggedOutUserId);
      }
      state = AuthState();
    }
  }

  // Get current user info
  Future<User?> getCurrentUser() async {
    try {
      return await _apiService.getCurrentUser();
    } catch (e) {
      return null;
    }
  }

  // Check if user is authenticated
  bool get isAuthenticated => state.isAuthenticated;

  // Get current user
  User? get currentUser => state.user;

  // Update user data
  void updateUser(User user) {
    state = state.copyWith(user: user);
    _storage.saveUser(user);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
