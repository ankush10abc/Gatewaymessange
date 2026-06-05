import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../services/api_service_simple.dart';

class NotificationPreferences {
  final bool globalEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool mentionNotifications;
  final bool groupNotifications;
  final bool privateNotifications;
  final Map<String, DateTime?> mutedChats;

  NotificationPreferences({
    this.globalEnabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.mentionNotifications = true,
    this.groupNotifications = true,
    this.privateNotifications = true,
    this.mutedChats = const {},
  });

  Map<String, dynamic> toJson() => {
    'global_enabled': globalEnabled,
    'sound_enabled': soundEnabled,
    'vibration_enabled': vibrationEnabled,
    'mention_notifications': mentionNotifications,
    'group_notifications': groupNotifications,
    'private_notifications': privateNotifications,
    'muted_chats': mutedChats.map((key, value) => MapEntry(key, value?.toIso8601String())),
  };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    final mutedChatsJson = json['muted_chats'] as Map? ?? {};
    final mutedChats = <String, DateTime?>{};
    mutedChatsJson.forEach((key, value) {
      mutedChats[key.toString()] = value != null ? DateTime.parse(value.toString()) : null;
    });

    return NotificationPreferences(
      globalEnabled: json['global_enabled'] ?? true,
      soundEnabled: json['sound_enabled'] ?? true,
      vibrationEnabled: json['vibration_enabled'] ?? true,
      mentionNotifications: json['mention_notifications'] ?? true,
      groupNotifications: json['group_notifications'] ?? true,
      privateNotifications: json['private_notifications'] ?? true,
      mutedChats: mutedChats,
    );
  }

  NotificationPreferences copyWith({
    bool? globalEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? mentionNotifications,
    bool? groupNotifications,
    bool? privateNotifications,
    Map<String, DateTime?>? mutedChats,
  }) {
    return NotificationPreferences(
      globalEnabled: globalEnabled ?? this.globalEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      mentionNotifications: mentionNotifications ?? this.mentionNotifications,
      groupNotifications: groupNotifications ?? this.groupNotifications,
      privateNotifications: privateNotifications ?? this.privateNotifications,
      mutedChats: mutedChats ?? this.mutedChats,
    );
  }
}

class NotificationPreferencesService {
  final ApiService _apiService;
  static late Box _prefsBox;
  static bool _isInitialized = false;

  NotificationPreferencesService(this._apiService);

  static Future<void> initialize() async {
    if (!_isInitialized) {
      _prefsBox = await Hive.openBox('notification_preferences');
      _isInitialized = true;
      debugPrint('✅ Notification preferences initialized');
    }
  }

  /// Get preferences from local cache
  NotificationPreferences getLocalPreferences() {
    final cached = _prefsBox.get('preferences');
    if (cached != null) {
      return NotificationPreferences.fromJson(Map<String, dynamic>.from(cached));
    }
    return NotificationPreferences();
  }

  /// Save preferences locally
  Future<void> saveLocal(NotificationPreferences prefs) async {
    await _prefsBox.put('preferences', prefs.toJson());
  }

  /// Sync preferences with backend
  Future<void> syncPreferences(NotificationPreferences prefs) async {
    try {
      // Note: This requires backend API implementation
      debugPrint('🔔 Syncing notification preferences...');
      // await _apiService.updateNotificationPreferences(prefs.toJson());
      await saveLocal(prefs);
      debugPrint('✅ Preferences synced');
    } catch (e) {
      debugPrint('❌ Failed to sync preferences: $e');
      // Still save locally
      await saveLocal(prefs);
    }
  }

  /// Mute a chat
  Future<void> muteChat(String chatId, {Duration? duration}) async {
    final prefs = getLocalPreferences();
    final mutedUntil = duration != null ? DateTime.now().add(duration) : null;
    final updated = prefs.copyWith(
      mutedChats: {...prefs.mutedChats, chatId: mutedUntil},
    );
    await syncPreferences(updated);
  }

  /// Unmute a chat
  Future<void> unmuteChat(String chatId) async {
    final prefs = getLocalPreferences();
    final mutedChats = Map<String, DateTime?>.from(prefs.mutedChats);
    mutedChats.remove(chatId);
    final updated = prefs.copyWith(mutedChats: mutedChats);
    await syncPreferences(updated);
  }

  /// Check if chat is muted
  bool isChatMuted(String chatId) {
    final prefs = getLocalPreferences();
    final mutedUntil = prefs.mutedChats[chatId];
    
    if (mutedUntil == null) {
      return prefs.mutedChats.containsKey(chatId); // Muted indefinitely
    }
    
    if (DateTime.now().isAfter(mutedUntil)) {
      // Mute period expired, unmute automatically
      unmuteChat(chatId);
      return false;
    }
    
    return true;
  }

  /// Check if notifications should be shown for this chat
  bool shouldShowNotification({
    required String chatId,
    required String chatType,
    bool isMention = false,
  }) {
    final prefs = getLocalPreferences();

    // Check global enabled
    if (!prefs.globalEnabled) return false;

    // Check if chat is muted
    if (isChatMuted(chatId)) {
      // Show notifications for mentions even if muted
      return isMention && prefs.mentionNotifications;
    }

    // Check chat type preferences
    if (chatType == 'group') {
      return prefs.groupNotifications;
    } else {
      return prefs.privateNotifications;
    }
  }
}
