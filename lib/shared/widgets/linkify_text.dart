import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget to detect and make URLs clickable in text
class LinkifyText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow? overflow;

  const LinkifyText(
    this.text, {
    Key? key,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final elements = _parseText(text);
    
    return RichText(
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        style: style ?? const TextStyle(color: Colors.black),
        children: elements.map((element) {
          if (element['type'] == 'link') {
            return TextSpan(
              text: element['text'],
              style: linkStyle ?? const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchUrl(element['url']!),
            );
          } else {
            return TextSpan(text: element['text']);
          }
        }).toList(),
      ),
    );
  }

  /// Parse text and identify URLs
  List<Map<String, String>> _parseText(String text) {
    final urlPattern = RegExp(
      r'(https?:\/\/[^\s]+)|(www\.[^\s]+)',
      caseSensitive: false,
    );

    final matches = urlPattern.allMatches(text);
    if (matches.isEmpty) {
      return [{'type': 'text', 'text': text}];
    }

    final elements = <Map<String, String>>[];
    int currentIndex = 0;

    for (final match in matches) {
      // Add text before URL
      if (match.start > currentIndex) {
        elements.add({
          'type': 'text',
          'text': text.substring(currentIndex, match.start),
        });
      }

      // Add URL
      String url = match.group(0)!;
      String displayUrl = url;
      
      // Add https:// if missing
      if (url.startsWith('www.')) {
        url = 'https://$url';
      }

      elements.add({
        'type': 'link',
        'text': displayUrl,
        'url': url,
      });

      currentIndex = match.end;
    }

    // Add remaining text
    if (currentIndex < text.length) {
      elements.add({
        'type': 'text',
        'text': text.substring(currentIndex),
      });
    }

    return elements;
  }

  /// Launch URL
  Future<void> _launchUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }
}
