import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/notification_preferences_service.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({Key? key}) : super(key: key);

  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  late final NotificationPreferencesService _prefsService;
  late NotificationPreferences _preferences;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final dio = Dio();
    final apiService = ApiService(dio);
    _prefsService = NotificationPreferencesService(apiService);
    _preferences = _prefsService.getLocalPreferences();
  }

  Future<void> _updatePreference(NotificationPreferences newPrefs) async {
    setState(() {
      _isLoading = true;
      _preferences = newPrefs;
    });

    try {
      await _prefsService.syncPreferences(newPrefs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preferences saved'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'General',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Enable Notifications'),
                  subtitle: const Text('Receive all notifications'),
                  value: _preferences.globalEnabled,
                  onChanged: (value) {
                    _updatePreference(_preferences.copyWith(globalEnabled: value));
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Alerts',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Sound'),
                  subtitle: const Text('Play sound for notifications'),
                  value: _preferences.soundEnabled,
                  onChanged: _preferences.globalEnabled
                      ? (value) {
                          _updatePreference(_preferences.copyWith(soundEnabled: value));
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Vibration'),
                  subtitle: const Text('Vibrate for notifications'),
                  value: _preferences.vibrationEnabled,
                  onChanged: _preferences.globalEnabled
                      ? (value) {
                          _updatePreference(_preferences.copyWith(vibrationEnabled: value));
                        }
                      : null,
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Message Types',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Group Messages'),
                  subtitle: const Text('Notifications from group chats'),
                  value: _preferences.groupNotifications,
                  onChanged: _preferences.globalEnabled
                      ? (value) {
                          _updatePreference(_preferences.copyWith(groupNotifications: value));
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Private Messages'),
                  subtitle: const Text('Notifications from private chats'),
                  value: _preferences.privateNotifications,
                  onChanged: _preferences.globalEnabled
                      ? (value) {
                          _updatePreference(_preferences.copyWith(privateNotifications: value));
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('@Mentions'),
                  subtitle: const Text('High-priority notifications when mentioned'),
                  value: _preferences.mentionNotifications,
                  onChanged: _preferences.globalEnabled
                      ? (value) {
                          _updatePreference(_preferences.copyWith(mentionNotifications: value));
                        }
                      : null,
                ),
              ],
            ),
    );
  }
}
