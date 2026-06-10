import 'package:flutter/foundation.dart';

class ActiveChatTracker {
  static String? _activeChatId;

  /// Set the currently active chat (when user opens a chat screen)
  static void setActiveChat(String chatId) {
    _activeChatId = chatId;
    debugPrint('📱 Active chat set: $chatId');
  }

  /// Clear the active chat (when user leaves chat screen)
  static void clearActiveChat() {
    debugPrint('📱 Active chat cleared: $_activeChatId');
    _activeChatId = null;
  }

  /// Check if a specific chat is currently active
  static bool isChatActive(String chatId) {
    return _activeChatId == chatId;
  }

  /// Get the current active chat ID
  static String? getActiveChatId() {
    return _activeChatId;
  }
}
