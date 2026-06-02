// import 'dart:async';
// import 'dart:io';
//
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:dio/dio.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
//
// import '../../core/models/chat_model.dart';
// import '../../core/models/message_model.dart';
// import '../../core/services/api_service_simple.dart';
// import '../../core/services/firebase_realtime_service.dart';
// import '../../core/storage/storage_service.dart';
// import '../../shared/providers/auth_provider.dart';
// import '../../shared/providers/chat_provider.dart';
// import '../../shared/widgets/forward_message_dialog.dart';
// import 'user_detail_screen.dart';
//
// class ChatScreen extends ConsumerStatefulWidget {
//   final String chatId;
//   final String chatType;
//   final String chatName;
//
//   const ChatScreen({
//     super.key,
//     required this.chatId,
//     required this.chatType,
//     required this.chatName,
//   });
//
//   @override
//   ConsumerState<ChatScreen> createState() => _ChatScreenState();
// }
//
// class _ChatScreenState extends ConsumerState<ChatScreen>
//     with WidgetsBindingObserver {
//   final ScrollController _scrollController = ScrollController();
//   final TextEditingController _messageController = TextEditingController();
//   final FocusNode _focusNode = FocusNode();
//   late final ApiService _apiService;
//   final StorageService _storage = StorageService();
//
//   // Real-time state
//   StreamSubscription<QuerySnapshot>? _messagesSubscription;
//   StreamSubscription<DatabaseEvent>? _typingSubscription;
//   StreamSubscription<DatabaseEvent>? _presenceSubscription;
//
//   List<Message> _messages = [];
//   Map<String, bool> _typingUsers = {};
//   Map<String, dynamic> _onlineUsers = {};
//   Message? _replyToMessage;
//   bool _showEmojiPicker = false;
//   bool _isAtBottom = true;
//   Timer? _typingTimer;
//   String? _currentUserId;
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     final dio = Dio();
//     _apiService = ApiService(dio);
//     _initializeAuth();
//     _scrollController.addListener(_onScroll);
//     _messageController.addListener(_onTextChanged);
//     _focusNode.addListener(_onFocusChanged);
//
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _initializeChat();
//     });
//   }
//
//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _messagesSubscription?.cancel();
//     _typingSubscription?.cancel();
//     _presenceSubscription?.cancel();
//     _typingTimer?.cancel();
//     _scrollController.dispose();
//     _messageController.dispose();
//     _focusNode.dispose();
//
//     if (_currentUserId != null) {
//       FirebaseRealtimeService.setUserOffline(_currentUserId!);
//       FirebaseRealtimeService.setTyping(widget.chatId, _currentUserId!, false);
//     }
//     super.dispose();
//   }
//
//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (_currentUserId == null) return;
//
//     switch (state) {
//       case AppLifecycleState.resumed:
//         FirebaseRealtimeService.setUserOnline(_currentUserId!);
//         break;
//       case AppLifecycleState.paused:
//       case AppLifecycleState.inactive:
//         FirebaseRealtimeService.setUserOffline(_currentUserId!);
//         FirebaseRealtimeService.setTyping(widget.chatId, _currentUserId!, false);
//         break;
//       default:
//         break;
//     }
//   }
//
//   Future<void> _initializeAuth() async {
//     final token = await _storage.getToken();
//     if (token != null) {
//       _apiService.setAuthToken(token);
//     }
//   }
//
//   Future<void> _initializeChat() async {
//     final user = ref.read(authProvider).user;
//     if (user == null) return;
//
//     _currentUserId = user.id;
//
//     // Set user online
//     await FirebaseRealtimeService.setUserOnline(user.id);
//
//     // Load initial messages from API
//     await _loadInitialMessages();
//
//     // Set up real-time listeners
//     _setupRealtimeListeners();
//
//     // Mark messages as read
//     await FirebaseRealtimeService.markMessagesAsRead(widget.chatId, user.id);
//
//     // Auto-scroll to bottom
//     Future.delayed(const Duration(milliseconds: 500), _scrollToBottom);
//   }
//
//   Future<void> _loadInitialMessages() async {
//     try {
//       final int id = int.parse(widget.chatId);
//
//       if (widget.chatType == 'group') {
//         final response = await _apiService.getGroupMessages(id, 1, 50);
//         if (response.data != null) {
//           setState(() {
//             _messages = response.data.map<Message>((msgData) =>
//                 Message.fromJson(msgData.toJson())).toList();
//           });
//         }
//       } else {
//         final response = await _apiService.getConversation(id, 1, 50);
//         if (response.data != null) {
//           setState(() {
//             _messages = response.data.map<Message>((msgData) =>
//                 Message.fromJson(msgData.toJson())).toList();
//           });
//         }
//       }
//     } catch (e) {
//       debugPrint('Error loading initial messages: $e');
//     }
//   }
//
//   void _setupRealtimeListeners() {
//     // Listen to real-time messages
//     _messagesSubscription = FirebaseFirestore.instance
//         .collection('chats')
//         .doc(widget.chatId)
//         .collection('messages')
//         .orderBy('timestamp', descending: true)
//         .limit(50)
//         .snapshots()
//         .listen((snapshot) {
//       final firebaseMessages = snapshot.docs
//           .map((doc) => Message.fromFirestore(doc.data(), doc.id))
//           .toList();
//
//       setState(() {
//         _messages = _mergeMessages(_messages, firebaseMessages);
//       });
//
//       if (_isAtBottom) {
//         Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
//       }
//     });
//
//     // Listen to typing indicators
//     _typingSubscription = FirebaseDatabase.instance
//         .ref('typing/${widget.chatId}')
//         .onValue
//         .listen((event) {
//       // final typingData = Map<String, dynamic>.from(event.snapshot.value ?? {});
//       final typingData = event is Map ? Map<String, dynamic>.from(event) : <String, dynamic>{};
//       final typingUsers = <String, bool>{};
//
//       typingData.forEach((userId, data) {
//         if (data is Map && data['isTyping'] == true && userId != _currentUserId) {
//           typingUsers[userId] = true;
//         }
//       });
//
//       setState(() {
//         _typingUsers = typingUsers;
//       });
//     });
//
//     // Listen to presence for single chats
//     if (widget.chatType != 'group') {
//       _presenceSubscription = FirebaseDatabase.instance
//           .ref('presence/${widget.chatId}')
//           .onValue
//           .listen((event) {
//         final presenceData = event.snapshot.value as Map<String, dynamic>?;
//         setState(() {
//           _onlineUsers[widget.chatId] = presenceData;
//         });
//       });
//     }
//   }
//
//   List<Message> _mergeMessages(List<Message> apiMessages, List<Message> firebaseMessages) {
//     final messageMap = <String, Message>{};
//
//     // Add API messages first
//     for (final message in apiMessages) {
//       messageMap[message.id] = message;
//     }
//
//     // Override with Firebase messages (more recent)
//     for (final message in firebaseMessages) {
//       messageMap[message.id] = message;
//     }
//
//     final mergedList = messageMap.values.toList();
//     mergedList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
//     return mergedList;
//   }
//
//   void _onScroll() {
//     final isAtBottom = _scrollController.position.pixels <= 100;
//     if (_isAtBottom != isAtBottom) {
//       setState(() {
//         _isAtBottom = isAtBottom;
//       });
//     }
//   }
//
//   void _onTextChanged() {
//     if (_currentUserId == null) return;
//
//     final isTyping = _messageController.text.trim().isNotEmpty;
//     FirebaseRealtimeService.setTyping(widget.chatId, _currentUserId!, isTyping);
//
//     if (isTyping) {
//       _typingTimer?.cancel();
//       _typingTimer = Timer(const Duration(seconds: 3), () {
//         FirebaseRealtimeService.setTyping(widget.chatId, _currentUserId!, false);
//       });
//     }
//   }
//
//   void _onFocusChanged() {
//     if (_focusNode.hasFocus && _showEmojiPicker) {
//       setState(() {
//         _showEmojiPicker = false;
//       });
//     }
//   }
//
//   void _scrollToBottom() {
//     if (_scrollController.hasClients) {
//       _scrollController.animateTo(
//         0.0,
//         duration: const Duration(milliseconds: 300),
//         curve: Curves.easeOut,
//       );
//     }
//   }
//
//   void _scrollToMessage(Message message) {
//     final index = _messages.indexWhere((m) => m.id == message.id);
//     if (index != -1) {
//       final position = index * 100.0;
//       _scrollController.animateTo(
//         position,
//         duration: const Duration(milliseconds: 500),
//         curve: Curves.easeInOut,
//       );
//     }
//   }
//
//   Future<void> _sendMessage({
//     String? text,
//     String type = 'text',
//     String? fileUrl,
//     String? fileName,
//     int? fileSize,
//   }) async {
//     if (_currentUserId == null) return;
//
//     final messageText = text ?? fileName ?? '';
//     if (messageText.trim().isEmpty && type == 'text') return;
//
//     final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
//     final user = ref.read(authProvider).user!;
//
//     // Create message
//     final message = Message(
//       id: tempId,
//       chatId: widget.chatId,
//       senderId: user.id,
//       senderName: user.name,
//       text: messageText,
//       type: type,
//       timestamp: DateTime.now(),
//       status: {'default': 'sending'},
//       fileUrl: fileUrl,
//       fileName: fileName,
//       fileSize: fileSize,
//       replyToMessage: _replyToMessage,
//     );
//
//     // Add to local state immediately
//     setState(() {
//       _messages = [message, ..._messages];
//       _replyToMessage = null;
//     });
//
//     _messageController.clear();
//     FirebaseRealtimeService.setTyping(widget.chatId, _currentUserId!, false);
//     _scrollToBottom();
//
//     try {
//       // Send to Firebase for real-time sync
//       await FirebaseRealtimeService.sendMessage(message.copyWith(
//         status: {'default': 'sent'},
//       ));
//
//       // Send to API backend
//       await _sendToAPI(message);
//
//       // Update status to sent
//       _updateMessageStatus(tempId, 'sent');
//     } catch (e) {
//       _updateMessageStatus(tempId, 'failed');
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Failed to send message: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }
//
//   Future<void> _sendToAPI(Message message) async {
//     try {
//       if (widget.chatType == 'group') {
//         await _apiService.sendMessage(
//           message: message.text,
//           groupId: widget.chatId,
//           messageType: message.type,
//           filePath: message.fileUrl,
//           fileName: message.fileName,
//           fileSize: message.fileSize,
//           replyToMessageId: message.replyToMessage?.id,
//         );
//       } else {
//         await _apiService.sendMessage(
//           message: message.text,
//           receiverId: widget.chatId,
//           messageType: message.type,
//           filePath: message.fileUrl,
//           fileName: message.fileName,
//           fileSize: message.fileSize,
//           replyToMessageId: message.replyToMessage?.id,
//         );
//       }
//     } catch (e) {
//       debugPrint('API sync error: $e');
//     }
//   }
//
//   void _updateMessageStatus(String messageId, String status) {
//     setState(() {
//       _messages = _messages.map((msg) {
//         if (msg.id == messageId) {
//           return msg.copyWith(status: {'default': status});
//         }
//         return msg;
//       }).toList();
//     });
//   }
//
//   Future<void> _handleFileSelection(File file, String messageType) async {
//     try {
//       final uploadResponse = await _apiService.uploadFile(file, messageType);
//
//       await _sendMessage(
//         type: messageType,
//         fileUrl: uploadResponse.filePath,
//         fileName: uploadResponse.fileName,
//         fileSize: uploadResponse.fileSize,
//       );
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Failed to upload file: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final user = ref.watch(authProvider).user!;
//
//     return Scaffold(
//       appBar: AppBar(
//         title: GestureDetector(
//           onTap: () {
//             Navigator.push(
//               context,
//               MaterialPageRoute(
//                 builder: (context) => UserDetailScreen(
//                   userId: widget.chatId,
//                   userName: widget.chatName,
//                   userImage: null,
//                   userDescription: 'Available',
//                   userRole: null,
//                   userPhone: null,
//                   userEmail: null,
//                   isGroup: widget.chatType == 'group',
//                   isOnline: _onlineUsers[widget.chatId]?['isOnline'] ?? false,
//                   lastSeen: _onlineUsers[widget.chatId]?['lastSeen'] != null
//                       ? DateTime.fromMillisecondsSinceEpoch(_onlineUsers[widget.chatId]['lastSeen'])
//                       : null,
//                 ),
//               ),
//             );
//           },
//           child: Row(
//             children: [
//               CircleAvatar(
//                 radius: 18,
//                 backgroundColor: Colors.grey[300],
//                 child: Icon(Icons.person, color: Colors.grey[600]),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(widget.chatName, style: const TextStyle(fontSize: 16)),
//                     _buildSubtitle(),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//         actions: [
//           PopupMenuButton<String>(
//             onSelected: (value) {
//               switch (value) {
//                 case 'info':
//                   break;
//                 case 'media':
//                   break;
//                 case 'search':
//                   break;
//               }
//             },
//             itemBuilder: (context) => [
//               const PopupMenuItem(value: 'info', child: Text('Chat Info')),
//               const PopupMenuItem(value: 'media', child: Text('Media')),
//               const PopupMenuItem(value: 'search', child: Text('Search')),
//             ],
//           ),
//         ],
//       ),
//       body: Container(
//         decoration: const BoxDecoration(
//           image: DecorationImage(
//             image: AssetImage('assets/icons/chat_background.png'),
//             fit: BoxFit.cover,
//             opacity: 0.1,
//           ),
//         ),
//         child: Column(
//           children: [
//             // Messages List
//             Expanded(
//               child: Stack(
//                 children: [
//                   ListView.builder(
//                     controller: _scrollController,
//                     padding: const EdgeInsets.all(8),
//                     reverse: true,
//                     itemCount: _messages.length,
//                     itemBuilder: (context, index) {
//                       final message = _messages[index];
//                       final isMe = message.senderId == user.id;
//
//                       // Mark message as read if it's not from current user
//                       if (!isMe && _currentUserId != null) {
//                         WidgetsBinding.instance.addPostFrameCallback((_) {
//                           FirebaseRealtimeService.updateMessageStatus(
//                             widget.chatId, message.id, _currentUserId!, 'read');
//                         });
//                       }
//
//                       return _buildMessageBubble(message, isMe, index);
//                     },
//                   ),
//
//                   // Typing indicator
//                   if (_typingUsers.isNotEmpty)
//                     Positioned(
//                       bottom: 8,
//                       left: 8,
//                       right: 8,
//                       child: _buildTypingIndicator(),
//                     ),
//
//                   // Scroll to bottom button
//                   if (!_isAtBottom)
//                     Positioned(
//                       bottom: 16,
//                       right: 16,
//                       child: FloatingActionButton.small(
//                         onPressed: _scrollToBottom,
//                         backgroundColor: Colors.white,
//                         child: const Icon(Icons.keyboard_arrow_down),
//                       ),
//                     ),
//                 ],
//               ),
//             ),
//
//             // Message Input
//             Column(
//               children: [
//                 // Reply Preview
//                 if (_replyToMessage != null) _buildReplyPreview(),
//
//                 _buildMessageInput(),
//
//                 // Emoji picker
//                 if (_showEmojiPicker)
//                   SizedBox(
//                     height: 250,
//                     child: EmojiPicker(
//                       onEmojiSelected: (category, emoji) => _onEmojiSelected(emoji),
//                       config: const Config(
//                         columns: 7,
//                         emojiSizeMax: 32,
//                         initCategory: Category.RECENT,
//                         bgColor: Color(0xFFF2F2F2),
//                         indicatorColor: Color(0xFF1dab61),
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   // All the UI building methods and helper methods go here...
//   // (I'll add them in the next part to keep the response manageable)
// }