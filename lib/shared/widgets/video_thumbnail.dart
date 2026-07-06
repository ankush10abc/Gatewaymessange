import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Lightweight video thumbnail widget with actual video frame preview.
/// Shows video_internet.png placeholder when [isOffline] is true.
/// Uses VideoPlayerController for thumbnail generation (cached in memory).
class VideoThumbnail extends StatefulWidget {
  final String videoUrl;

  /// When true, renders the offline placeholder instead of generating thumbnail.
  final bool isOffline;

  const VideoThumbnail({
    super.key,
    required this.videoUrl,
    this.isOffline = false,
  });

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasFailed = false;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isOffline && widget.videoUrl.isNotEmpty) {
      _initThumbnail();
    }
  }

  @override
  void didUpdateWidget(VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If connectivity changed from offline to online, init thumbnail
    if (oldWidget.isOffline && !widget.isOffline && _controller == null) {
      _initThumbnail();
    }
  }

  Future<void> _initThumbnail() async {
    if (_isInitializing) return;
    
    setState(() => _isInitializing = true);

    try {
      debugPrint('🎬 Starting video thumbnail init: ${widget.videoUrl}');
      
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
      
      // Initialize with a 5-second timeout
      await controller.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⏱️ Video thumbnail timeout after 5s');
          controller.dispose();
          throw TimeoutException('Thumbnail generation timeout');
        },
      );

      if (!mounted) {
        debugPrint('⚠️ Widget unmounted, disposing controller');
        controller.dispose();
        return;
      }

      debugPrint('✅ Video thumbnail initialized successfully');
      
      setState(() {
        _controller = controller;
        _isInitialized = true;
        _isInitializing = false;
        _hasFailed = false;
      });
    } catch (e) {
      debugPrint('❌ Video thumbnail generation failed: $e');
      if (mounted) {
        setState(() {
          _hasFailed = true;
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    debugPrint('🗑️ Disposing video thumbnail controller');
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Offline state — show video_internet.png placeholder
    if (widget.isOffline) {
      return _buildOfflinePlaceholder();
    }

    // Online state with video frame ready — show actual thumbnail
    if (_isInitialized && 
        _controller != null && 
        _controller!.value.isInitialized) {
      debugPrint('🎥 Showing actual video frame thumbnail');
      return _buildVideoThumbnail();
    }

    // Thumbnail generation failed or timeout — show styled fallback card
    if (_hasFailed) {
      debugPrint('⚠️ Showing fallback card (failed/timeout)');
      return _buildFallbackCard();
    }

    // Loading state while generating thumbnail — show gradient with small spinner
    debugPrint('⏳ Showing loading state');
    return _buildLoadingState();
  }

  Widget _buildOfflinePlaceholder() {
    return Container(
      width: 250,
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xffe4f3c8),

        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Image.asset(
          'assets/images/video_internet.png',
          width: 220,
          height: 220,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail() {
    return Container(
      width: 250,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 250,
          height: 200,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackCard() {
    return Container(
      width: 250,
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16213E), Color(0xFF0F3460)],
        ),
      ),
      child: Stack(
        children: [
          // Video icon strip at top
          Positioned(
            top: 12,
            left: 12,
            child: Row(
              children: [
                const Icon(Icons.videocam_rounded,
                    color: Colors.white54, size: 18),
                const SizedBox(width: 4),
                Text(
                  'Video',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Centered play button
          const Center(
            child: Icon(
              Icons.play_circle_filled_rounded,
              color: Colors.white,
              size: 56,
            ),
          ),
          // Subtle bottom label
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Tap to play',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      width: 250,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16213E), Color(0xFF0F3460)],
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: Colors.white54,
            strokeWidth: 2.0,
          ),
        ),
      ),
    );
  }
}
