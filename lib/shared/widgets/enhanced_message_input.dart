import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

import '../../app/theme/app_theme.dart';

class EnhancedMessageInput extends StatefulWidget {
  final TextEditingController controller;
  final Function(String) onSendMessage;
  final VoidCallback? onPickImage;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickFile;
  final Function(bool) onTypingChanged;

  const EnhancedMessageInput({
    super.key,
    required this.controller,
    required this.onSendMessage,
    required this.onPickImage,
    required this.onPickCamera,
    required this.onPickFile,
    required this.onTypingChanged,
  });

  @override
  State<EnhancedMessageInput> createState() => _EnhancedMessageInputState();
}

class _EnhancedMessageInputState extends State<EnhancedMessageInput> {
  bool _showEmojiPicker = false;
  bool _isTyping = false;
  final FocusNode _focusNode = FocusNode();

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
    super.dispose();
  }

  void _onTextChanged() {
    final isCurrentlyTyping = widget.controller.text.trim().isNotEmpty;
    if (_isTyping != isCurrentlyTyping) {
      setState(() {
        _isTyping = isCurrentlyTyping;
      });
      widget.onTypingChanged(isCurrentlyTyping);
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus && _showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
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

  void _onEmojiSelected(Emoji emoji) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      emoji.emoji,
    );
    
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + emoji.emoji.length,
      ),
    );
  }

  void _sendMessage() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSendMessage(text);
      widget.controller.clear();
      setState(() {
        _isTyping = false;
      });
      widget.onTypingChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Attachment button
              IconButton(
                icon: const Icon(Icons.attach_file, color: Colors.grey),
                onPressed: _showAttachmentOptions,
              ),
              
              // Text input
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    children: [
                      // Emoji button
                      IconButton(
                        icon: Icon(
                          _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions,
                          color: Colors.grey[600],
                        ),
                        onPressed: _toggleEmojiPicker,
                      ),
                      
                      // Text field
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          focusNode: _focusNode,
                          maxLines: 5,
                          minLines: 1,
                          style: const TextStyle(color: Colors.black),
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                            hintStyle: TextStyle(color: Colors.grey),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      
                      // Camera button
                      // IconButton(
                      //   icon: Icon(Icons.camera_alt, color: Colors.grey[600]),
                      //   onPressed: widget.onPickImage,
                      // ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(width: 8),
              
              // Send button
              Container(
                decoration: const BoxDecoration(
                  color: AppTheme.whatsAppGreen,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
        
        // Emoji picker
        if (_showEmojiPicker)
          SizedBox(
            height: 400,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) => _onEmojiSelected(emoji),
              config: const Config(
                skinToneConfig: SkinToneConfig(
                  // skinToneDialogBgColor: Colors.white,
                  // skinToneIndicatorColor: Colors.grey,
                  // enableSkinTones: true,
                ),
                checkPlatformCompatibility: true,
                categoryViewConfig: CategoryViewConfig(
                  initCategory: Category.RECENT,
                  // bgColor: Color(0xFFF2F2F2),
                  indicatorColor: AppTheme.whatsAppGreen,
                  iconColor: Colors.grey,
                  iconColorSelected: AppTheme.whatsAppGreen,
                  backspaceColor: AppTheme.whatsAppGreen,

                  recentTabBehavior: RecentTabBehavior.RECENT,
                ),
                emojiViewConfig:EmojiViewConfig(
                   columns: 7,
    emojiSizeMax: 32,
    verticalSpacing: 0,
    horizontalSpacing: 0,
    gridPadding: EdgeInsets.zero,

    recentsLimit: 28,
    replaceEmojiOnLimitExceed: false,
    noRecents: Text(
      'No Recents',
      style: TextStyle(fontSize: 20, color: Colors.black26),
      textAlign: TextAlign.center,
    ),
    loadingIndicator: SizedBox.shrink(),
    // tabIndicatorAnimDuration: kTabScrollDuration,
    // categoryIcons: CategoryIcons(),
    buttonMode: ButtonMode.MATERIAL,

    )


              ),
            ),
          ),
      ],
    );
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
              'Share',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachmentOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: Colors.purple,
                  onTap: () {
                    debugPrint("Ankush banawade Gallery");
                    debugPrint("Ankush banawade Gallery${widget.onPickImage}");
                    Navigator.pop(context);
                    if (widget.onPickImage != null) {

                      widget.onPickImage!();
                    }else{
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'You do not have permission to send attachments in this chat')),
                      );
                    }
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: Colors.pink,
                  onTap: () {
                    Navigator.pop(context);

                    if (widget.onPickCamera != null) {

                      widget.onPickCamera!();
                    }else{
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'You do not have permission to send attachments in this chat')),
                      );
                    }
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.insert_drive_file,
                  label: 'Document',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(context);
                    if (widget.onPickFile != null) {
                      widget.onPickFile!();
                    }else{
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'You do not have permission to send attachments in this chat')),
                      );
                    }
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
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}