import 'package:flutter/services.dart';

/// Controls the native TelemetryForegroundService via MethodChannel.
/// start() on login — shows persistent background notification.
/// stop() on logout — removes notification immediately.
class VerificationCheckController {
  static const _channel = MethodChannel('com.company.gateway/telemetry');

  // Called on login — starts TelemetryForegroundService notification
  static Future<void> start() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (_) {}
  }

  // Called on logout / 401 — stops TelemetryForegroundService and removes notification
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (_) {}
  }
}
