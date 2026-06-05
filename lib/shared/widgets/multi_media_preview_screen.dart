import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:path_provider/path_provider.dart';

class MultiMediaPreviewScreen extends StatefulWidget {
  final List<File> mediaFiles;
  final VoidCallback onCancel;
  final Function(List<File>) onSend;

  const MultiMediaPreviewScreen({
    super.key,
    required this.mediaFiles,
    required this.onCancel,
    required this.onSend,
  });

  @override
  State<MultiMediaPreviewScreen> createState() => _MultiMediaPreviewScreenState();
}

class _MultiMediaPreviewScreenState extends State<MultiMediaPreviewScreen> {
  late List<File> _files;
  int _currentIndex = 0;
  bool _isSending = false;
  bool _isCropping = false;
  final _cropController = CropController();
  Uint8List? _currentImageData;

  @override
  void initState() {
    super.initState();
    _files = List.from(widget.mediaFiles);
  }

  Future<void> _startCrop() async {
    setState(() => _isCropping = true);
    _currentImageData = await _files[_currentIndex].readAsBytes();
  }

  Future<void> _saveCroppedImage(Uint8List croppedData) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(croppedData);
    setState(() {
      _files[_currentIndex] = file;
      _isCropping = false;
    });
  }

  void _removeImage(int index) {
    setState(() {
      _files.removeAt(index);
      if (_files.isEmpty) {
        widget.onCancel();
      } else if (_currentIndex >= _files.length) {
        _currentIndex = _files.length - 1;
      }
    });
  }

  void _handleSend() {
    if (_isSending || _files.isEmpty) return;
    setState(() => _isSending = true);
    widget.onSend(_files);
  }

  @override
  Widget build(BuildContext context) {
    if (_isCropping && _currentImageData != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: const Color(0xFF075E54),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => setState(() => _isCropping = false),
          ),
          title: const Text('Crop Image', style: TextStyle(color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.white),
              onPressed: () => _cropController.crop(),
            ),
          ],
        ),
        body: Crop(
          image: _currentImageData!,
          controller: _cropController,
          onCropped: _saveCroppedImage,
          aspectRatio: null,
          initialSize: 0.8,
          withCircleUi: false,
          baseColor: Colors.black,
          maskColor: Colors.black.withOpacity(0.5),
          cornerDotBuilder: (size, edgeAlignment) => const DotControl(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: widget.onCancel,
        ),
        title: Text(
          '${_currentIndex + 1}/${_files.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.crop, color: Colors.white),
            onPressed: _startCrop,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: () => _removeImage(_currentIndex),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              itemCount: _files.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  child: Center(
                    child: Image.file(_files[index], fit: BoxFit.contain),
                  ),
                );
              },
            ),
          ),
          Container(
            height: 100,
            color: Colors.black87,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _files.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = index),
                  child: Container(
                    width: 80,
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _currentIndex == index
                            ? const Color(0xFF25D366)
                            : Colors.transparent,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(_files[index], fit: BoxFit.cover),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              top: 16,
            ),
            color: Colors.black87,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_files.length} ${_files.length == 1 ? 'photo' : 'photos'} selected',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                FloatingActionButton(
                  onPressed: _isSending ? null : _handleSend,
                  backgroundColor: const Color(0xFF25D366),
                  child: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
