import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

class FileDownloadService {
  static final Dio _dio = Dio();

  static Future<String?> downloadFile(String url, String fileName) async {
    try {
      final filePath = '/downloads/$fileName';
      await _dio.download(url, filePath);
      return filePath;
    } catch (e) {
      throw Exception('Download failed: $e');
    }
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class DownloadProgressDialog extends StatefulWidget {
  final String url;
  final String fileName;

  const DownloadProgressDialog({
    super.key,
    required this.url,
    required this.fileName,
  });

  @override
  State<DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<DownloadProgressDialog> {
  double _progress = 0.0;
  bool _isDownloading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final filePath = '/downloads/${widget.fileName}';
      await Dio().download(
        widget.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );
      setState(() {
        _isDownloading = false;
      });
      if (mounted) Navigator.of(context).pop(filePath);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Downloading'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.fileName),
          const SizedBox(height: 16),
          if (_isDownloading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text('${(_progress * 100).toStringAsFixed(0)}%'),
          ] else if (_error != null) ...[
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(height: 8),
            Text('Download failed: $_error'),
          ] else ...[
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(height: 8),
            const Text('Download completed'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_isDownloading ? 'Cancel' : 'Close'),
        ),
      ],
    );
  }
}