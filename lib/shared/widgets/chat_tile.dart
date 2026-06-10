import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/chat_model.dart';
import 'cached_profile_image.dart';

class ChatTile extends StatelessWidget {
  final Chat chat;
  final String currentUserId;
  final VoidCallback onTap;

  const ChatTile({
    super.key,
    required this.chat,
    required this.currentUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unreadCount = chat.getUnreadCountForUser(currentUserId);
    final displayName = chat.getDisplayName(currentUserId, []);
    final displayImage = chat.getDisplayImage(currentUserId, []);

    return ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          CachedProfileImage(
            imagePath: displayImage,
            size: 50,
            fallbackText: displayName,
          ),
          if (chat.isPinned)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.push_pin,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: TextStyle(
                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (chat.lastMessage != null)
            Text(
              _formatTime(chat.lastMessage!.timestamp),
              style: TextStyle(
                fontSize: 12,
                color: unreadCount > 0 ?  AppTheme.whatsAppLightGreen : Colors.grey[600],
                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          if (chat.lastMessage != null) ...[
            if (chat.lastMessage!.senderId == currentUserId)
              Icon(
                _getMessageStatusIcon(),
                size: 16,
                color: _getMessageStatusColor(),
              ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _getLastMessageText(),
                style: TextStyle(
                  color: unreadCount > 0 ? Colors.black87 : Colors.grey[600],
                  fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            Expanded(
              child: Text(
                // chat.isGroup ? 'Group created' : 'Tap to start chatting',
                 'Tap to start chatting',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
      trailing: unreadCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.whatsAppLightGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      return DateFormat('HH:mm').format(timestamp);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE').format(timestamp);
    } else {
      return DateFormat('dd/MM/yy').format(timestamp);
    }
  }

  IconData _getMessageStatusIcon() {
    if (chat.lastMessage == null) return Icons.check;

    final status = chat.lastMessage!.getStatusForUser(currentUserId);
    switch (status) {
      case 'sent':
        return Icons.check;
      case 'delivered':
        return Icons.done_all;
      case 'read':
        return Icons.done_all;
      default:
        return Icons.schedule;
    }
  }

  Color _getMessageStatusColor() {
    if (chat.lastMessage == null) return Colors.grey;

    final status = chat.lastMessage!.getStatusForUser(currentUserId);
    switch (status) {
      case 'read':
        return const Color(0xFF34B7F1);
      case 'delivered':
        return Colors.grey[600]!;
      default:
        return Colors.grey;
    }
  }

  String _getLastMessageText() {
    if (chat.lastMessage == null) return '';

    final message = chat.lastMessage!;
    switch (message.type) {
      case 'text':
        return message.text;
      case 'image':
        return '📷 Photo';
      case 'file':
        return '📄 ${message.fileName ?? 'File'}';
      case 'video':
        return '🎥 Video';
      default:
        return message.text;
    }
  }
}
