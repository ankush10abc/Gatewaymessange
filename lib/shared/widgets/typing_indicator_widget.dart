import 'package:flutter/material.dart';

class TypingIndicatorWidget extends StatefulWidget {
  final Map<String, bool> typingUsers;
  final bool isGroupChat;

  const TypingIndicatorWidget({
    super.key,
    required this.typingUsers,
    required this.isGroupChat,
  });

  @override
  State<TypingIndicatorWidget> createState() => _TypingIndicatorWidgetState();
}

class _TypingIndicatorWidgetState extends State<TypingIndicatorWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.typingUsers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTypingDots(),
          const SizedBox(width: 8),
          Text(
            _getTypingText(),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDots() {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final animationValue = (_animation.value - delay).clamp(0.0, 1.0);
            final opacity = (animationValue * 2).clamp(0.0, 1.0);
            
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              child: Opacity(
                opacity: opacity > 1.0 ? 2.0 - opacity : opacity,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  String _getTypingText() {
    final typingUserIds = widget.typingUsers.keys.where((key) => widget.typingUsers[key] == true).toList();
    
    if (typingUserIds.isEmpty) {
      return '';
    }

    if (widget.isGroupChat) {
      if (typingUserIds.length == 1) {
        return '${_getUserName(typingUserIds.first)} is typing...';
      } else if (typingUserIds.length == 2) {
        return '${_getUserName(typingUserIds[0])} and ${_getUserName(typingUserIds[1])} are typing...';
      } else {
        return '${_getUserName(typingUserIds[0])} and ${typingUserIds.length - 1} others are typing...';
      }
    } else {
      return 'typing...';
    }
  }

  String _getUserName(String userId) {
    // In a real implementation, you would fetch the user name from your user data
    // For now, returning a placeholder
    return 'User'; // Replace with actual user name lookup
  }
}