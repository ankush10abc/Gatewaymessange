import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

class MediaViewerScreen extends StatefulWidget {
  final String mediaUrl;
  final String mediaType;
  final String? fileName;
  final String? caption;

  const MediaViewerScreen({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
    this.fileName,
    this.caption,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.fileName ?? 'Media'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareMedia,
          ),
          if (widget.mediaType != 'image')
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _downloadMedia,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildMediaContent(),
          ),
          if (widget.caption != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.black87,
              child: Text(
                widget.caption!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaContent() {
    switch (widget.mediaType.toLowerCase()) {
      case 'image':
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return _buildImageViewer();
      case 'pdf':
        return _buildDocumentViewer();
      case 'video':
      case 'mp4':
      case 'mov':
        return _buildVideoViewer();
      default:
        return _buildFileViewer();
    }
  }

  Widget _buildImageViewer() {
    return PhotoView(
      imageProvider: CachedNetworkImageProvider(widget.mediaUrl),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 2.0,
      heroAttributes: PhotoViewHeroAttributes(tag: widget.mediaUrl),
      loadingBuilder: (context, event) => Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          value: event == null ? 0 : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
        ),
      ),
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, color: Colors.white, size: 64),
            SizedBox(height: 16),
            Text(
              'Failed to load image',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentViewer() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.picture_as_pdf,
            size: 100,
            color: Colors.red,
          ),
          const SizedBox(height: 20),
          Text(
            widget.fileName ?? 'Document',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _openDocument,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Document'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1dab61),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoViewer() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.play_circle_outline,
            size: 100,
            color: Colors.white,
          ),
          SizedBox(height: 20),
          Text(
            'Video Player',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tap to play video',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileViewer() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.insert_drive_file,
            size: 100,
            color: Colors.white,
          ),
          const SizedBox(height: 20),
          Text(
            widget.fileName ?? 'File',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _openFile,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open File'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1dab61),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareMedia() async {
    try {
      await Share.share(
        widget.mediaUrl,
        subject: widget.fileName,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to share media')),
      );
    }
  }

  Future<void> _downloadMedia() async {
    // TODO: Implement download functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Download functionality coming soon')),
    );
  }

  Future<void> _openDocument() async {
    try {
      final uri = Uri.parse(widget.mediaUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch document';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open document')),
      );
    }
  }

  Future<void> _openFile() async {
    try {
      final uri = Uri.parse(widget.mediaUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch file';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open file')),
      );
    }
  }
}
