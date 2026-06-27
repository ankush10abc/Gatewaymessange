import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class WarningSlider extends StatefulWidget {
  const WarningSlider({super.key});

  @override
  _WarningSliderState createState() => _WarningSliderState();
}

class _WarningSliderState extends State<WarningSlider>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  // True pixel-per-second speed — identical on every device/refresh-rate
  static const double _pixelsPerSecond = 50.0;

  final String _englishText =
      'All messages sent on the phone are for parents only. '
      'Please do not give mobile phones to children. '
      'The school does not assign any work to students via phone.';

  final String _hindiText =
      'फोन पर भेजे जाने वाले सभी संदेश केवल अभिभावकों के लिए हैं। '
      'कृपया बच्चों को मोबाइल फोन न दें। '
      'स्कूल द्वारा फोन पर बच्चों को कोई काम नहीं दिया जाता है।';

  // Current horizontal offset in pixels (starts at screenWidth, moves left)
  double _offsetX = 0;

  // Width of the text+icon row measured after first layout
  double _contentWidth = 0;
  double _screenWidth = 0;

  bool _isEnglish = true;
  bool _layoutReady = false;

  // Wall-clock time of the previous ticker tick
  Duration? _lastElapsed;

  final GlobalKey _textKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);

    // Measure content size after first frame, then start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureAndStart();
    });
  }

  void _measureAndStart() {
    if (!mounted) return;

    final box = _textKey.currentContext?.findRenderObject() as RenderBox?;
    final mediaWidth = MediaQuery.of(context).size.width;

    _screenWidth = mediaWidth;
    // content = icon(16) + gap(8) + text + trailing gap(50) + horizontal padding(32)
    _contentWidth = (box?.size.width ?? mediaWidth * 2) + 16 + 8 + 50 + 32;

    // Start fully off-screen to the right
    _offsetX = _screenWidth;
    _layoutReady = true;
    _lastElapsed = null;

    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final last = _lastElapsed;
    _lastElapsed = elapsed;

    if (last == null) return; // skip first tick — no delta yet

    // Delta in seconds using real wall-clock time → speed is device-independent
    final deltaSeconds = (elapsed - last).inMicroseconds / 1e6;
    final deltaPixels = _pixelsPerSecond * deltaSeconds;

    setState(() {
      _offsetX -= deltaPixels;

      // When text has fully scrolled off-screen to the left, reset & switch language
      if (_offsetX < -_contentWidth) {
        _isEnglish = !_isEnglish;
        _offsetX = _screenWidth; // restart from right edge
        _lastElapsed = null;    // skip next delta to avoid a jump

        // Re-measure after language switch (text length differs)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final box =
              _textKey.currentContext?.findRenderObject() as RenderBox?;
          if (box != null) {
            _contentWidth = box.size.width + 16 + 8 + 50 + 32;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Capture screen width on every build (handles rotation)
    _screenWidth = MediaQuery.of(context).size.width;

    return Container(
      height: 40,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: Colors.orange[100]),
      child: _layoutReady
          ? Transform.translate(
              offset: Offset(_offsetX, 0),
              child: _buildContent(),
            )
          // First frame: render off-screen so we can measure, but invisible
          : Opacity(
              opacity: 0,
              child: _buildContent(),
            ),
    );
  }

  Widget _buildContent() {
    return Row(
      key: _textKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 16),
        Icon(Icons.warning_amber_rounded, color: Colors.orange[800], size: 16),
        const SizedBox(width: 8),
        Text(
          _isEnglish ? _englishText : _hindiText,
          style: TextStyle(
            color: Colors.orange[800],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          softWrap: false,
        ),
        const SizedBox(width: 50),
      ],
    );
  }
}
