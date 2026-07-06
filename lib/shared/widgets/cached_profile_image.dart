import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/services/api_service_simple.dart';

class CachedProfileImage extends StatelessWidget {
  final String? imagePath;
  final double size;
  final String fallbackText;
  static final Map<String, bool> _localFileExistsCache = {};

  const CachedProfileImage({
    super.key,
    this.imagePath,
    this.size = 50,
    this.fallbackText = '?',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[300],
      ),
      child: ClipOval(
        child: _buildImage(context),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final path = imagePath?.trim();
    if (path == null || path.isEmpty) {
      return _buildFallback();
    }

    if (_isLocalFilePath(path)) {
      final exists = _localFileExistsCache.putIfAbsent(
        path,
        () => File(path).existsSync(),
      );
      if (exists) {
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallback(),
        );
      }
      return _buildFallback();
    }

    final cacheSize = (size * MediaQuery.of(context).devicePixelRatio).round();
    return CachedNetworkImage(
      imageUrl: _networkImageUrl(path),
      fit: BoxFit.cover,
      width: size,
      height: size,
      memCacheWidth: cacheSize,
      maxWidthDiskCache: cacheSize,
      fadeInDuration: Duration.zero,
      placeholder: (_, __) => Container(color: Colors.grey[300]),
      errorWidget: (_, __, ___) => _buildFallback(),
    );
  }

  bool _isLocalFilePath(String path) {
    if (!path.startsWith('/')) return false;
    return !path.startsWith('/storage/');
  }

  String _networkImageUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('/storage/')) {
      return '${ApiService.baseUrl}$path';
    }
    if (path.startsWith('storage/')) {
      return '${ApiService.baseUrl}/$path';
    }
    return '${ApiService.baseUrl}/storage/$path';
  }

  Widget _buildFallback() {
    return Container(
      color: Colors.grey[400],
      child: Center(
        child: Text(
          fallbackText.isNotEmpty ? fallbackText[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
