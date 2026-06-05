import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

class EnhancedEmojiPicker extends StatelessWidget {
  final Function(Emoji) onEmojiSelected;
  final TextEditingController textController;

  const EnhancedEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    required this.textController,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: EmojiPicker(
        textEditingController: textController,
        onEmojiSelected: (category, emoji) {
          onEmojiSelected(emoji);
        },
      ),
    );
  }
}

class EmojiInputField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final Function(String)? onChanged;
  final VoidCallback? onSend;

  const EmojiInputField({
    super.key,
    required this.controller,
    this.hintText = 'Type a message...',
    this.onChanged,
    this.onSend,
  });

  @override
  _EmojiInputFieldState createState() => _EmojiInputFieldState();
}

class _EmojiInputFieldState extends State<EmojiInputField> {
  bool _showEmojiPicker = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: widget.hintText,
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
                    onChanged: widget.onChanged,
                    onSubmitted: (_) => widget.onSend?.call(),
                  ),
                ),
              ),

              // Send Button
              Container(
                margin: const EdgeInsets.only(left: 4),
                child: CircleAvatar(
                  backgroundColor: widget.controller.text.isNotEmpty
                      ? const Color(0xFF1dab61)
                      : Colors.grey,
                  radius: 24,
                  child: IconButton(
                    icon: Icon(
                      widget.controller.text.isNotEmpty ? Icons.send : Icons.mic,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: widget.controller.text.isNotEmpty
                        ? widget.onSend
                        : () {
                            // Voice message functionality
                          },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Emoji Picker
        if (_showEmojiPicker)
          EnhancedEmojiPicker(
            textController: widget.controller,
            onEmojiSelected: (emoji) {
              // Emoji is automatically added to text controller
              widget.onChanged?.call(widget.controller.text);
            },
          ),
      ],
    );
  }
}
