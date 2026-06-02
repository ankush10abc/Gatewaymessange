import 'package:flutter/material.dart';

class MemoryManager {
  static void clearImageCache() {
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  static void evictImage(String url) {
    final NetworkImage image = NetworkImage(url);
    image.evict();
  }

  static void limitImageCache({int maxImages = 100, int maxBytes = 50 * 1024 * 1024}) {
    imageCache.maximumSize = maxImages;
    imageCache.maximumSizeBytes = maxBytes;
  }

  static void clearCache() {
    clearImageCache();
  }

  static void optimizeMemory() {
    clearImageCache();
    limitImageCache();
  }

  static int get imageCacheSize => imageCache.currentSize;
  static int get imageCacheSizeBytes => imageCache.currentSizeBytes;
}

class OptimizedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const OptimizedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: width,
          height: height,
          color: Colors.grey[300],
          child: const Icon(Icons.error),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}