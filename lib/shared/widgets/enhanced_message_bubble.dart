import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/message_model.dart';
import 'media_viewer_widget.dart';
import 'document_viewer_widget.dart';

class EnhancedMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool isGroupChat;
  final bool showTime;
  final Function(Message) onReply;
  final Function(Message) onCopy;
  final Function(Message) onForward;
  final Function(Message)? onReplyTap;
  final String? currentUserId;

  const EnhancedMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isGroupChat,
    required this.showTime,
    required this.onReply,
    required this.onCopy,
    required this.onForward,
    this.onReplyTap,
    this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showTime) _buildTimeHeader(),
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe && isGroupChat) _buildSenderAvatar(),
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _showMessageOptions(context),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    margin: EdgeInsets.only(
                      left: isMe ? 50 : 0,
                      right: isMe ? 0 : 50,
                      bottom: 2,
                    ),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: Radius.circular(isMe ? 12 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe && isGroupChat) _buildSenderName(),
                        if (message.isForwarded) _buildForwardedLabel(),
                        if (message.replyToMessage != null) _buildReplyPreview(),
                        _buildMessageContent(),
                        _buildMessageFooter(),
                      ],
                    ),
                  ),
                ),
              ),
              if (isMe) _buildMessageStatus(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _formatDate(message.timestamp),
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSenderAvatar() {
    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 4),
      child: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.grey[300],
        backgroundImage: message.profile_picture_url != null
            ? NetworkImage(message.profile_picture_url.toString())
            : null,
        child: message.profile_picture_url == null
            ? Text(
                (message.senderName ?? 'U')[0].toUpperCase(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              )
            : null,
      ),
    );
  }

  Widget _buildSenderName() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        message.senderName ?? 'Unknown',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _getSenderColor(message.senderId),
        ),
      ),
    );
  }

  Widget _buildForwardedLabel() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.forward,
            size: 14,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 4),
          Text(
            'Forwarded',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    final replyMessage = message.replyToMessage!;
    return GestureDetector(
      onTap: () => onReplyTap?.call(replyMessage),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: isMe ? Colors.green : Colors.grey,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              replyMessage.senderName ?? 'Unknown',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _getSenderColor(replyMessage.senderId),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (replyMessage.isImageMessage) _buildReplyImagePreview(replyMessage),
                Expanded(
                  child: Text(
                    _getReplyText(replyMessage),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyImagePreview(Message replyMessage) {
    return Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          replyMessage.fileUrl ?? replyMessage.file_path ?? '',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey[200],
            child: const Icon(Icons.image, size: 20, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageContent() {
    switch (message.type) {
      case 'image':
        return _buildImageContent();
      case 'pdf':
      case 'doc':
      case 'docx':
        return _buildDocumentContent();
      default:
        return _buildTextContent();
    }
  }

  Widget _buildTextContent() {
    if (message.text.isEmpty) return const SizedBox.shrink();
    
    return SelectableText(
      message.text,
      style: const TextStyle(fontSize: 16),
    );
  }

  Widget _buildImageContent() {
    final imageUrl = message.fileUrl ?? message.file_path ?? '';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _openMediaViewer(imageUrl),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 250,
              maxHeight: 300,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 200,
                  color: Colors.grey[200],
                  child: const Center(
                    child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (message.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(message.text, style: const TextStyle(fontSize: 16)),
        ],
      ],
    );
  }

  Widget _buildDocumentContent() {
    return GestureDetector(
      onTap: () => _openDocument(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getFileColor(message.type),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getFileIcon(message.type),
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.fileName ?? 'Document',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (message.fileSize != null)
                    Text(
                      _formatFileSize(message.fileSize!),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.download,
              color: Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageFooter() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTime(message.timestamp),
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 4),
            _buildMessageStatusIcon(),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageStatus() {
    return Container(
      margin: const EdgeInsets.only(left: 4, bottom: 4),
      child: _buildMessageStatusIcon(),
    );
  }

  Widget _buildMessageStatusIcon() {
    final status = message.getStatusForUser(currentUserId ?? 'default');
    
    switch (status) {
      case 'sending':
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1),
        );
      case 'sent':
        return const Icon(Icons.check, size: 16, color: Colors.grey);
      case 'delivered':
        return const Icon(Icons.done_all, size: 16, color: Colors.grey);
      case 'read':
        return const Icon(Icons.done_all, size: 16, color: Colors.blue);
      case 'failed':
        return const Icon(Icons.error_outline, size: 16, color: Colors.red);
      default:
        return const SizedBox.shrink();
    }
  }

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                onReply(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                onCopy(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(context);
                onForward(message);
              },
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(context);
                  // Implement delete functionality
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openMediaViewer(String imageUrl) {
    // Implement media viewer
  }

  void _openDocument() {
    // Implement document viewer
  }

  Color _getSenderColor(String senderId) {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];
    return colors[senderId.hashCode % colors.length];
  }

  Color _getFileColor(String fileType) {
    switch (fileType) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getFileIcon(String fileType) {
    switch (fileType) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _getReplyText(Message replyMessage) {
    switch (replyMessage.type) {
      case 'image':
        return replyMessage.text.isNotEmpty ? replyMessage.text : '📷 Photo';
      case 'pdf':
        return '📄 ${replyMessage.fileName ?? 'PDF Document'}';
      case 'doc':
      case 'docx':
        return '📄 ${replyMessage.fileName ?? 'Word Document'}';
      default:
        return replyMessage.text;
    }
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays == 0) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  String _formatDate(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}