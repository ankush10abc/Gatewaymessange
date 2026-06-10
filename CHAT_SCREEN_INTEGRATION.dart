// // INSTRUCTIONS: Add this to your existing ChatScreen
// // Replace _loadInitialMessages() and _setupRealtimeListeners() with these methods
//
// import '../services/message_sync_service.dart';
//
// class _ChatScreenState extends ConsumerState<ChatScreen> {
//   // Add this field
//   final MessageSyncService _syncService = MessageSyncService();
//
//   // REPLACE: _loadInitialMessages()
//   Future<void> _loadInitialMessages() async {
//     try {
//       final int id = int.parse(widget.chatId);
//
//       // Load from cache first (INSTANT)
//       final cachedMessages = await _syncService.loadMessages(
//         chatId: widget.chatId,
//         chatType: widget.chatType,
//         apiService: _apiService,
//         currentUserId: _currentUserId,
//         otherUserId: widget.chatType != 'group' ? _user?['id']?.toString() : null,
//         pageCount: pageCount,
//       );
//
//       if (mounted && cachedMessages.isNotEmpty) {
//         setState(() {
//           _messages = cachedMessages;
//           _isLoadingPermissions = false;
//         });
//       }
//
//       // API call for user metadata (permission check)
//       if (widget.chatType == 'group') {
//         final response = await _apiService.getGroupMessages(
//           id,
//           pageCount,
//           ApiService.messageCount,
//         );
//         if (mounted) {
//           _user = Map<String, dynamic>.from(response.user);
//           setState(() {
//             _isLoadingPermissions = false;
//           });
//         }
//       } else {
//         final response = await _apiService.getConversation(
//           id,
//           pageCount,
//           ApiService.messageCount,
//         );
//         if (mounted) {
//           _user = Map<String, dynamic>.from(response.user);
//           setState(() {
//             _isLoadingPermissions = false;
//           });
//         }
//       }
//     } catch (e) {
//       if (mounted) {
//         setState(() {
//           _isLoadingPermissions = false;
//         });
//       }
//     }
//   }
//
//   // REPLACE: _setupRealtimeListeners() message subscription part
//   void _setupRealtimeListeners() {
//     if (_currentUserId == null) return;
//
//     // Start Firebase sync via service
//     _syncService.startFirebaseListener(
//       chatId: widget.chatId,
//       chatType: widget.chatType,
//       messagesPerPage: _messagesPerPage,
//       currentUserId: _currentUserId,
//       otherUserId: widget.chatType != 'group'
//           ? _user?['id']?.toString()
//           : '0',
//     );
//
//     // Watch for message changes from cache
//     _messagesSubscription = _syncService.watchMessages(widget.chatId).listen(
//       (messages) {
//         if (mounted) {
//           final previousLength = _messages.length;
//           setState(() {
//             if (widget.chatType == 'group' &&
//                 _user != null &&
//                 _user!['attendance_group'] == true) {
//               _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
//             } else {
//               _messages = messages;
//             }
//           });
//
//           if (_messages.length > previousLength && messages.isNotEmpty) {
//             final newMessage = messages.first;
//             if (newMessage.senderId != _currentUserId) {
//               ref.read(chatProvider.notifier).onMessageReceived(
//                 widget.chatId,
//                 widget.chatType,
//                 newMessage,
//                 true,
//               );
//             }
//           }
//
//           if (_isAtBottom && _messages.length > previousLength) {
//             Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
//           }
//         }
//       },
//       onError: (error) {
//         debugPrint('Messages stream error: $error');
//       },
//     );
//
//     // Keep typing and presence listeners as is
//     _typingSubscription = FirebaseRealtimeService.getTypingUsers(
//       widget.chatId,
//       widget.chatType,
//       otherUserId: _currentUserId,
//     ).listen((typingData) {
//       if (mounted) {
//         final typingUsers = <String, bool>{};
//         typingData.forEach((userId, data) {
//           if (data is Map &&
//               data['isTyping'] == true &&
//               userId != _currentUserId) {
//             typingUsers[userId] = true;
//           }
//         });
//
//         setState(() {
//           _typingUsers = typingUsers;
//         });
//       }
//     });
//
//     _presenceSubscription = FirebaseDatabase.instance
//         .ref('presence/${widget.chatId}')
//         .onValue
//         .listen((event) {
//       if (mounted) {
//         final value = event.snapshot.value;
//         final presenceData =
//             value is Map ? Map<String, dynamic>.from(value) : null;
//         setState(() {
//           _onlineUsers[widget.chatId] = presenceData;
//         });
//       }
//     });
//   }
//
//   // UPDATE: _sendMessage() to add optimistic update
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
//     // Add optimistic update to cache
//     await _syncService.addOptimisticMessage(widget.chatId, message);
//
//     // UI already updated via stream, no need for setState
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
//
//       ref.read(chatProvider.notifier).onMessageSent(
//         widget.chatId,
//         widget.chatType,
//         message,
//       );
//     } catch (e) {
//       // Error handling remains the same
//     }
//   }
//
//   // ADD: In dispose()
//   @override
//   void dispose() {
//     _syncService.stopFirebaseListener(widget.chatId, widget.chatType);
//     // ... rest of dispose code
//     super.dispose();
//   }
// }
