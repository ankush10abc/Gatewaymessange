import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/message_model.dart';
import '../providers/chat_provider.dart';

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
  final Set<String> _selectedChats = {};
  final int _maxSelection = 5;

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);

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
                // Text(
                //   '${_selectedChats.length}/$_maxSelection',
                //   style: const TextStyle(color: Colors.white70),
                // ),
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

          // Chat List
          Expanded(
            child: chatState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(builder: (context) {
                    final visibleChats = chatState.chats
                        .where((c) => c.attendance_group != true)
                        .toList();
                    if (visibleChats.isEmpty) {
                      return const Center(child: Text('No chats available'));
                    }
                    return ListView.builder(
                      itemCount: visibleChats.length,
                      itemBuilder: (context, index) {
                        final chat = visibleChats[index];
                        final isSelected = _selectedChats.contains(chat.id);
                        debugPrint("chat.id${chat.id}");
                        // final canSelect =
                        //     _selectedChats.length < _maxSelection || isSelected;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey[300],
                            child: Icon(
                              chat.type == 'group' ? Icons.group : Icons.person,
                              color: Colors.grey[600],
                            ),
                          ),
                          title: Text(
                            chat.groupName ?? chat.id,
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
                                  _selectedChats.add(chat.id);
                                } else {
                                  _selectedChats.remove(chat.id);
                                }
                              });
                            },
                            activeColor: Theme.of(context).primaryColor,
                          ),
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedChats.remove(chat.id);
                              } else {
                                _selectedChats.add(chat.id);
                              }
                            });
                          },
                          enabled: true,
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
                onPressed: _selectedChats.isNotEmpty
                    ? () {
                        final selectedIds = _selectedChats.toList();
                        Navigator.pop(context);
                        Future.microtask(() =>
                            widget.onForward(widget.message, selectedIds));
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
                  _selectedChats.isEmpty
                      ? 'Select chats to forward'
                      : 'Forward to ${_selectedChats.length} chat(s)',
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
