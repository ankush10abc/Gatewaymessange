

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../core/models/message_model.dart';
import '../../core/utils/internet_checker.dart';
import '../providers/optimized_chat_provider.dart';

class ForwardMessageDialog extends ConsumerStatefulWidget {
  final Message message;
  final Function(Message, List<String>) onForward;

  const ForwardMessageDialog({
    super.key,
    required this.message,
    required this.onForward,
  });

  @override
  ConsumerState<ForwardMessageDialog> createState() =>
      _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends ConsumerState<ForwardMessageDialog> {
  // Store composite key "type::id" to preserve both chatType and chatId unambiguously
  final Set<String> _selectedKeys = {};

  /// Builds a composite key from chat type and id
  static String _key(String type, String id) => '$type::$id';

  @override
  Widget build(BuildContext context) {
    // Use same provider as home screen so the same chat list is shown
    final chatState = ref.watch(optimizedChatProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Text(
                    'Forward Message',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Message Preview
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _getMessageIcon(),
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getMessagePreview(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),

          // Chat List — filter out attendance groups, same as home screen
          Expanded(
            child: chatState.isInitialLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(builder: (context) {
                    final visibleChats = chatState.chats
                        .where((c) => c.attendanceGroup != true)
                        .toList();
                    if (visibleChats.isEmpty) {
                      return const Center(child: Text('No chats available'));
                    }
                    return ListView.builder(
                      itemCount: visibleChats.length,
                      itemBuilder: (context, index) {
                        final chat = visibleChats[index];
                        // Use composite key so group/user with same numeric id are distinct
                        final compositeKey = _key(chat.type, chat.id);
                        final isSelected = _selectedKeys.contains(compositeKey);
                        if (chat.name == 'Unknown') return const SizedBox.shrink();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey[300],
                            child: Icon(
                              chat.type == 'group' ? Icons.group : Icons.person,
                              color: Colors.grey[600],
                            ),
                          ),
                          title: Text(
                            chat.name,
                            style: const TextStyle(color: Colors.black),
                          ),
                          subtitle: Text(
                            chat.type == 'group' ? 'Group' : 'Personal',
                            style: const TextStyle(color: Colors.black54),
                          ),
                          trailing: Checkbox(
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedKeys.add(compositeKey);
                                } else {
                                  _selectedKeys.remove(compositeKey);
                                }
                              });
                            },
                            activeColor: Theme.of(context).primaryColor,
                          ),
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedKeys.remove(compositeKey);
                              } else {
                                _selectedKeys.add(compositeKey);
                              }
                            });
                          },
                        );
                      },
                    );
                  }),
          ),

          // Forward Button
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedKeys.isNotEmpty
                    ? () async {
               bool hasInternet=   await InternetChecker.hasInternet();
                  if(hasInternet == true){
                    // Pass composite keys so _forwardMessage can extract type + id
                    final selectedKeys = _selectedKeys.toList();
                    Navigator.pop(context);
                    Future.microtask(() =>
                        widget.onForward(widget.message, selectedKeys));
                  }else{
                    Fluttertoast.showToast(msg: "Check your internet");
                  }

                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _selectedKeys.isEmpty
                      ? 'Select chats to forward'
                      : 'Forward to ${_selectedKeys.length} chat(s)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getMessageIcon() {
    switch (widget.message.type) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'file':
        return Icons.attach_file;
      default:
        return Icons.message;
    }
  }

  String _getMessagePreview() {
    switch (widget.message.type) {
      case 'image':
        return '📷 Photo';
      case 'video':
        return '🎥 Video';
      case 'file':
        return '📎 ${widget.message.fileName ?? 'File'}';
      default:
        return widget.message.text;
    }
  }
}
