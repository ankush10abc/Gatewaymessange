import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:path_provider/path_provider.dart';

class MultiImagePreviewScreen extends StatefulWidget {
  final List<File> imageFiles;
  final VoidCallback onCancel;
  final Function(List<File>) onSend;

  const MultiImagePreviewScreen({
    super.key,
    required this.imageFiles,
    required this.onCancel,
    required this.onSend,
  });

  @override
  State<MultiImagePreviewScreen> createState() => _MultiImagePreviewScreenState();
}

class _MultiImagePreviewScreenState extends State<MultiImagePreviewScreen> {
  late List<File> _images;
  int _currentIndex = 0;
  bool _isCropping = false;
  final _cropController = CropController();
  Uint8List? _currentImageData;

  @override
  void initState() {
    super.initState();
    _images = List.from(widget.imageFiles);
  }

  Future<void> _startCrop() async {
    final imageData = await _images[_currentIndex].readAsBytes();
    setState(() {
      _isCropping = true;
      _currentImageData = imageData;
    });
  }

  Future<void> _onCropped(Uint8List croppedData) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(croppedData);

    setState(() {
      _images[_currentIndex] = file;
      _isCropping = false;
      _currentImageData = null;
    });
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
      if (_currentIndex >= _images.length && _images.isNotEmpty) {
        _currentIndex = _images.length - 1;
      }
    });

    if (_images.isEmpty) {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _isCropping ? () => setState(() => _isCropping = false) : widget.onCancel,
        ),
        title: Text(
          _isCropping ? 'Crop Image' : '${_currentIndex + 1}/${_images.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: _isCropping
            ? [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.white),
                  onPressed: () => _cropController.crop(),
                ),
              ]
            : [
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
      body: _isCropping
          ? Crop(
              controller: _cropController,
              image: _currentImageData!,
              onCropped: _onCropped,
              initialSize: 0.8,
              withCircleUi: false,
              baseColor: Colors.black,
              maskColor: Colors.black.withOpacity(0.5),
            )
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    itemCount: _images.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return InteractiveViewer(
                        child: Center(
                          child: Image.file(_images[index], fit: BoxFit.contain),
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
                    itemCount: _images.length,
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentIndex = index;
                          });
                        },
                        child: Container(
                          width: 80,
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _currentIndex == index
                                  ? const Color(0xFF1dab61)
                                  : Colors.transparent,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(_images[index], fit: BoxFit.cover),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: _isCropping
          ? null
          : FloatingActionButton.extended(
              onPressed: () => widget.onSend(_images),
              backgroundColor: const Color(0xFF1dab61),
              icon: const Icon(Icons.send),
              label: Text('Send ${_images.length}'),
            ),
    );
  }
}
