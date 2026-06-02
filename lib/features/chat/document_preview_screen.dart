import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class DocumentPreviewService {
  static Future<void> previewDocument(String url, String fileName) async {
    final extension = fileName.split('.').last.toLowerCase();

    switch (extension) {
      case 'pdf':
        await _openPdfViewer(url, fileName);
        break;
      case 'doc':
      case 'docx':
        await _openDocumentViewer(url, fileName);
        break;
      case 'txt':
        await _openTextViewer(url, fileName);
        break;
      default:
        await _downloadAndOpen(url, fileName);
    }
  }

  static Future<void> _openPdfViewer(String url, String fileName) async {
    // For now, download and open with system app
    await _downloadAndOpen(url, fileName);
  }

  static Future<void> _openDocumentViewer(String url, String fileName) async {
    await _downloadAndOpen(url, fileName);
  }

  static Future<void> _openTextViewer(String url, String fileName) async {
    try {
      final response = await Dio().get(url);
      final content = response.data.toString();

      // Show in a dialog or navigate to text viewer screen
      // For now, download and open
      await _downloadAndOpen(url, fileName);
    } catch (e) {
      await _downloadAndOpen(url, fileName);
    }
  }

  static Future<void> _downloadAndOpen(String url, String fileName) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      throw Exception('Cannot open document: $e');
    }
  }
}

class DocumentPreviewScreen extends StatefulWidget {
  final String documentUrl;
  final String fileName;

  const DocumentPreviewScreen({
    super.key,
    required this.documentUrl,
    required this.fileName,
  });

  @override
  _DocumentPreviewScreenState createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  bool _isLoading = true;
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      final extension = widget.fileName.split('.').last.toLowerCase();

      if (extension == 'txt') {
        final response = await Dio().get(widget.documentUrl);
        setState(() {
          _content = response.data.toString();
          _isLoading = false;
        });
      } else {
        // For other formats, show preview unavailable
        setState(() {
          _error = 'Preview not available for this file type';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load document: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _downloadFile(),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareFile(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => DocumentPreviewService.previewDocument(
                          widget.documentUrl,
                          widget.fileName,
                        ),
                        child: const Text('Open with External App'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(_content ?? ''),
                ),
    );
  }

  void _downloadFile() async {
    try {
      await DocumentPreviewService.previewDocument(
        widget.documentUrl,
        widget.fileName,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  void _shareFile() {
    // Implement share functionality
  }
}
