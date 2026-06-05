import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';

class VersionService {
  static final Dio _dio = Dio();

  static Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  static Future<String> getBuildNumber() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.buildNumber;
  }

  static Future<bool> checkForUpdate() async {
    try {
      final currentVersion = await getCurrentVersion();
      // TODO: Check with server for latest version
      // This would typically call an API endpoint to get the latest version
      return false; // No update available for now
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, String>> getAppInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return {
      'appName': packageInfo.appName,
      'packageName': packageInfo.packageName,
      'version': packageInfo.version,
      'buildNumber': packageInfo.buildNumber,
    };
  }
}