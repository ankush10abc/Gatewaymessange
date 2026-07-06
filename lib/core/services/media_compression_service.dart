import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

/// Compresses images and videos before upload to reduce send time.
class MediaCompressionService {
  // Image: compress to max 1080px, quality 75 (good balance of size vs quality)
  static const int _imageMaxWidth = 1080;
  static const int _imageMaxHeight = 1080;
  static const int _imageQuality = 75;

  // Video: medium quality preset — reduces size ~60-70% vs original
  static const VideoQuality _videoQuality = VideoQuality.MediumQuality;

  /// Compresses an image file. Returns the compressed file.
  /// Falls back to original if compression fails.
  static Future<File> compressImage(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      final ext = file.path.split('.').last.toLowerCase();

      // Use jpg for compressed output (smaller than png)
      final targetPath =
          '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final CompressFormat format =
          ext == 'png' ? CompressFormat.png : CompressFormat.jpeg;

      final XFile? result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: _imageQuality,
        minWidth: _imageMaxWidth,
        minHeight: _imageMaxHeight,
        format: format,
      );

      if (result == null) {
        debugPrint('⚠️ Image compression returned null, using original');
        return file;
      }

      final originalSize = await file.length();
      final compressedSize = await File(result.path).length();
      debugPrint(
          '🗜️ Image compressed: ${_formatSize(originalSize)} → ${_formatSize(compressedSize)} '
          '(${((1 - compressedSize / originalSize) * 100).toStringAsFixed(0)}% smaller)');

      return File(result.path);
    } catch (e) {
      debugPrint('⚠️ Image compression failed, using original: $e');
      return file; // Safe fallback
    }
  }

  /// Compresses a video file. Returns the compressed file.
  /// Falls back to original if compression fails.
  static Future<File> compressVideo(File file) async {
    try {
      final originalSize = await file.length();
      debugPrint(
          '🎬 Compressing video: ${file.path} (${_formatSize(originalSize)})');

      final MediaInfo? info = await VideoCompress.compressVideo(
        file.path,
        quality: _videoQuality,
        deleteOrigin: false, // Keep original safe
        includeAudio: true,
      );

      if (info == null || info.file == null) {
        debugPrint('⚠️ Video compression returned null, using original');
        return file;
      }

      final compressedSize = await info.file!.length();
      debugPrint(
          '🗜️ Video compressed: ${_formatSize(originalSize)} → ${_formatSize(compressedSize)} '
          '(${((1 - compressedSize / originalSize) * 100).toStringAsFixed(0)}% smaller)');

      return info.file!;
    } catch (e) {
      debugPrint('⚠️ Video compression failed, using original: $e');
      return file; // Safe fallback
    }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
