// import 'dart:async';
// import 'dart:io';
// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:dio/dio.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:scroll_to_index/scroll_to_index.dart';
//
// import '../../core/models/message_model.dart';
// import '../../core/services/api_service_simple.dart';
// import '../../core/services/firebase_realtime_service.dart';
// import '../../core/services/message_sync_service.dart';
// import '../../core/storage/storage_service.dart';
// import '../../core/utils/internet_checker.dart';
// import '../../shared/providers/auth_provider.dart';
// import '../../shared/providers/chat_messages_provider.dart';
// import '../../shared/widgets/enhanced_message_input.dart';
//
// class OptimizedChatScreen extends ConsumerStatefulWidget {
//   final String chatId;
//   final String chatType;
//   final String chatName;
//   final String? initialMessage;
//
//   const OptimizedChatScreen({
//     super.key,
//     required this.chatId,
//     required this.chatType,
//     required this.chatName,
//     this.initialMessage,
//   });
//
//   @override
//   ConsumerState<OptimizedChatScreen> createState() => _OptimizedChatScreenState();
// }
//
// class _OptimizedChatScreenState extends ConsumerState<OptimizedChatScreen> {
//   final _scrollController = AutoScrollController();
//   final TextEditingController _messageController = TextEditingController();
//   final MessageSyncService _syncService = MessageSyncService();
//   late final ApiService _apiService;
//   final StorageService _storage = StorageService();
//
//   Map<String, dynamic>? _user;
//   Message? _replyToMessage;
//   String? _currentUserId;
//   bool _isAtBottom = true;
//   Timer? _typingTimer;
//   int _pageCount = 1;
//
//   @override
//   void initState() {
//     super.initState();
//     final dio = Dio();
//     _apiService = ApiService(dio);
//     _initializeAuth();
//     _scrollController.addListener(_onScroll);
//
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       ApiService.setContext(context);
//       _initializeChat();
//     });
//   }
//
//   @override
//   void dispose() {
//     _syncService.stopFirebaseListener(widget.chatId, widget.chatType);
//     _typingTimer?.cancel();
//     _scrollController.dispose();
//     _messageController.dispose();
//
//     if (_currentUserId != null) {
//       try {
//         FirebaseRealtimeService.setUserOffline(_currentUserId!);
//         FirebaseRealtimeService.setTyping(
//           widget.chatType,
//           widget.chatId,
//           _currentUserId!,
//           false,
//         );
//       } catch (e) {
//         // Ignore
//       }
//     }
//     super.dispose();
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
//     // Load messages from cache (instant) + get user metadata
//     final result = await _syncService.loadMessages(
//       chatId: widget.chatId,
//       chatType: widget.chatType,
//       apiService: _apiService,
//       currentUserId: _currentUserId,
//       otherUserId: widget.chatType != 'group' ? _user?['id']?.toString() : null,
//       pageCount: _pageCount,
//     );
//
//     // Get user metadata for permissions after first API call
//     await Future.delayed(const Duration(milliseconds: 500));
//     if (mounted) {
//       try {
//         final int id = int.parse(widget.chatId);
//         if (widget.chatType == 'group') {
//           final response = await _apiService.getGroupMessages(id, _pageCount, ApiService.messageCount);
//           _user = Map<String, dynamic>.from(response.user);
//         } else {
//           final response = await _apiService.getConversation(id, _pageCount, ApiService.messageCount);
//           _user = Map<String, dynamic>.from(response.user);
//         }
//         if (mounted) setState(() {});
//       } catch (e) {
//         debugPrint('Error loading user metadata: $e');
//       }
//     }
//
//     // Start Firebase real-time sync
//     _syncService.startFirebaseListener(
//       chatId: widget.chatId,
//       chatType: widget.chatType,
//       messagesPerPage: 50,
//       currentUserId: _currentUserId,
//       otherUserId: widget.chatType != 'group' ? _user?['id']?.toString() : null,
//     );
//
//     await FirebaseRealtimeService.setUserOnline(user.id);
//
//     Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
//   }
//
//   void _onScroll() {
//     if (!_scrollController.hasClients) return;
//
//     final position = _scrollController.position;
//     _isAtBottom = position.pixels <= 100;
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
//     final hasInternet = await InternetChecker.hasInternet();
//     if (!hasInternet) return;
//
//     final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
//     final user = ref.read(authProvider).user!;
//
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
//     // Optimistic update
//     ref.read(chatMessagesProvider(widget.chatId).notifier).addOptimisticMessage(message);
//
//     _messageController.clear();
//     setState(() => _replyToMessage = null);
//
//     FirebaseRealtimeService.setTyping(
//       widget.chatType,
//       widget.chatId,
//       _currentUserId!,
//       false,
//     );
//     _scrollToBottom();
//
//     try {
//       await _sendToAPI(message);
//     } catch (e) {
//       debugPrint('Send message error: $e');
//     }
//   }
//
//   Future<void> _sendToAPI(Message message) async {
//     String? firebaseKey;
//     try {
//       firebaseKey = await FirebaseRealtimeService.sendMessage(
//         message,
//         chatType: widget.chatType,
//         currentUserId: _currentUserId,
//         otherUserId: widget.chatType != 'group' ? _user?['id']?.toString() ?? '0' : '0',
//       );
//     } catch (e) {
//       debugPrint('Firebase send error: $e');
//     }
//
//     Message? msg;
//     if (widget.chatType == 'group') {
//       msg = await _apiService.sendMessage(
//         message: message.text,
//         groupId: widget.chatId,
//         messageType: message.type,
//         filePath: message.fileUrl,
//         fileName: message.fileName,
//         fileSize: message.fileSize,
//         firebaseKey: firebaseKey,
//         replyToMessageId: message.replyToMessage?.msgId,
//         old_firebase_message_id: message.replyToMessage?.firebaseId,
//       );
//     } else {
//       msg = await _apiService.sendMessage(
//         message: message.text,
//         receiverId: widget.chatId,
//         messageType: message.type,
//         filePath: message.fileUrl,
//         fileName: message.fileName,
//         fileSize: message.fileSize,
//         firebaseKey: firebaseKey,
//         replyToMessageId: message.replyToMessage?.msgId,
//         old_firebase_message_id: message.replyToMessage?.firebaseId,
//       );
//     }
//
//     await FirebaseRealtimeService.updateMessage(
//       message,
//       chatType: widget.chatType,
//       currentUserId: _currentUserId,
//       otherUserId: widget.chatType != 'group' ? _user?['id']?.toString() ?? '0' : '0',
//       chatIdServer: msg.id.toString(),
//       key: firebaseKey,
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final messagesState = ref.watch(chatMessagesProvider(widget.chatId));
//     final user = ref.watch(authProvider).user!;
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(widget.chatName),
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
//             Expanded(
//               child: messagesState.messages.isEmpty && messagesState.isLoading
//                   ? const Center(child: CircularProgressIndicator())
//                   : _MessagesList(
//                       messages: messagesState.messages,
//                       scrollController: _scrollController,
//                       currentUserId: user.id,
//                     ),
//             ),
//             if (_replyToMessage != null)
//               _ReplyPreview(
//                 replyMessage: _replyToMessage!,
//                 onCancel: () => setState(() => _replyToMessage = null),
//               ),
//             Padding(
//               padding: const EdgeInsets.only(bottom: 8.0),
//               child: EnhancedMessageInput(
//                 controller: _messageController,
//                 onSendMessage: (text) => _sendMessage(text: text),
//                 onTypingChanged: (isTyping) {
//                   if (_currentUserId != null) {
//                     FirebaseRealtimeService.setTyping(
//                       widget.chatType,
//                       widget.chatId,
//                       _currentUserId!,
//                       isTyping,
//                     );
//                     if (isTyping) {
//                       _typingTimer?.cancel();
//                       _typingTimer = Timer(const Duration(seconds: 3), () {
//                         FirebaseRealtimeService.setTyping(
//                           widget.chatType,
//                           widget.chatId,
//                           _currentUserId!,
//                           false,
//                         );
//                       });
//                     }
//                   }
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
//
// class _MessagesList extends StatelessWidget {
//   final List<Message> messages;
//   final AutoScrollController scrollController;
//   final String currentUserId;
//
//   const _MessagesList({
//     required this.messages,
//     required this.scrollController,
//     required this.currentUserId,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return ListView.builder(
//       controller: scrollController,
//       padding: const EdgeInsets.all(8),
//       reverse: true,
//       itemCount: messages.length,
//       itemBuilder: (context, index) {
//         final message = messages[index];
//         final isMe = message.senderId == currentUserId;
//
//         return AutoScrollTag(
//           key: ValueKey(message.id),
//           controller: scrollController,
//           index: index,
//           child: _MessageBubble(message: message, isMe: isMe),
//         );
//       },
//     );
//   }
// }
//
// class _MessageBubble extends StatelessWidget {
//   final Message message;
//   final bool isMe;
//
//   const _MessageBubble({
//     required this.message,
//     required this.isMe,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
//       child: Row(
//         mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
//         children: [
//           Flexible(
//             child: Container(
//               constraints: BoxConstraints(
//                 maxWidth: MediaQuery.of(context).size.width * 0.75,
//               ),
//               padding: const EdgeInsets.all(12),
//               decoration: BoxDecoration(
//                 color: isMe ? const Color(0xFFDCF8C6) : const Color(0xFFFCD7EB),
//                 borderRadius: BorderRadius.only(
//                   topLeft: const Radius.circular(12),
//                   topRight: const Radius.circular(12),
//                   bottomLeft: Radius.circular(isMe ? 12 : 4),
//                   bottomRight: Radius.circular(isMe ? 4 : 12),
//                 ),
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     message.text,
//                     style: const TextStyle(fontSize: 16, color: Colors.black),
//                   ),
//                   const SizedBox(height: 4),
//                   Row(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       Text(
//                         _formatTime(message.timestamp),
//                         style: TextStyle(fontSize: 11, color: Colors.grey[600]),
//                       ),
//                       if (isMe) ...[
//                         const SizedBox(width: 4),
//                         _buildStatusIcon(message),
//                       ],
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildStatusIcon(Message message) {
//     final status = message.status['default'] ?? 'sent';
//
//     switch (status) {
//       case 'sending':
//         return const SizedBox(
//           width: 12,
//           height: 12,
//           child: CircularProgressIndicator(strokeWidth: 1),
//         );
//       case 'sent':
//         return const Icon(Icons.check, size: 16, color: Colors.grey);
//       case 'delivered':
//         return const Icon(Icons.done_all, size: 16, color: Colors.grey);
//       case 'read':
//         return const Icon(Icons.done_all, size: 16, color: Colors.blue);
//       default:
//         return const SizedBox.shrink();
//     }
//   }
//
//   String _formatTime(DateTime timestamp) {
//     return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
//   }
// }
//
// class _ReplyPreview extends StatelessWidget {
//   final Message replyMessage;
//   final VoidCallback onCancel;
//
//   const _ReplyPreview({
//     required this.replyMessage,
//     required this.onCancel,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(12),
//       margin: const EdgeInsets.symmetric(horizontal: 8),
//       decoration: BoxDecoration(
//         color: const Color(0xFFE8F5E8),
//         borderRadius: BorderRadius.circular(8),
//         border: const Border(
//           left: BorderSide(color: Color(0xFF1dab61), width: 4),
//         ),
//       ),
//       child: Row(
//         children: [
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Replying to ${replyMessage.senderName ?? replyMessage.senderId}',
//                   style: const TextStyle(
//                     fontWeight: FontWeight.bold,
//                     color: Color(0xFF1dab61),
//                     fontSize: 12,
//                   ),
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   replyMessage.text,
//                   maxLines: 2,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(color: Colors.grey[700], fontSize: 14),
//                 ),
//               ],
//             ),
//           ),
//           IconButton(
//             icon: const Icon(Icons.close, size: 20),
//             color: Colors.grey[600],
//             onPressed: onCancel,
//           ),
//         ],
//       ),
//     );
//   }
// }
