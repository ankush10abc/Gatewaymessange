import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

class VersionService {
  static final Dio _dio = Dio();

  static Future<bool> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      // Check with your backend for latest version
      final response = await _dio.get('/api/version/check');
      final latestVersion = response.data['latest_version'];
      
      return _isUpdateRequired(currentVersion, latestVersion);
    } catch (e) {
      // If version check fails, continue without update
      return false;
    }
  }

  static bool _isUpdateRequired(String current, String latest) {
    final currentParts = current.split('.').map(int.parse).toList();
    final latestParts = latest.split('.').map(int.parse).toList();
    
    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) {
        return true;
      } else if (latestParts[i] < currentParts[i]) {
        return false;
      }
    }
    
    return false;
  }

  static Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }
}