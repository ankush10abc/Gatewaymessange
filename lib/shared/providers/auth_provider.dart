import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/user_model.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/simple_notification_service.dart';
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

    // Set 401 handler
    ApiService.onUnauthorized = () async {
      bool hasinternet = await InternetChecker.hasInternet();
      if (hasinternet) _handle401Unauthorized();
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
            if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
              await _handleAuthFailure();
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

  Future<void> _handleAuthFailure() async {
    await _storage.clearAll();
    _apiService.clearAuthToken();
    state = AuthState();
  }

  void _handle401Unauthorized() async {
    await _storage.clearAll();
    _apiService.clearAuthToken();
    state = AuthState();
  }

  Future<bool> login(String mobile, String password) async {
    state = state.copyWith(isLoading: true);

    try {
      // Get FCM token
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
        debugPrint('FCM Token: $fcmToken');
      } catch (e) {
        debugPrint('Failed to get FCM token: $e');
      }

      final request =
          LoginRequest(mobile: mobile, password: password, fcmToken: fcmToken);
      final response = await _apiService.login(request);
      debugPrint("Ankush Banawade ${response.user.role}");
      debugPrint("Ankush Banawade ${response.token}");
      // Store credentials securely
      await _storage.saveToken(response.token);
      await _storage.saveUser(response.user);

      state = state.copyWith(
        user: response.user,
        isAuthenticated: true,
        isLoading: false,
      );

      // Set user online in Firebase and API
      await FirebaseService.setUserOnline(response.user.id);
      await _apiService.setOnlineStatus();

      // Initialize simple notifications
      await SimpleNotificationService.initialize();

      return true;
    } catch (e) {
      String errorMessage = 'Login failed';

      if (e is DioException) {
        if (e.response?.statusCode == 422) {
          // Handle validation errors
          final data = e.response?.data;
          if (data is Map<String, dynamic>) {
            if (data['message'] != null) {
              errorMessage = data['message'];
            } else if (data['errors'] != null) {
              final errors = data['errors'] as Map<String, dynamic>;
              final firstError = errors.values.first;
              if (firstError is List && firstError.isNotEmpty) {
                errorMessage = firstError.first.toString();
              }
            }
          }
        } else {
          errorMessage = e.response?.data?['message'] ?? 'Login failed';
        }
      } else {
        errorMessage = e.toString();
      }

      state = state.copyWith(
        error: errorMessage,
        isLoading: false,
      );
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);

    try {
      if (state.user != null) {
        // Set user offline in Firebase and API
        await FirebaseService.setUserOffline(state.user!.id);
        await _apiService.setOfflineStatus();
      }

      // Call logout API
      await _apiService.logout();

      // Clear stored data
      await _storage.clearAll();

      state = AuthState();
    } catch (e) {
      // Even if API call fails, clear local data
      await _storage.clearAll();
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
    state = state.copyWith();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
