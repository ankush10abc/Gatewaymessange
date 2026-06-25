import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

class WhatsAppTextParser {
  // URL regex pattern - detects http/https URLs and www links

  static final RegExp _urlPattern = RegExp(
  r'(https?://[^\s]+)|(www\.[^\s]+)|([a-zA-Z0-9][a-zA-Z0-9-]*(\.[a-zA-Z0-9][a-zA-Z0-9-]*)*\.(com|in)(?:/[^\s]*)?\b)',
  caseSensitive: false,
);

  // Email regex pattern - detects email addresses
  static final RegExp _emailPattern = RegExp(
    r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}',
    caseSensitive: false,
  );

  // Combined pattern to detect both URLs and emails
  static final RegExp _urlOrEmailPattern = RegExp(
    r'([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})|(https?://[^\s]+)|(www\.[^\s]+)|([a-zA-Z0-9][a-zA-Z0-9-]*(\.[a-zA-Z0-9][a-zA-Z0-9-]*)*\.(com|in)(?:/[^\s]*)?\b)',
    caseSensitive: false,
  );

  static TextSpan parseText(String text, {TextStyle? baseStyle}) {
    final List<TextSpan> spans = [];
    final List<_TextSegment> segments = _parseSegments(text);

    for (final segment in segments) {
      // Check if segment contains URLs
      /*if (_urlPattern.hasMatch(segment.text)) {
        spans.addAll(_parseUrlsInSegment(segment, baseStyle));
      }*/
      if (_urlOrEmailPattern.hasMatch(segment.text)) {
        spans.addAll(_parseUrlsAndEmailsInSegment(segment, baseStyle));
      } else {
        spans.add(TextSpan(
          text: segment.text,
          style: _getStyleForType(segment.type, baseStyle),
        ));
      }
    }

    return TextSpan(children: spans);
  }

  // Parse URLs within a text segment and create clickable links
  static List<TextSpan> _parseUrlsInSegment(_TextSegment segment, TextStyle? baseStyle) {
    final List<TextSpan> spans = [];
    final String text = segment.text;
    int lastIndex = 0;

    for (final match in _urlPattern.allMatches(text)) {
      // Add text before URL
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: _getStyleForType(segment.type, baseStyle),
        ));
      }

      // Add clickable URL
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: _getStyleForType(segment.type, baseStyle).copyWith(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _launchURL(url),
      ));

      lastIndex = match.end;
    }

    // Add remaining text after last URL
    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: _getStyleForType(segment.type, baseStyle),
      ));
    }

    return spans;
  }
  static List<TextSpan> _parseUrlsAndEmailsInSegment(
      _TextSegment segment, TextStyle? baseStyle) {
    final List<TextSpan> spans = [];
    final String text = segment.text;
    int lastIndex = 0;

    for (final match in _urlOrEmailPattern.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: _getStyleForType(segment.type, baseStyle),
        ));
      }

      final matchedText = match.group(0)!;
      final bool isEmail = _emailPattern.hasMatch(matchedText) &&
          !matchedText.startsWith('http') &&
          !matchedText.startsWith('www');

      spans.add(TextSpan(
        text: matchedText,
        style: _getStyleForType(segment.type, baseStyle).copyWith(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            if (isEmail) {
              _launchEmail(matchedText);
            } else {
              _launchURL(matchedText);
            }
          },
      ));

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: _getStyleForType(segment.type, baseStyle),
      ));
    }

    return spans;
  }

  // Launch email app with pre-filled recipient
  static Future<void> _launchEmail(String email) async {
    try {
      final Uri emailUri = Uri(
        scheme: 'mailto',
        path: email,
      );

      bool launched = false;

      try {
        launched = await launchUrl(emailUri);
      } catch (e) {
        debugPrint('⚠️ mailto launch failed: $e');
      }

      if (!launched) {
        // Fallback: open Gmail web
        final Uri gmailUri = Uri.parse(
          'https://mail.google.com/mail/?view=cm&to=$email',
        );
        try {
          launched = await launchUrl(gmailUri, mode: LaunchMode.externalApplication);
        } catch (e) {
          debugPrint('⚠️ Gmail web fallback failed: $e');
        }
      }

      if (!launched) {
        debugPrint('❌ Could not launch email: $email');
      }
    } catch (e) {
      debugPrint('❌ Error launching email: $e');
    }
  }


  // Launch URL in browser
  static Future<void> _launchURL(String urlString) async {
    try {
      // Add https:// prefix if missing
      String url = urlString;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final Uri uri = Uri.parse(url);

      // Try to launch with different modes for better compatibility
      bool launched = false;

      // First try: platformDefault (most compatible)
      try {
        launched = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
        );
      } catch (e) {
        debugPrint('⚠️ platformDefault failed: $e');
      }

      // Second try: externalNonBrowserApplication
      if (!launched) {
        try {
          launched = await launchUrl(
            uri,
            mode: LaunchMode.externalNonBrowserApplication,
          );
        } catch (e) {
          debugPrint('⚠️ externalNonBrowserApplication failed: $e');
        }
      }

      // Third try: inAppBrowserView (fallback)
      if (!launched) {
        try {
          launched = await launchUrl(
            uri,
            mode: LaunchMode.inAppBrowserView,
          );
        } catch (e) {
          debugPrint('⚠️ inAppBrowserView failed: $e');
        }
      }

      if (!launched) {
        debugPrint('❌ Could not launch URL: $url');
      }
    } catch (e) {
      debugPrint('❌ Error launching URL: $e');
    }
  }

  static List<_TextSegment> _parseSegments(String text) {
    final List<_TextSegment> segments = [];
    final RegExp patterns = RegExp(
      r'\*([^*]+)\*|_([^_]+)_|~([^~]+)~|`([^`]+)`',
      multiLine: true,
    );

    int lastIndex = 0;

    for (final match in patterns.allMatches(text)) {
      // Add text before match
      if (match.start > lastIndex) {
        segments.add(_TextSegment(
          text.substring(lastIndex, match.start),
          _TextType.normal,
        ));
      }

      // Add formatted text
      if (match.group(1) != null) {
        // Bold: *text*
        segments.add(_TextSegment(match.group(1)!, _TextType.bold));
      } else if (match.group(2) != null) {
        // Italic: _text_
        segments.add(_TextSegment(match.group(2)!, _TextType.italic));
      } else if (match.group(3) != null) {
        // Strikethrough: ~text~
        segments.add(_TextSegment(match.group(3)!, _TextType.strikethrough));
      } else if (match.group(4) != null) {
        // Monospace: `text`
        segments.add(_TextSegment(match.group(4)!, _TextType.monospace));
      }

      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < text.length) {
      segments.add(_TextSegment(
        text.substring(lastIndex),
        _TextType.normal,
      ));
    }

    return segments;
  }

  static TextStyle _getStyleForType(_TextType type, TextStyle? baseStyle) {
    final base = baseStyle ?? const TextStyle();

    switch (type) {
      case _TextType.bold:
        return base.copyWith(fontWeight: FontWeight.bold);
      case _TextType.italic:
        return base.copyWith(fontStyle: FontStyle.italic);
      case _TextType.strikethrough:
        return base.copyWith(decoration: TextDecoration.lineThrough);
      case _TextType.monospace:
        return base.copyWith(
          fontFamily: 'monospace',
          backgroundColor: Colors.grey[200],
        );
      case _TextType.normal:
      default:
        return base;
    }
  }
}

class _TextSegment {
  final String text;
  final _TextType type;

  _TextSegment(this.text, this.type);
}

enum _TextType {
  normal,
  bold,
  italic,
  strikethrough,
  monospace,
}

class FormattedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const FormattedText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: WhatsAppTextParser.parseText(text, baseStyle: style),
      textAlign: textAlign ?? TextAlign.start,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

class FormattingPreviewInput extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final Function(String)? onChanged;
  final VoidCallback? onSend;
  final Function(File, String)? onFileSelected;

  const FormattingPreviewInput({
    super.key,
    required this.controller,
    this.hintText = 'Type a message...',
    this.onChanged,
    this.onSend,
    this.onFileSelected,
  });

  @override
  _FormattingPreviewInputState createState() => _FormattingPreviewInputState();
}

class _FormattingPreviewInputState extends State<FormattingPreviewInput> {
  bool _showPreview = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasFormatting = _hasFormattingMarkers(widget.controller.text);
    if (hasFormatting != _showPreview) {
      setState(() {
        _showPreview = hasFormatting;
      });
    }
    widget.onChanged?.call(widget.controller.text);
  }

  bool _hasFormattingMarkers(String text) {
    return RegExp(r'\*[^*]+\*|_[^_]+_|~[^~]+~|`[^`]+`').hasMatch(text);
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.blue),
              title: const Text('Document'),
              onTap: () {
                Navigator.pop(context);
                _pickDocument();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('Photos & videos'),
              onTap: () {
                Navigator.pop(context);
                _pickMedia();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.red),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickCamera();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'xls', 'xlsx'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      widget.onFileSelected?.call(file, 'document');
    }
  }

  Future<void> _pickMedia() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCamera() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Record Video'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (image != null) {
      final file = File(image.path);
      widget.onFileSelected?.call(file, 'image');
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    final XFile? video = await _imagePicker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 5),
    );

    if (video != null) {
      final file = File(video.path);
      widget.onFileSelected?.call(file, 'video');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showPreview && widget.controller.text.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preview:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                FormattedText(
                  widget.controller.text,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add, color: Color(0xFF1dab61)),
                onPressed: _showAttachmentOptions,
              ),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: Color(0xFF1dab61)),
                onPressed: widget.controller.text.isNotEmpty ? widget.onSend : null,
              ),
            ],
          ),
        ),
        if (_showPreview)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Formatting: *bold* _italic_ ~strike~ `code`',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          ),
      ],
    );
  }
}
