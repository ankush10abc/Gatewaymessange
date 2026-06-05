// // ========================================
// // IMPLEMENTATION GUIDE: HIGH-PERFORMANCE UI
// // ========================================
// // This guide shows how to implement instant UI updates with zero loading states
//
// // ========================================
// // 1. INITIALIZE SERVICES (main.dart)
// // ========================================
//
// import 'package:flutter/material.dart';
// import 'package:dio/dio.dart';
// import 'core/services/cache_manager.dart';
// import 'core/services/background_sync_service.dart';
// import 'core/services/api_service_simple.dart';
// import 'core/services/offline_queue_service.dart';
// import 'core/storage/storage_service.dart';
//
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//
//   // Initialize cache FIRST for instant data access
//   await CacheManager.init();
//
//   // Initialize storage
//   final storage = StorageService();
//   await storage.init();
//
//   // Initialize API and offline queue
//   final dio = Dio();
//   final apiService = ApiService(dio);
//   final token = await storage.getToken();
//   if (token != null) {
//     apiService.setAuthToken(token);
//   }
//
//   await OfflineQueueService.initialize(apiService);
//
//   // Start background sync
//   final backgroundSync = BackgroundSyncService(apiService);
//   backgroundSync.start();
//
//   runApp(MyApp());
// }
//
// // ========================================
// // 2. CHAT PROVIDER - Already Updated ✅
// // ========================================
// // lib/shared/providers/chat_provider.dart
// // - Loads from cache instantly (0ms)
// // - Syncs in background without blocking
// // - No loading indicators
//
// // ========================================
// // 3. OPTIMISTIC MESSAGE SENDING
// // ========================================
//
// // In ChatScreen, replace _sendMessage with:
//
// import '../../core/services/optimistic_update_handler.dart';
//
// class _ChatScreenState extends ConsumerState<ChatScreen> {
//   late OptimisticUpdateHandler _optimisticHandler;
//
//   @override
//   void initState() {
//     super.initState();
//     final user = ref.read(authProvider).user!;
//     _optimisticHandler = OptimisticUpdateHandler(_apiService, user.id);
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
//     final tempId = 'temp_\${DateTime.now().millisecondsSinceEpoch}';
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
//     // INSTANT UI UPDATE - message appears immediately
//     setState(() {
//       _messages.insert(0, message);
//       _replyToMessage = null;
//     });
//     _messageController.clear();
//     _scrollToBottom();
//
//     // Background sync - don't wait
//     _optimisticHandler.sendMessageOptimistic(
//       message: message,
//       chatType: widget.chatType,
//       chatId: widget.chatId,
//       otherUserId: widget.chatType != 'group' ? _user!['id']?.toString() : null,
//       onOptimisticUpdate: (updatedMsg) {
//         // Update message status in UI
//         setState(() {
//           final index = _messages.indexWhere((m) => m.id == updatedMsg.id);
//           if (index != -1) {
//             _messages[index] = updatedMsg;
//           }
//         });
//       },
//       onSuccess: (finalMsg) {
//         // Replace temp message with final message from API
//         setState(() {
//           final index = _messages.indexWhere((m) => m.id == tempId);
//           if (index != -1) {
//             _messages[index] = finalMsg;
//           }
//         });
//       },
//       onError: (msg, error) {
//         // Mark message as failed
//         setState(() {
//           final index = _messages.indexWhere((m) => m.id == msg.id);
//           if (index != -1) {
//             _messages[index] = msg.copyWith(status: {'default': 'failed'});
//           }
//         });
//       },
//     );
//   }
// }
//
// // ========================================
// // 4. INSTANT MESSAGE LOADING (ChatScreen)
// // ========================================
//
// // Update _loadInitialMessages to load from cache first:
//
// Future<void> _loadInitialMessages() async {
//   // INSTANT: Load cached messages first (0ms)
//   final cachedMessages = CacheManager.getCachedMessages(widget.chatId);
//   if (cachedMessages.isNotEmpty) {
//     setState(() {
//       _messages = cachedMessages;
//       _isLoadingPermissions = false;
//     });
//   }
//
//   // Background API sync
//   try {
//     final int id = int.parse(widget.chatId);
//
//     if (widget.chatType == 'group') {
//       final response = await _apiService.getGroupMessages(id, pageCount, ApiService.messageCount);
//       if (mounted) {
//         _user = Map<String, dynamic>.from(response.user);
//         final messages = response.data.map<Message>((msgData) {
//           return Message.fromJson(msgData.toJson());
//         }).toList();
//
//         setState(() {
//           _messages = messages;
//           _isLoadingPermissions = false;
//         });
//
//         // Save to cache for next time
//         await CacheManager.saveMessages(widget.chatId, messages);
//       }
//     } else {
//       final response = await _apiService.getConversation(id, pageCount, ApiService.messageCount);
//       if (mounted) {
//         _user = Map<String, dynamic>.from(response.user);
//         final messages = response.data.map<Message>((msgData) => Message.fromJson(msgData.toJson())).toList();
//
//         setState(() {
//           _messages = messages;
//           _isLoadingPermissions = false;
//         });
//
//         await CacheManager.saveMessages(widget.chatId, messages);
//       }
//     }
//   } catch (e) {
//     // Keep showing cached data on error
//     if (mounted && _messages.isEmpty) {
//       setState(() {
//         _isLoadingPermissions = false;
//       });
//     }
//   }
// }
//
// // ========================================
// // 5. PRELOADING & IMAGE OPTIMIZATION
// // ========================================
//
// // Add to ChatScreen for better image performance:
//
// Widget _buildImageContent(Message message) {
//   final imageUrl = message.fileUrl ?? message.file_path ?? '';
//   final fullImageUrl = imageUrl.contains(ApiService.baseUrl)
//       ? imageUrl
//       : '\${ApiService.baseUrl}/storage/\$imageUrl';
//
//   return Column(
//     crossAxisAlignment: CrossAxisAlignment.start,
//     children: [
//       GestureDetector(
//         onTap: () => _showFullScreenImage(fullImageUrl),
//         child: Container(
//           constraints: const BoxConstraints(maxWidth: 250, maxHeight: 300),
//           child: ClipRRect(
//             borderRadius: BorderRadius.circular(8),
//             child: CachedNetworkImage(
//               imageUrl: fullImageUrl,
//               fit: BoxFit.cover,
//               // Optimize for faster loading
//               memCacheWidth: 250,
//               maxWidthDiskCache: 250,
//               // Show cached image instantly
//               fadeInDuration: Duration.zero,
//               placeholder: (context, url) => Container(
//                 height: 200,
//                 color: Colors.grey[200],
//               ),
//               errorWidget: (context, error, stackTrace) => Container(
//                 height: 200,
//                 color: Colors.grey[200],
//                 child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
//               ),
//             ),
//           ),
//         ),
//       ),
//     ],
//   );
// }
//
// // ========================================
// // 6. BATCH MARK AS READ (Reduce API Calls)
// // ========================================
//
// // Add batchSendMessages to ApiService:
//
// class ApiService {
//   // Add this method:
//   Future<Map<String, dynamic>> batchSendMessages(List<Map<String, dynamic>> messages) async {
//     final response = await _dio.post(
//       '/api/messages/batch-send',
//       data: {'messages': messages},
//     );
//     return response.data;
//   }
// }
//
// // ========================================
// // 7. PERFORMANCE MONITORING
// // ========================================
//
// // Add to HomeScreen:
//
// void _measurePerformance() {
//   final stopwatch = Stopwatch()..start();
//
//   // Load chat list
//   ref.read(chatProvider.notifier).loadChatList();
//
//   stopwatch.stop();
//   debugPrint('✅ Chat list loaded in: \${stopwatch.elapsedMilliseconds}ms');
//
//   // Should be <100ms for instant feel
//   if (stopwatch.elapsedMilliseconds > 100) {
//     debugPrint('⚠️ Performance warning: slow chat load');
//   }
// }
//
// // ========================================
// // EXPECTED RESULTS
// // ========================================
//
// // ✅ Chat list: <100ms load time (instant)
// // ✅ Messages: <100ms load time (instant)
// // ✅ Send message: Instant UI update, background sync
// // ✅ Images: Progressive loading with cache
// // ✅ No loading spinners on screen transitions
// // ✅ Smooth 60fps scrolling
// // ✅ Offline mode: Full functionality
// // ✅ Background sync: Silent, no UI blocking
//
// // ========================================
// // MIGRATION CHECKLIST
// // ========================================
//
// // □ 1. Initialize CacheManager in main.dart
// // □ 2. Start BackgroundSyncService in main.dart
// // □ 3. Update ChatProvider (already done ✅)
// // □ 4. Replace _sendMessage with optimistic handler
// // □ 5. Update _loadInitialMessages to use cache
// // □ 6. Optimize image loading with memCacheWidth
// // □ 7. Remove all loading indicators from UI
// // □ 8. Test offline functionality
// // □ 9. Measure performance (<100ms target)
// // □ 10. Add batch send API endpoint on backend
