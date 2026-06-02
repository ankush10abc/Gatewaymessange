import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../storage/storage_service.dart';
import '../services/api_service_simple.dart';
import '../utils/internet_checker.dart';

class AppLifecycleManager extends WidgetsBindingObserver {
  final WidgetRef ref;
  final StorageService _storage = StorageService();
  late final ApiService _apiService;

  AppLifecycleManager(this.ref) {
    final dio = Dio();
    _apiService = ApiService(dio);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        _validateTokenOnResume();
        break;
      case AppLifecycleState.paused:
        _setUserOffline();
        break;
      case AppLifecycleState.detached:
        _setUserOffline();
        break;
      default:
        break;
    }
  }

  Future<void> _validateTokenOnResume() async {
    try {
      bool hasInternet =   await InternetChecker.hasInternet();
      if(hasInternet){
        final token = await _storage.getToken();
        if (token != null) {
          // Verify token is still valid
          await _apiService.getCurrentUser();
          // Set user online
          await _apiService.setOnlineStatus();
        }
      }

    } catch (e) {
      // Token invalid, clear storage and logout
      bool hasInternet =   await InternetChecker.hasInternet();
      if(hasInternet)
      await _storage.clearAll();
      // Navigate to login screen
      // This should be handled by the auth provider
    }
  }

  Future<void> _setUserOffline() async {
    try {
      await _apiService.setOfflineStatus();
    } catch (e) {
      // Ignore errors when setting offline status
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}