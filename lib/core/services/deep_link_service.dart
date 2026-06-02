import 'package:flutter/material.dart';

class DeepLinkService {
  static String? _pendingMessage;

  static void setPendingMessage(String? message) {
    debugPrint('Deep link received:setPendingMessage $message');
    _pendingMessage = message;
  }

  static String? getPendingMessage() {
    final message = _pendingMessage;
    // _pendingMessage = null;
    return message;
  }

  static bool hasPendingMessage() {
    return _pendingMessage != null && _pendingMessage!.isNotEmpty;
  }

  static String decodeMessage(String encodedMessage) {
    return Uri.decodeFull(encodedMessage);
  }
}
