import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../app/app.dart';
import '../../core/services/deep_link_service.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../core/models/chat_model.dart';
import '../../core/models/message_model.dart';
import '../../core/services/whatsapp_text_parser.dart';
import '../../core/services/api_service_simple.dart';
import '../../core/services/firebase_realtime_service.dart';
import '../../core/storage/storage_service.dart';
import '../home/home_screen.dart';

class ChatSelectionScreen extends ConsumerStatefulWidget {
  final String message;

  const ChatSelectionScreen({super.key, required this.message});

  @override
  ConsumerState<ChatSelectionScreen> createState() => _ChatSelectionScreenState();
}

class _ChatSelectionScreenState extends ConsumerState<ChatSelectionScreen> {
  final Set<String> _selectedChats = {};
  late final ApiService _apiService;
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    final dio = Dio();
    _apiService = ApiService(dio);
    _initializeAuth();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider.notifier).loadChatList();
    });
  }

  Future<void> _initializeAuth() async {
    final token = await _storage.getToken();
    if (token != null) {
      _apiService.setAuthToken(token);
    }
  }

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
    DeepLinkService.setPendingMessage(null);
  }
  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final user = ref.watch(authProvider).user;

    return PopScope(
      canPop: false,  // Prevents default back navigation
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          DeepLinkService.setPendingMessage(null);
          context.go('/home');  // Redirects to HomeScreen route
        }
      },
      child: Scaffold(
        appBar: AppBar(

          title: Text('Select Chats (${_selectedChats.length})'),
          actions: [
            if (_selectedChats.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendToSelectedChats,
              ),
          ],
        ),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[100],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Message Preview:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12,color: Colors.black),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: FormattedText(
                      widget.message,
                      style: const TextStyle(fontSize: 14,color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: chatState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: chatState.chats.length,
                      itemBuilder: (context, index) {
                        final chat = chatState.chats[index];
                        final isSelected = _selectedChats.contains(chat.id);
                        final chatName = chat.getDisplayName(user?.id ?? '', []);

                        return CheckboxListTile(
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
                          title: Text(chatName),
                          subtitle: Text(chat.type == 'group' ? 'Group' : 'Personal'),
                          secondary: CircleAvatar(
                            backgroundColor: Colors.grey[300],
                            child: Text(chatName[0].toUpperCase()),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendToSelectedChats() async {
    if (_selectedChats.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final user = ref.read(authProvider).user;
    if (user == null) {
      if (mounted) Navigator.pop(context,true);
      return;
    }
    try {
      // Send messages in background
      await Future(() async {
        for (final chatId in _selectedChats) {
          try {
            final chat = ref.read(chatProvider).chats.firstWhere((c) => c.id == chatId);

            final message = Message(
              id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
              chatId: chatId,
              senderId: user.id,
              senderName: user.name,
              text: widget.message,
              type: 'text',
              timestamp: DateTime.now(),
              status: {'default': 'sending'},
            );

            // Send to Firebase
            final firebaseKey = await FirebaseRealtimeService.sendMessage(
              message,
              chatType: chat.type,
              currentUserId: user.id,
              otherUserId: chat.type != 'group' ? chatId : '0',
            );

            // Send to API
            Message? msg;
            if (chat.type == 'group') {
              msg = await _apiService.sendMessage(
                message: widget.message,
                groupId: chatId,
                messageType: 'text',
                firebaseKey: firebaseKey,
              );
            } else {
              msg = await _apiService.sendMessage(
                message: widget.message,
                receiverId: chatId,
                messageType: 'text',
                firebaseKey: firebaseKey,
              );
            }

            // Update Firebase with API msgId
            await FirebaseRealtimeService.updateMessage(
              message,
              chatType: chat.type,
              currentUserId: user.id,
              otherUserId: chat.type != 'group' ? chatId : '0',
              chatIdServer: msg.id.toString(),
              key: firebaseKey,
            );
          } catch (e) {
            debugPrint('Error sending to chat $chatId: $e');
          }
        }
      });

      if (mounted) {
        DeepLinkService.setPendingMessage(null);
        if(Navigator.canPop(context))
        Navigator.pop(context);
        context.go('/home');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message sent to ${_selectedChats.length} chats')),
        );
      }else{
        DeepLinkService.setPendingMessage(null);
        navigatorKey.currentState?.pushNamed('/home');
      }
    } catch (e) {
      DeepLinkService.setPendingMessage(null);
      navigatorKey.currentState?.pushNamed('/home');
      // Navigator.pushReplacementNamed(context, '/home');
      print(e);
    }
  }

}
