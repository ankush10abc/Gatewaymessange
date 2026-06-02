import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MediaViewerScreen extends StatelessWidget {
  final String mediaUrl;
  final String mediaType;
  final String? fileName;

  const MediaViewerScreen({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
    this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          fileName ?? 'Media',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: () {
              _downloadMedia();
            },
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () {
              _shareMedia();
            },
          ),
        ],
      ),
      body: Center(
        child: mediaType == 'image'
            ? PhotoView(
                imageProvider: CachedNetworkImageProvider(mediaUrl),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2,
                heroAttributes: PhotoViewHeroAttributes(tag: mediaUrl),
              )
            : mediaType == 'video'
                ? _buildVideoPlayer()
                : _buildFilePreview(),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return Container(
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.play_circle_outline,
            size: 80,
            color: Colors.white,
          ),
          SizedBox(height: 16),
          Text(
            'Video Player',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          SizedBox(height: 8),
          Text(
            'Tap to play video',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildFilePreview() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getFileIcon(),
            size: 80,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          Text(
            fileName ?? 'Document',
            style: const TextStyle(color: Colors.white, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _downloadMedia,
            icon: const Icon(Icons.download),
            label: const Text('Download'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1dab61),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon() {
    final extension = fileName?.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  void _downloadMedia() {
    // Implement download functionality
  }

  void _shareMedia() {
    // Implement share functionality
  }
}
