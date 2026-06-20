import 'package:flutter/material.dart';

class WarningSlider extends StatefulWidget {
  const WarningSlider({super.key});

  @override
  _WarningSliderState createState() => _WarningSliderState();
}

class _WarningSliderState extends State<WarningSlider>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  // Nullable — initialized only after first frame when layout is known
  Animation<Offset>? _slideAnimation;
  bool _isEnglish = true;
  final GlobalKey _textKey = GlobalKey();

  // Medium fixed speed — readable on all screen sizes (px/sec)
  static const double _scrollSpeed = 55.0;

  final String englishText =
      "All messages sent on the phone are for parents only. Please do not give mobile phones to children. The school does not assign any work to students via phone.";
  final String hindiText =
      'फोन पर भेजे जाने वाले सभी संदेश केवल अभिभावकों के लिए हैं। कृपया बच्चों को मोबाइल फोन न दें। स्कूल द्वारा फोन पर बच्चों को कोई काम नहीं दिया जाता है।';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 20), // overridden in _startAnimation
      vsync: this,
    );

    // Wait for first frame so layout + RenderBox are available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAnimation();
    });
  }

  void _startAnimation() {
    if (!mounted) return;

    final screenWidth = MediaQuery.of(context).size.width;

    // Measure actual rendered text width via RenderBox
    double contentWidth = screenWidth * 2;
    final renderBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      contentWidth = renderBox.size.width + 16 + 8 + 16 + 50; // padding + icon + spacer
    }

    // Total travel = screen width (start off-right) + content width (end off-left)
    final totalPixels = screenWidth + contentWidth;
    final durationMs = (totalPixels / _scrollSpeed * 1000).round();

    _animationController.duration = Duration(milliseconds: durationMs);

    // Build animation and assign atomically before starting
    final animation = Tween<Offset>(
      begin: Offset(screenWidth / contentWidth, 0.0),
      end: const Offset(-1.0, 0.0),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    ));

    // setState ensures AnimatedBuilder sees the non-null animation
    if (mounted) {
      setState(() {
        _slideAnimation = animation;
      });
    }

    _animationController.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _isEnglish = !_isEnglish;
          _slideAnimation = null; // Reset while next animation is prepared
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _startAnimation());
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: Colors.orange[100],
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          // Guard: show static text until animation is initialized
          child: _slideAnimation == null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange[800], size: 16),
                      const SizedBox(width: 8),
                      Text(
                        _isEnglish ? englishText : hindiText,
                        key: _textKey,
                        style: TextStyle(
                          color: Colors.orange[800],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                      ),
                      const SizedBox(width: 50),
                    ],
                  ),
                )
              : AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) => SlideTransition(
                    position: _slideAnimation!,
                    child: child,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange[800],
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isEnglish ? englishText : hindiText,
                          key: _textKey,
                          style: TextStyle(
                            color: Colors.orange[800],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                        ),
                        const SizedBox(width: 50),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
