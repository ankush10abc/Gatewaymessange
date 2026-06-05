import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PerformanceOptimizer {
  static Widget optimizedNetworkImage({
    required String imageUrl,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      maxWidthDiskCache: 500,
      maxHeightDiskCache: 500,
      memCacheWidth: 400,
      memCacheHeight: 400,
      placeholder: (context, url) => Container(color: Colors.grey[200]),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[300],
        child: Icon(Icons.broken_image, color: Colors.grey[400]),
      ),
    );
  }

  static Widget optimizedListView({
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    ScrollController? controller,
    bool reverse = false,
  }) {
    return ListView.builder(
      controller: controller,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      reverse: reverse,
      cacheExtent: 1000.0,
      physics: const BouncingScrollPhysics(),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
    );
  }

  static Widget isolateRepaint(Widget child) {
    return RepaintBoundary(child: child);
  }
}
