import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/enums.dart';
import '../../../core/services/api_service_simple.dart';
import '../../../core/storage/storage_service.dart';
import 'package:dio/dio.dart';

class AuthState {
  final LoadingState state;
  final String? errorMessage;
  final bool isAuthenticated;

  AuthState({
    this.state = LoadingState.idle,
    this.errorMessage,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    LoadingState? state,
    String? errorMessage,
    bool? isAuthenticated,
  }) {
    return AuthState(
      state: state ?? this.state,
      errorMessage: errorMessage,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

class AuthViewModel extends StateNotifier<AuthState> {
  late final ApiService _apiService;
  late final StorageService _storageService;

  AuthViewModel() : super(AuthState()) {
    final dio = Dio();
    _apiService = ApiService(dio);
    _storageService = StorageService();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    await _storageService.init();
    final token = await _storageService.getToken();
    if (token != null) {
      _apiService.setAuthToken(token);
      try {
        final user = await _apiService.getCurrentUser();
        state = state.copyWith(
          isAuthenticated: true,
          state: LoadingState.success,
        );
      } catch (e) {
        await _storageService.clearToken();
      }
    }
  }

  Future<bool> login(LoginRequest request) async {
    state = state.copyWith(state: LoadingState.loading);

    try {
      final response = await _apiService.login(request);
      debugPrint("Ankush Banawade $response");
      // Store token and user data
      await _storageService.saveToken(response.token);
      await _storageService.saveUserId(response.user.id);
      await _storageService.saveUser(response.user);

      state = state.copyWith(
        state: LoadingState.success,
        isAuthenticated: true,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        state: LoadingState.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _apiService.logout();
    } catch (e) {
      // Ignore logout errors
    } finally {
      await _storageService.clearAll();
      state = AuthState();
    }
  }
}

final authViewModelProvider = StateNotifierProvider<AuthViewModel, AuthState>(
  (ref) => AuthViewModel(),
);