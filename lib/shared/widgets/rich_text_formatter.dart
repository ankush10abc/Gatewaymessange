import 'package:flutter/material.dart';

class RichTextFormatter extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;

  const RichTextFormatter({
    super.key,
    required this.text,
    this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: _buildFormattedText(text, baseStyle ?? const TextStyle()),
    );
  }

  TextSpan _buildFormattedText(String text, TextStyle baseStyle) {
    final List<TextSpan> spans = [];
    final RegExp boldRegex = RegExp(r'\*([^*]+)\*');
    final RegExp italicRegex = RegExp(r'_([^_]+)_');
    final RegExp strikeRegex = RegExp(r'~([^~]+)~');
    final RegExp codeRegex = RegExp(r'```([^`]+)```');

    int lastIndex = 0;

    // Process bold text
    for (final match in boldRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: baseStyle,
        ));
      }

      spans.add(TextSpan(
        text: match.group(1),
        style: baseStyle.copyWith(fontWeight: FontWeight.bold),
      ));

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: baseStyle,
      ));
    }

    return TextSpan(children: spans);
  }
}

class RichTextInput extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final Function(String)? onChanged;

  const RichTextInput({
    super.key,
    required this.controller,
    this.hintText = 'Type a message...',
    this.onChanged,
  });

  @override
  _RichTextInputState createState() => _RichTextInputState();
}

class _RichTextInputState extends State<RichTextInput> {
  bool _showFormatting = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_showFormatting)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                _buildFormatButton('*Bold*', () => _insertFormat('*')),
                _buildFormatButton('_Italic_', () => _insertFormat('_')),
                _buildFormatButton('~Strike~', () => _insertFormat('~')),
                _buildFormatButton('```Code```', () => _insertFormat('```')),
              ],
            ),
          ),
        TextField(
          controller: widget.controller,
          maxLines: null,
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: Icon(
                _showFormatting ? Icons.format_clear : Icons.format_bold,
                color: Colors.grey[600],
              ),
              onPressed: () {
                setState(() {
                  _showFormatting = !_showFormatting;
                });
              },
            ),
          ),
          onChanged: widget.onChanged,
        ),
      ],
    );
  }

  Widget _buildFormatButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ),
      ),
    );
  }

  void _insertFormat(String format) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (selection.isValid && !selection.isCollapsed) {
      // Wrap selected text
      final selectedText = text.substring(selection.start, selection.end);
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        '$format$selectedText$format',
      );

      widget.controller.text = newText;
      widget.controller.selection = TextSelection.collapsed(
        offset: selection.end + format.length * 2,
      );
    } else {
      // Insert format markers
      final newText = text.replaceRange(
        selection.start,
        selection.start,
        '$format$format',
      );

      widget.controller.text = newText;
      widget.controller.selection = TextSelection.collapsed(
        offset: selection.start + format.length,
      );
    }
  }
}
