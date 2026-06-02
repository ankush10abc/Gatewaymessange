import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class InternetChecker {
  static Future<bool> hasInternet() async {
    try {
      // Try multiple DNS servers for better mobile data reliability
      final result = await InternetAddress.lookup('google.com').timeout(
        const Duration(seconds: 3),
      );
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}
    
    try {
      // Fallback to Cloudflare DNS
      final result = await InternetAddress.lookup('1.1.1.1').timeout(
        const Duration(seconds: 2),
      );
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> checkAndRedirect(BuildContext context) async {
    final hasConnection = await hasInternet();
    if (!hasConnection && context.mounted) {
      context.go('/no-internet');
    }
    return hasConnection;
  }

  static Future<bool> checkAndShowDialog(BuildContext context) async {
    final hasConnection = await hasInternet();
    if (!hasConnection && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.red),
              SizedBox(width: 8),
              Text('No Internet Connection'),
            ],
          ),
          content: const Text(
            'Please check your internet connection and try again.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    return hasConnection;
  }
}