import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

class MonitoringService {
  static FirebaseAnalytics? _analytics;
  static FirebasePerformance? _performance;
  static FirebaseCrashlytics? _crashlytics;

  static Future<void> initialize() async {
    _analytics = FirebaseAnalytics.instance;
    _performance = FirebasePerformance.instance;
    _crashlytics = FirebaseCrashlytics.instance;

    // Enable crashlytics collection
    await _crashlytics!.setCrashlyticsCollectionEnabled(true);
    
    // Pass all uncaught errors to Crashlytics
    FlutterError.onError = _crashlytics!.recordFlutterFatalError;
    
    // Pass all uncaught asynchronous errors to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      _crashlytics!.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // Analytics Events
  static Future<void> logLogin(String method) async {
    await _analytics?.logLogin(loginMethod: method);
  }

  static Future<void> logMessageSent(String messageType) async {
    await _analytics?.logEvent(
      name: 'message_sent',
      parameters: {'message_type': messageType},
    );
  }

  static Future<void> logChatCreated(String chatType) async {
    await _analytics?.logEvent(
      name: 'chat_created',
      parameters: {'chat_type': chatType},
    );
  }

  static Future<void> logSearch(String query) async {
    await _analytics?.logSearch(searchTerm: query);
  }

  static Future<void> logUserEngagement() async {
    await _analytics?.logEvent(name: 'user_engagement');
  }

  // Performance Monitoring
  static Future<T> tracePerformance<T>(
    String traceName,
    Future<T> Function() operation,
  ) async {
    final trace = _performance?.newTrace(traceName);
    await trace?.start();
    
    try {
      final result = await operation();
      await trace?.stop();
      return result;
    } catch (e) {
      await trace?.stop();
      rethrow;
    }
  }

  // Crash Reporting
  static Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    bool fatal = false,
    Map<String, dynamic>? context,
  }) async {
    await _crashlytics?.recordError(
      exception,
      stack,
      fatal: fatal,
      information: context?.entries.map((e) => '${e.key}: ${e.value}').toList() ?? [],
    );
  }

  static Future<void> setUserIdentifier(String userId) async {
    await _crashlytics?.setUserIdentifier(userId);
    await _analytics?.setUserId(id: userId);
  }

  static Future<void> setCustomKey(String key, dynamic value) async {
    await _crashlytics?.setCustomKey(key, value);
  }

  // User Properties
  static Future<void> setUserProperty(String name, String value) async {
    await _analytics?.setUserProperty(name: name, value: value);
  }

  // Screen Tracking
  static Future<void> setCurrentScreen(String screenName) async {
    await _analytics?.logScreenView(screenName: screenName);
  }
}

class PerformanceMetrics {
  static Future<void> measureAppStartup() async {
    await MonitoringService.tracePerformance('app_startup', () async {
      // App startup logic is measured automatically
    });
  }

  static Future<void> measureMessageDelivery() async {
    await MonitoringService.tracePerformance('message_delivery', () async {
      // Message delivery logic
    });
  }

  static Future<void> measureSearchResponse() async {
    await MonitoringService.tracePerformance('search_response', () async {
      // Search response logic
    });
  }
}