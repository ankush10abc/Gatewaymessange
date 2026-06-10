import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service_simple.dart';
import 'dart:io';

class UpdateInfo {
  final bool updateAvailable;
  final String latestVersion;
  final String updateType; // 'force' or 'optional'
  final String? releaseNotes;
  final String? downloadUrl;
  final String? directApkUrl;
  final double? apkSizeMb;
  final bool canSkip;
  final bool isCurrentSupported;
  final String? forceUpdateMessage;

  UpdateInfo({
    required this.updateAvailable,
    required this.latestVersion,
    required this.updateType,
    this.releaseNotes,
    this.downloadUrl,
    this.directApkUrl,
    this.apkSizeMb,
    required this.canSkip,
    required this.isCurrentSupported,
    this.forceUpdateMessage,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return UpdateInfo(
      updateAvailable: data['update_available'] ?? false,
      latestVersion: data['latest_version'] ?? '',
      updateType: data['update_type'] ?? 'optional',
      releaseNotes: data['release_notes'],
      downloadUrl: data['download_url'],
      directApkUrl: data['direct_apk_url'],
      apkSizeMb: data['apk_size_mb']?.toDouble(),
      canSkip: data['can_skip'] ?? true,
      isCurrentSupported: data['is_current_supported'] ?? true,
      forceUpdateMessage: data['force_update_message'],
    );
  }

  bool get isForceUpdate => updateType == 'force';
  bool get isOptionalUpdate => updateType == 'optional';
}

class UpdateService {
  final ApiService _apiService;
  PackageInfo? _packageInfo;

  UpdateService(this._apiService);

  /// Check for app updates
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      _packageInfo ??= await PackageInfo.fromPlatform();
      final currentVersion = _packageInfo!.version;

      debugPrint('📱 Checking for updates - Current version: $currentVersion');

      final response = await _apiService.checkAppVersion(
        currentVersion: currentVersion,
      );

      // Validate response structure
      if (response['success'] != true) {
        debugPrint('⚠️ Update check response not successful');
        return null;
      }

      final updateInfo = UpdateInfo.fromJson(response);
      
      if (updateInfo.updateAvailable) {
        debugPrint('🆕 Update available: ${updateInfo.latestVersion} (${updateInfo.updateType})');
      } else {
        debugPrint('✅ App is up to date');
      }

      return updateInfo;
    } catch (e) {
      debugPrint('❌ Update check failed: $e');
      return null;
    }
  }

  /// Show update dialog
  void showUpdateDialog(BuildContext context, UpdateInfo updateInfo) {
    final isForce = updateInfo.isForceUpdate;

    showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (context) => WillPopScope(
        onWillPop: () async => !isForce,
        child: AlertDialog(
          title: Text(
            isForce ? '⚠️ Update Required' : '🆕 Update Available',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isForce && updateInfo.forceUpdateMessage != null) ...[
                  Text(
                    updateInfo.forceUpdateMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text('Version ${updateInfo.latestVersion} is now available.'),
                const SizedBox(height: 8),
                Text(
                  'Current version: ${_packageInfo?.version ?? 'Unknown'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (updateInfo.apkSizeMb != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Size: ${updateInfo.apkSizeMb!.toStringAsFixed(1)} MB',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                if (updateInfo.releaseNotes != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'What\'s New:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    updateInfo.releaseNotes!,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (updateInfo.canSkip && !isForce)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later'),
              ),
            if (updateInfo.directApkUrl != null && Platform.isAndroid)
              TextButton(
                onPressed: () {
                  _launchUrl(updateInfo.directApkUrl!);
                  if (!isForce) Navigator.pop(context);
                },
                child: const Text('Download APK'),
              ),
            ElevatedButton(
              onPressed: () {
                if (updateInfo.downloadUrl != null) {
                  _launchUrl(updateInfo.downloadUrl!);
                }
                if (!isForce) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isForce ? Colors.red : null,
              ),
              child: Text(
                Platform.isAndroid ? 'Update from Play Store' : 'Update from App Store',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Launch URL
  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('❌ Could not launch $url');
      }
    } catch (e) {
      debugPrint('❌ Error launching URL: $e');
    }
  }

  /// Check and show update dialog automatically
  Future<void> checkAndShowUpdate(BuildContext context) async {
    final updateInfo = await checkForUpdate();
    if (updateInfo != null && updateInfo.updateAvailable && context.mounted) {
      showUpdateDialog(context, updateInfo);
    }
  }

  /// Get current app version
  Future<String> getCurrentVersion() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!.version;
  }

  /// Get current build number
  Future<String> getCurrentBuildNumber() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!.buildNumber;
  }
}
