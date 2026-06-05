import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationPermissionHelper {
  /// Requests POST_NOTIFICATIONS permission on Android 13+ (API 33+).
  /// Returns true if granted, false otherwise.
  static Future<bool> request() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) return false;

    final result = await Permission.notification.request();
    return result.isGranted;
  }

  /// Shows a rationale dialog before requesting, then requests the permission.
  /// Returns true if granted.
  static Future<bool> requestWithRationale(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(context);
      return false;
    }

    final shouldRequest = await _showRationaleDialog(context);
    if (!shouldRequest) return false;

    final result = await Permission.notification.request();

    if (result.isPermanentlyDenied && context.mounted) {
      await _showSettingsDialog(context);
    }

    return result.isGranted;
  }

  static Future<bool> _showRationaleDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Enable Notifications'),
            content: const Text(
                'Allow notifications to receive messages and important updates.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not Now'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Allow'),
              ),
            ],
          ),
        ) ??
        false;
  }

  static Future<void> _showSettingsDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Notifications Blocked'),
        content: const Text(
            'Notifications are permanently blocked. Enable them in app settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
