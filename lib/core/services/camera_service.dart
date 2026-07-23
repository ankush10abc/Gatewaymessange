import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> takePicture() async {
    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      throw Exception('Camera permission denied');
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      throw Exception('Failed to take picture: $e');
    }
  }

  static Future<XFile?> pickFromGallery() async {
    // API 29+: system photo picker handles access — no permission needed
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      throw Exception('Failed to pick image: $e');
    }
  }

  static Future<XFile?> recordVideo() async {
    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      throw Exception('Camera permission denied');
    }

    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      return video;
    } catch (e) {
      throw Exception('Failed to record video: $e');
    }
  }
}

class CameraBottomSheet extends StatelessWidget {
  final Function(XFile) onMediaSelected;

  const CameraBottomSheet({
    super.key,
    required this.onMediaSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Select Media',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildOption(
                icon: Icons.camera_alt,
                label: 'Camera',
                color: Colors.blue,
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final image = await CameraService.takePicture();
                    if (image != null) {
                      onMediaSelected(image);
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                },
              ),
              _buildOption(
                icon: Icons.photo_library,
                label: 'Gallery',
                color: Colors.green,
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final image = await CameraService.pickFromGallery();
                    if (image != null) {
                      onMediaSelected(image);
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                },
              ),
              _buildOption(
                icon: Icons.videocam,
                label: 'Video',
                color: Colors.red,
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final video = await CameraService.recordVideo();
                    if (video != null) {
                      onMediaSelected(video);
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
