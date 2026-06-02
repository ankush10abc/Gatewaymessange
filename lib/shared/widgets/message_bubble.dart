import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/message_model.dart';
import '../../core/services/whatsapp_text_parser.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool showTime;
  final Function(Message)? onReply;
  final Function(Message)? onCopy;
  final Function(Message)? onForward;
  final bool isGroupChat;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showTime = false,
    this.onReply,
    this.onCopy,
    this.onForward,
    this.isGroupChat = false,
  });

  @override
  Widget build(BuildContext context) {
    // debugPrint("Ankush sender name ${message.senderName}");
    return Column(
      children: [
        if (showTime)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              DateFormat('MMM dd, HH:mm').format(message.timestamp),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: GestureDetector(
            onLongPress: () => _showMessageOptions(context),
            child: Row(
              mainAxisAlignment:
                  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (!isMe) const SizedBox(width: 5),
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: Radius.circular(isMe ? 12 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 12),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sender name for group chats (only for others' messages)
                        if (isGroupChat && !isMe)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              message.senderName ?? 'Unknown',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1dab61),
                              ),
                            ),
                          ),
                        // Reply preview if this message is a reply
                        if (message.replyToMessage != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                              border: const Border(
                                  left:
                                      BorderSide(color: Colors.grey, width: 3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const  Text(
                                  // 'Replying to message ${message.replyToMessage!.file_path}',
                                  'Replying to message ',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildReplyPreview(message.replyToMessage!),
                                    Flexible(
                                      child: Text(
                                        _getReplyText(message.replyToMessage!),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.grey[600]),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        _buildMessageContent(),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('HH:mm').format(message.timestamp),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                _getStatusIcon(),
                                size: 16,
                                color: _getStatusColor(),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (isMe) const SizedBox(width: 5),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageContent() {
    switch (message.type) {
      case 'text':
        return _buildTextMessage();
      case 'image':
        return _buildImageMessage();
      case 'file':
        return _buildFileMessage();
      case 'pdf':
        return _buildFileMessage();
      case 'doc':
        return _buildFileMessage();
      case 'docx':
        return _buildFileMessage();
      case 'video':
        return _buildVideoMessage();
      default:
        return _buildTextMessage();
    }
  }

  Widget _buildTextMessage() {
    return FormattedText(
      message.text,
      style: const TextStyle(
        fontSize: 16,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildImageMessage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(
          builder: (context) => GestureDetector(
            onTap: () {
              if (message.file_path != null) {
                _showFullScreenImage(context);
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 200,
                  maxHeight: 200,
                ),
                child: message.file_path != null
                    ? CachedNetworkImage(
                        imageUrl: message.file_path!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 150,
                          color: Colors.grey[300],
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 150,
                          color: Colors.grey[300],
                          child: const Icon(Icons.error),
                        ),
                      )
                    : Container(
                        height: 150,
                        color: Colors.grey[300],
                        child: const Icon(Icons.image),
                      ),
              ),
            ),
          ),
        ),
        if (message.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            message.text,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ],
    );
  }

  Widget _buildFileMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getFileIcon(),
            color: Colors.grey[600],
            size: 24,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.fileName ?? 'File',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    fontSize: 14,
                  ),
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
          const SizedBox(width: 8),
          // Icon(
          //   Icons.download,
          //   color: Colors.grey[600],
          //   size: 20,
          // ),
        ],
      ),
    );
  }

  Widget _buildVideoMessage() {
    final videoUrl = message.file_path ?? message.fileUrl;
    return GestureDetector(
      onTap: () {
        if (videoUrl != null) {
          _playVideo(videoUrl);
        }
      },
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 200,
                maxHeight: 200,
              ),
              color: Colors.black,
              child: const SizedBox(
                height: 150,
                width: 200,
                child: Icon(
                  Icons.videocam,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
          if (message.text.isNotEmpty)
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  message.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: message.file_path!,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (context, url, error) => const Center(
                  child: Icon(Icons.error, color: Colors.white, size: 50),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _playVideo(String videoUrl) {
    // For now, just show a dialog with the video URL
    // In a real app, you would use a video player like video_player package
    debugPrint('Playing video: $videoUrl');
  }

  IconData _getStatusIcon() {
    // This would be based on actual message status
    return Icons.done_all;
  }

  Color _getStatusColor() {
    // This would be based on actual message status
    return const Color(0xFF34B7F1);
  }

  IconData _getFileIcon() {
    final extension = message.fileName?.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildReplyPreview(Message replyMessage) {
    final replyType = replyMessage.reply_type?.toString() ?? replyMessage.type;
    
    switch (replyType) {
      case 'image':
        if (replyMessage.file_path != null) {
          return Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey[400]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: replyMessage.file_path!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.image, size: 16, color: Colors.grey),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.image, size: 16, color: Colors.grey),
                ),
              ),
            ),
          );
        }
        break;
      case 'pdf':
      case 'doc':
      case 'docx':
        return Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: _getFileColor(replyType),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            _getFileIconByType(replyType),
            size: 16,
            color: Colors.white,
          ),
        );
    }
    return const SizedBox.shrink();
  }

  String _getReplyText(Message replyMessage) {
    final replyType = replyMessage.reply_type?.toString() ?? replyMessage.type;
    
    switch (replyType) {
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

  IconData _getFileIconByType(String fileType) {
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

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                onReply?.call(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                onCopy?.call(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(context);
                onForward?.call(message);
              },
            ),
          ],
        ),
      ),
    );
  }
}
