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
import 'chat_screen.dart';

class ChatDeepLinkingScreen extends ConsumerStatefulWidget {
  final String message;

  const ChatDeepLinkingScreen({super.key, required this.message});


  @override
  ConsumerState<ChatDeepLinkingScreen> createState() => _ChatDeepLinkingScreenState();
}

class _ChatDeepLinkingScreenState extends ConsumerState<ChatDeepLinkingScreen> {
  String? _selectedChatId;
  String? _actual_role;
  late final ApiService _apiService;
  final StorageService _storage = StorageService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSending = false;

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
    _searchController.dispose();
    DeepLinkService.setPendingMessage(null);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final user = ref.watch(authProvider).user;

    final filteredChats = chatState.chats.where((chat) {
      if (_searchQuery.isEmpty) return true;
      final chatName = chat.getDisplayName(user?.id ?? '', []).toLowerCase();
      return chatName.contains(_searchQuery.toLowerCase());
    }).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          DeepLinkService.setPendingMessage(null);
          context.go('/home');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Select Chat'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              DeepLinkService.setPendingMessage(null);
              context.go('/home');
            },
          ),
        ),
        body: Column(
          children: [
            // Message Preview Card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.message, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Message to Send',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: FormattedText(
                        widget.message,
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: Colors.indigoAccent),
                decoration: InputDecoration(
                  hintText: 'Search chats...',

                  hintStyle: TextStyle(color: Colors.blue),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),

            // Chat List
            Expanded(
              child: chatState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredChats.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isEmpty ? 'No chats available' : 'No chats found',
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredChats.length,
                          itemBuilder: (context, index) {
                            final chat = filteredChats[index];
                            // debugPrint("chattoJson${chat.toJson()}");
                            final isSelected = _selectedChatId == chat.id && _actual_role == chat.actual_role  ;
                            final attendance_group = filteredChats[index].attendance_group ?? false;
                            final chatName = chat.getDisplayName(user?.id ?? '', []);

                            return
                              attendance_group == true ? SizedBox() :
                              Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected && attendance_group == false ? Colors.blue : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: ListTile(
                                onTap: () {
                                  if(attendance_group == true ){
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Message not sent to chat')),
                                    );

                                  }else{
                                    setState(() {
                                      debugPrint("Ankush ${chat.id} $attendance_group");
                                      _selectedChatId = chat.id;
                                      _actual_role = chat.actual_role;
                                    });
                                  }

                                },
                                leading: CircleAvatar(
                                  backgroundColor: isSelected  && attendance_group == false ?  Colors.blue : Colors.grey.shade300,
                                  child: Text(
                                    chatName[0].toUpperCase(),
                                    style: TextStyle(
                                      color: isSelected && attendance_group == false ?  Colors.white : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  chatName,
                                  style: TextStyle(
                                    fontWeight: isSelected && attendance_group == false ?  FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    Icon(
                                      chat.type == 'group' ? Icons.group : Icons.person,
                                      size: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      chat.type == 'group' ? 'Group' : 'Personal',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                                trailing: isSelected
                                    && attendance_group == false ?  Icon(Icons.check_circle, color: Colors.blue, size: 28)
                                    : Icon(Icons.circle_outlined, color: Colors.grey.shade400, size: 28),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
        bottomNavigationBar: _selectedChatId != null
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: ElevatedButton.icon(
                    onPressed: _isSending ? null : _sendToSelectedChat,
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isSending ? 'Sending...' : 'Send Message',style: TextStyle(color: _isSending ? Colors.indigo : Colors.white),),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  void _sendToSelectedChat() async {
    if (_selectedChatId == null || _isSending) return;
    debugPrint("Ankush $_selectedChatId");
    setState(() {
      _isSending = true;
    });

    final user = ref.read(authProvider).user;
    if (user == null) {
      setState(() {
        _isSending = false;
      });
      return;
    }

    final chat = ref.read(chatProvider).chats.firstWhere((c) => c.id == _selectedChatId  && c.actual_role == _actual_role);
    final chatName = chat.getDisplayName(user.id, []);
    try {
      final chat = ref.read(chatProvider).chats.firstWhere((c) => c.id == _selectedChatId && c.actual_role == _actual_role);
      // final actual_role = ref.read(chatProvider).chats.firstWhere((c) => c.actual_role == _selectedChatId);
        debugPrint("chattoJson${chat.toJson()}");
      final message = Message(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        chatId: _selectedChatId!,
        senderId: user.id,
        senderName: user.name,
        text: widget.message,
        type: 'text',
        timestamp: DateTime.now(),
        status: {'default': 'sending'},
      );

      // Send to Firebase
      debugPrint("It is comming two times$_selectedChatId");
      final firebaseKey = await FirebaseRealtimeService.sendMessage(
        message,
        chatType: chat.type,
        currentUserId: user.id,
        otherUserId: chat.type != 'group' ? _selectedChatId ?? '1' : '0',
      );

      // Send to API
      Message? msg;
      if (chat.type == 'group') {
        msg = await _apiService.sendMessage(
          message: widget.message,
          groupId: _selectedChatId,
          messageType: 'text',
          firebaseKey: firebaseKey,
        );
      } else {
        debugPrint("Ankush $_selectedChatId");
        msg = await _apiService.sendMessage(
          message: widget.message,
          receiverId: _selectedChatId ?? '1',
          messageType: 'text',
          firebaseKey: firebaseKey,
        );
      }

      // Update Firebase with API msgId
      await FirebaseRealtimeService.updateMessage(
        message,
        chatType: chat.type,
        currentUserId: user.id,
        otherUserId: chat.type != 'group' ? _selectedChatId ??'1' : '0',
        chatIdServer: msg.id.toString(),
        key: firebaseKey,
      );
    } catch (e) {
      debugPrint('Error sending to chat $_selectedChatId: $e');
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
      return;
    }

    // Clear pending message and navigate to chat screen
    DeepLinkService.setPendingMessage(null);
    
    if (mounted) {
      // Navigate directly to chat screen without initialMessage since message already sent
      context.go('/home');
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              chatId: _selectedChatId ?? '1',
              chatType: chat.type,
              chatName: chatName,
            ),
          ),
        );
      }
    }
  }

}
