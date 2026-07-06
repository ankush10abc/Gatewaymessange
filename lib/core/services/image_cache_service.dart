import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  final Dio _dio = Dio();
  String? _cacheDir;

  Future<void> initialize() async {
    if (_cacheDir != null) return;

    final dir = await getApplicationDocumentsDirectory();
    _cacheDir = '${dir.path}/chat_images';
    await Directory(_cacheDir!).create(recursive: true);
    debugPrint('🖼️ Image cache initialized: $_cacheDir');
  }

  Future<void> _ensureInitialized() async {
    if (_cacheDir == null) {
      await initialize();
    }
  }

  String _getCacheFileName(String url) {
    final hash = md5.convert(utf8.encode(url)).toString();
    final ext = url.split('.').last.split('?').first;
    return '$hash.$ext';
  }

  Future<String?> downloadAndCache(String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) return null;

    try {
      await _ensureInitialized();
      final fileName = _getCacheFileName(imageUrl);
      final filePath = '$_cacheDir/$fileName';
      final file = File(filePath);

      if (await file.exists()) {
        debugPrint('✅ Image cached: $fileName');
        return filePath;
      }

      debugPrint('⬇️ Downloading image: $imageUrl');
      await _dio.download(imageUrl, filePath);
      debugPrint('💾 Image saved: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('❌ Image download failed: $e');
      return imageUrl; // Return original URL as fallback
    }
  }

  Future<String?> cacheLocalFileForUrl(
      String? imageUrl, File sourceFile) async {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    if (!await sourceFile.exists()) return null;

    try {
      await _ensureInitialized();
      final fileName = _getCacheFileName(imageUrl);
      final filePath = '$_cacheDir/$fileName';
      final cachedFile = File(filePath);

      if (await cachedFile.exists()) return filePath;

      await sourceFile.copy(filePath);
      debugPrint('💾 Local image cached: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('❌ Local image cache failed: $e');
      return null;
    }
  }

  Future<void> clearCache() async {
    if (_cacheDir == null) return;
    final dir = Directory(_cacheDir!);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create();
      debugPrint('🧹 Image cache cleared');
    }
  }

  String? getCachedImagePath(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    if (_cacheDir == null) return null;
    if (imageUrl.startsWith('/') && File(imageUrl).existsSync()) {
      return imageUrl; // Already local path
    }

    final fileName = _getCacheFileName(imageUrl);
    final filePath = '$_cacheDir/$fileName';
    final file = File(filePath);

    return file.existsSync() ? filePath : null;
  }
}
