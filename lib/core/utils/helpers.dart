import 'dart:io';


import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
/// Utility helper functions for common operations like snackbars and validation.
class Helpers {
  /// Displays GetX snackbar with theme-aware colors.
  /// Set isError=true for error styling.
   void showSnackBar(String title, String message,
      {bool isError = false}) {
    // Get.snackbar(
    //   title,
    //   message,
    //   backgroundColor: isError ? Get.theme.colorScheme.error : Get.theme.colorScheme.primary,
    //   colorText: Get.theme.colorScheme.onPrimary,
    // );
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('$title\n$message'),
        backgroundColor: isError ? Colors.red : Colors.blue,
      ),
    );
  }


  /// Checks internet connectivity by attempting DNS lookup.
  /// Returns true if connected, false otherwise.
  Future<bool> checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Formats coordinate to 6 decimal places for display.
  // static String formatCoordinate(double coordinate) {
  //   return coordinate.toStringAsFixed(6);
  // }
  //
  // /// Validates that coordinates are non-null and non-zero.
  // static bool isValidCoordinate(double? lat, double? lng) {
  //   return lat != null && lng != null && lat != 0.0 && lng != 0.0;
  // }

   Helpers._internal();

  static final Helpers instance = Helpers._internal();

  // Global key so we can show snackbars without needing BuildContext anywhere
  final GlobalKey<ScaffoldMessengerState> messengerKey =
  GlobalKey<ScaffoldMessengerState>();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isOffline = false; // guards against repeated snackbars

  void start() {
    // _sub?.cancel();
    // _sub = Connectivity().onConnectivityChanged.listen(_handleChange);
  }

  void _handleChange(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) => r != ConnectivityResult.none);

    if (!hasConnection && !_isOffline) {
      _isOffline = true;
      messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('No internet connection'),
          duration: Duration(days: 1), // stays until we hide it below
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (hasConnection && _isOffline) {
      _isOffline = false;
      messengerKey.currentState?.hideCurrentSnackBar();
      // optional: show a brief "Back online" snackbar here
    }
  }

  void dispose() => _sub?.cancel();

}


// void main() {
//   NetworkWatcher.instance.start();
//   runApp(const MyApp());
// }
//
// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       scaffoldMessengerKey: NetworkWatcher.instance.messengerKey, // key part
//       home: const HomeScreen(),
//     );
//   }
// }