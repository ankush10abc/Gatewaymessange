import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'dart:async';
import '../../core/services/typing_indicator_service.dart';
import '../../core/services/whatsapp_text_parser.dart';

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final Function(String) onSendMessage;
  final VoidCallback onPickImage;
  final VoidCallback onPickFile;
  final Function(bool) onTypingChanged;
  final String? chatId;
  final String? userId;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSendMessage,
    required this.onPickImage,
    required this.onPickFile,
    required this.onTypingChanged,
    this.chatId,
    this.userId,
  });

  @override
  _MessageInputState createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  bool _showEmojiPicker = false;
  bool _isTyping = false;
  bool _showFormatPreview = false;
  final FocusNode _focusNode = FocusNode();
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _typingTimer?.cancel();
    if (_isTyping && widget.chatId != null && widget.userId != null) {
      TypingIndicatorService.clearTyping(widget.chatId!, widget.userId!);
    }
    super.dispose();
  }

  void _onTextChanged() {
    final isCurrentlyTyping = widget.controller.text.trim().isNotEmpty;
    final hasFormatting = _hasFormattingMarkers(widget.controller.text);

    if (isCurrentlyTyping != _isTyping || hasFormatting != _showFormatPreview) {
      setState(() {
        _isTyping = isCurrentlyTyping;
        _showFormatPreview = hasFormatting;
      });
      widget.onTypingChanged(isCurrentlyTyping);

      // Update typing status in Firebase
      if (widget.chatId != null && widget.userId != null) {
        if (isCurrentlyTyping) {
          TypingIndicatorService.setTyping(widget.chatId!, widget.userId!, true);
        }

        // Reset typing timer
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 2), () {
          if (_isTyping) {
            setState(() {
              _isTyping = false;
            });
            widget.onTypingChanged(false);
            TypingIndicatorService.clearTyping(widget.chatId!, widget.userId!);
          }
        });
      }
    }
  }

  bool _hasFormattingMarkers(String text) {
    return RegExp(r'\*[^*]+\*|_[^_]+_|~[^~]+~|`[^`]+`').hasMatch(text);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus && _showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
    }
  }

  void _sendMessage() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSendMessage(text);
    }
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });

    if (_showEmojiPicker) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Send Media',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // _buildAttachmentOption(
                //   icon: Icons.photo_camera,
                //   label: 'Camera',
                //   color: Colors.pink,
                //   onTap: () {
                //     Navigator.pop(context);
                //     widget.onPickImage();
                //     // Open camera
                //   },
                // ),
                _buildAttachmentOption(
                  icon: Icons.photo_library,
                  label: 'Media Library',
                  color: Colors.purple,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onPickImage();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.insert_drive_file,
                  label: 'Document',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onPickFile();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Format Preview
        if (_showFormatPreview && widget.controller.text.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Emoji Button
              IconButton(
                icon: Icon(
                  _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions,
                  color: Colors.grey[600],
                ),
                onPressed: _toggleEmojiPicker,
              ),

              // Text Input
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 80),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),

              // Attachment Button
              IconButton(
                icon: Icon(
                  Icons.attach_file,
                  color: Colors.grey[600],
                ),
                onPressed: _showAttachmentOptions,
              ),

              // Send Button
              if (widget.controller.text.trim().isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  child: CircleAvatar(
                    backgroundColor: const Color(0xFF1dab61),
                    radius: 20,
                    child: IconButton(
                      icon: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: _sendMessage,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Emoji Picker
        if (_showEmojiPicker)
          SizedBox(
            height: 250,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {
                widget.controller.text += emoji.emoji;
              },
            ),
          ),
      ],
    );
  }
}
