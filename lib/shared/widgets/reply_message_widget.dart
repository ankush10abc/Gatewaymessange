import 'package:flutter/material.dart';
import '../../core/models/message_model.dart';
import '../../core/models/user_model.dart';

class ReplyMessageWidget extends StatelessWidget {
  final Message replyToMessage;
  final User? replyToUser;
  final VoidCallback? onCancel;

  const ReplyMessageWidget({
    super.key,
    required this.replyToMessage,
    this.replyToUser,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(
            color: Color(0xFF1dab61),
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  replyToUser?.name ?? 'Unknown User',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1dab61),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (replyToMessage.type == 'image' && replyToMessage.file_path != null)
                      Container(
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
                            replyToMessage.file_path!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.image, size: 20, color: Colors.grey),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        _getReplyPreview(),
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onCancel != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onCancel,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  String _getReplyPreview() {
    final replyType = replyToMessage.reply_type?.toString() ?? replyToMessage.type;
    
    switch (replyType) {
      case 'text':
        return replyToMessage.text;
      case 'image':
        return replyToMessage.text.isNotEmpty ? replyToMessage.text : '📷 Photo';
      case 'pdf':
        return '📄 ${replyToMessage.fileName ?? 'PDF Document'}';
      case 'doc':
      case 'docx':
        return '📄 ${replyToMessage.fileName ?? 'Word Document'}';
      case 'video':
        return '🎥 Video';
      default:
        return replyToMessage.text;
    }
  }
}

class MessageWithReply extends StatelessWidget {
  final Message message;
  final Message? replyToMessage;
  final User? replyToUser;
  final bool isMe;

  const MessageWithReply({
    super.key,
    required this.message,
    this.replyToMessage,
    this.replyToUser,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (replyToMessage != null)
          Container(
            margin: EdgeInsets.only(
              left: isMe ? 40 : 8,
              right: isMe ? 8 : 40,
              bottom: 4,
            ),
            child: ReplyMessageWidget(
              replyToMessage: replyToMessage!,
              replyToUser: replyToUser,
            ),
          ),
        // Original message bubble would go here
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(message.text),
        ),
      ],
    );
  }
}

class ReplyProvider extends ChangeNotifier {
  Message? _replyToMessage;
  User? _replyToUser;

  Message? get replyToMessage => _replyToMessage;
  User? get replyToUser => _replyToUser;
  bool get isReplying => _replyToMessage != null;

  void setReply(Message message, User user) {
    _replyToMessage = message;
    _replyToUser = user;
    notifyListeners();
  }

  void clearReply() {
    _replyToMessage = null;
    _replyToUser = null;
    notifyListeners();
  }

  Message createReplyMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) {
    return Message(
      id: '',
      chatId: chatId,
      senderId: senderId,
      text: text,
      type: 'text',
      timestamp: DateTime.now(),
      status: {},
      replyToId: _replyToMessage?.id,
    );
  }
}
