import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

class MediaViewerWidget extends StatelessWidget {
  final String imageUrl;
  final String? heroTag;

  const MediaViewerWidget({
    super.key,
    required this.imageUrl,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Implement share functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              // Implement download functionality
            },
          ),
        ],
      ),
      body: PhotoView(
        imageProvider: NetworkImage(imageUrl),
        heroAttributes: heroTag != null 
            ? PhotoViewHeroAttributes(tag: heroTag!)
            : null,
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
        backgroundDecoration: const BoxDecoration(
          color: Colors.black,
        ),
        loadingBuilder: (context, event) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(
            Icons.error,
            color: Colors.white,
            size: 50,
          ),
        ),
      ),
    );
  }
}