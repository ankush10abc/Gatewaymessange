import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DocumentViewerWidget extends StatelessWidget {
  final String documentUrl;
  final String fileName;
  final String fileType;

  const DocumentViewerWidget({
    super.key,
    required this.documentUrl,
    required this.fileName,
    required this.fileType,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openInExternalApp(),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _downloadFile(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getFileIcon(),
              size: 100,
              color: _getFileColor(),
            ),
            const SizedBox(height: 20),
            Text(
              fileName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              fileType.toUpperCase(),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _openInExternalApp,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open in External App'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _downloadFile,
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon() {
    switch (fileType.toLowerCase()) {
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

  Color _getFileColor() {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'txt':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Future<void> _openInExternalApp() async {
    final uri = Uri.parse(documentUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Handle error
      debugPrint('Could not launch $documentUrl');
    }
  }

  Future<void> _downloadFile() async {
    // Implement download functionality
    // This would typically involve downloading the file to the device's storage
    debugPrint('Downloading file: $fileName');
  }
}