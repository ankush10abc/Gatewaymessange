import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../errors/permission_exception.dart';

class PermissionService {
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      throw PermissionException('Camera permission denied');
    }
    return status.isGranted;
  }

  Future<bool> requestStoragePermission() async {
    final status = await Permission.storage.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      PermissionStatus status;

      if (sdkInt >= 33) {  // Android 13+
        // Granular media perms for images/videos/audio; adjust as needed
        final Map<Permission, PermissionStatus> results = await [
          Permission.photos,
          Permission.videos,
          Permission.audio,  // Or use manageExternalStorage for all files (risky for Play)
        ].request();
        status = results.values.every((s) => s.isGranted)
            ? PermissionStatus.granted
            : PermissionStatus.denied;
      } else {
        status = await Permission.storage.request();
      }

      if (!status.isGranted) {

        return false;
      }
      throw PermissionException('Storage permission denied');
    }
    return status.isGranted;
  }

  Future<bool> requestLocationPermission() async {
    final status = await Permission.locationWhenInUse.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      throw PermissionException('Location permission denied');
    }
    return status.isGranted;
  }

  Future<bool> requestBackgroundLocationPermission() async {
    final whenInUse = await Permission.locationWhenInUse.status;
    if (!whenInUse.isGranted) {
      await requestLocationPermission();
    }
    
    final status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<void> openAppSettings() async {
    await openAppSettings();
  }
}
