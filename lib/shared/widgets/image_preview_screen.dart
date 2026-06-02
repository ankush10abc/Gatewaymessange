import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ImagePreviewScreen extends StatefulWidget {
  final File imageFile;
  final VoidCallback onCancel;
  final Function(File) onSend;

  const ImagePreviewScreen({
    super.key,
    required this.imageFile,
    required this.onCancel,
    required this.onSend,
  });

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  bool _isSending = false;

  void _handleSend() async {
    if (_isSending) return;
    
    setState(() {
      _isSending = true;
    });

    HapticFeedback.lightImpact();
    widget.onSend(widget.imageFile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen image with zoom/pan
          SizedBox.expand(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 3.0,
              child: Center(
                child: Image.file(
                  widget.imageFile,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // Top overlay with cancel button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(25),
              child: InkWell(
                onTap: widget.onCancel,
                borderRadius: BorderRadius.circular(25),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),

          // Bottom overlay with send button
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            right: 20,
            child: Material(
              color: const Color(0xFF25D366),
              borderRadius: BorderRadius.circular(30),
              elevation: 4,
              child: InkWell(
                onTap: _isSending ? null : _handleSend,
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
              ),
            ),
          ),

          // Loading overlay
          if (_isSending)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Sending image...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}