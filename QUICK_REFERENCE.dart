// // ╔═══════════════════════════════════════════════════════════════╗
// // ║           QUICK REFERENCE: RESPONSIVE UI IMPLEMENTATION       ║
// // ╚═══════════════════════════════════════════════════════════════╝
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 1. INITIALIZATION (main.dart)                                │
// // └──────────────────────────────────────────────────────────────┘
//
// await CacheManager.init();                          // Instant cache access
// await OfflineQueueService.initialize(apiService);   // Offline message queue
// BackgroundSyncService(apiService).start();          // Silent sync every 30s
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 2. INSTANT CHAT LIST (ChatProvider)                          │
// // └──────────────────────────────────────────────────────────────┘
//
// // Load cached data FIRST (0ms), sync in background
// final cached = CacheManager.getCachedChatList();
// state = state.copyWith(chats: cached);              // ✅ Instant display
// _syncInBackground();                                 // ⏳ Background API call
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 3. INSTANT MESSAGES (ChatScreen)                             │
// // └──────────────────────────────────────────────────────────────┘
//
// // Load cached messages
// final cached = CacheManager.getCachedMessages(chatId);
// setState(() { _messages = cached; });               // ✅ Instant display
//
// // Background API sync
// final messages = await _apiService.getMessages();
// setState(() { _messages = messages; });             // Silent update
// CacheManager.saveMessages(chatId, messages);        // Cache for next time
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 4. OPTIMISTIC SEND (ChatScreen)                              │
// // └──────────────────────────────────────────────────────────────┘
//
// // Show message IMMEDIATELY
// setState(() { _messages.insert(0, message); });     // ✅ Instant UI
//
// // Sync in background (don't wait)
// OptimisticUpdateHandler(_apiService, userId).sendMessageOptimistic(
//   message: message,
//   chatType: chatType,
//   chatId: chatId,
//   onOptimisticUpdate: (msg) => setState(() { /* update status */ }),
//   onSuccess: (msg) => setState(() { /* finalize */ }),
//   onError: (msg, err) => setState(() { /* mark failed */ }),
// );
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 5. PERFORMANCE RULES                                         │
// // └──────────────────────────────────────────────────────────────┘
//
// // ✅ DO: Load from cache first
// final data = CacheManager.getCached();
// setState(() { show(data); });                       // Instant
//
// // ❌ DON'T: Wait for API
// setState(() { isLoading = true; });                 // Bad UX
// final data = await api.fetch();                     // Blocks UI
//
// // ✅ DO: Background sync
// _syncInBackground();                                 // Silent
//
// // ❌ DON'T: Show loaders
// CircularProgressIndicator()                          // Avoid this
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 6. CACHE OPERATIONS                                          │
// // └──────────────────────────────────────────────────────────────┘
//
// // Save chat list
// await CacheManager.saveChatList(chats);
//
// // Get chat list (instant)
// final chats = CacheManager.getCachedChatList();
//
// // Save messages for chat
// await CacheManager.saveMessages(chatId, messages);
//
// // Get messages for chat (instant)
// final messages = CacheManager.getCachedMessages(chatId);
//
// // Cleanup old cache (>7 days)
// await CacheManager.clearOldCache();
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 7. OFFLINE QUEUE                                             │
// // └──────────────────────────────────────────────────────────────┘
//
// // Check queue status
// final stats = OfflineQueueService.getQueueStats();
// final pending = stats['pending'];                   // Pending count
// final total = stats['total'];                       // Total queued
//
// // Queue message manually (usually automatic)
// await OfflineQueueService.queueMessage(pendingMsg);
//
// // Get pending for specific chat
// final pending = OfflineQueueService.getPendingMessagesForChat(chatId);
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 8. BACKGROUND SYNC                                           │
// // └──────────────────────────────────────────────────────────────┘
//
// // Start background sync
// final bgSync = BackgroundSyncService(apiService);
// bgSync.start();                                     // Auto-syncs every 30s
//
// // Stop background sync (cleanup)
// bgSync.stop();
//
// // Manual sync for specific chat
// await bgSync.syncChatMessages(chatId, chatType);
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 9. IMAGE OPTIMIZATION                                        │
// // └──────────────────────────────────────────────────────────────┘
//
// CachedNetworkImage(
//   imageUrl: url,
//   memCacheWidth: 250,          // Resize for faster decode
//   maxWidthDiskCache: 250,      // Limit disk cache size
//   fadeInDuration: Duration.zero, // No fade = faster feel
//   placeholder: (_, __) => Container(color: Colors.grey[200]),
// )
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 10. PERFORMANCE MONITORING                                   │
// // └──────────────────────────────────────────────────────────────┘
//
// // Measure load time
// final stopwatch = Stopwatch()..start();
// final data = CacheManager.getCachedChatList();
// stopwatch.stop();
// debugPrint('Load time: ${stopwatch.elapsedMilliseconds}ms'); // Should be <100ms
//
// // Check cache hit rate
// final cached = CacheManager.getCachedChatList();
// debugPrint('Cache hit: ${cached.isNotEmpty ? 'YES' : 'NO'}');
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 11. ERROR HANDLING                                           │
// // └──────────────────────────────────────────────────────────────┘
//
// // Always show cached data, sync in background
// try {
//   final cached = CacheManager.getCached();
//   setState(() { show(cached); });                   // ✅ Always show something
//
//   final fresh = await api.fetch();
//   setState(() { show(fresh); });                    // Silent update
//   CacheManager.save(fresh);
// } catch (e) {
//   // Keep showing cached data, don't block user
//   debugPrint('Background sync failed: $e');
// }
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 12. REQUIRED BACKEND APIs                                    │
// // └──────────────────────────────────────────────────────────────┘
//
// // Batch send messages (CRITICAL)
// POST /api/messages/batch-send
// Body: {"messages": [{temp_id, chat_id, message, ...}]}
//
// // Incremental sync (HIGH PRIORITY)
// GET /api/sync/chats?since=2024-01-15T10:00:00Z
//
// // Batch mark as read (MEDIUM)
// POST /api/messages/batch-read
// Body: {"message_ids": [101, 102, 103]}
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 13. PERFORMANCE TARGETS                                      │
// // └──────────────────────────────────────────────────────────────┘
//
// // ✅ Chat list load:    <100ms (instant from cache)
// // ✅ Message load:      <100ms (instant from cache)
// // ✅ Send message:      0ms (optimistic UI)
// // ✅ Screen transition: <50ms (no loader)
// // ✅ Scroll FPS:        60fps (smooth)
// // ✅ Background sync:   Silent (no blocking)
//
// // ┌──────────────────────────────────────────────────────────────┐
// // │ 14. TESTING CHECKLIST                                        │
// // └──────────────────────────────────────────────────────────────┘
//
// // [ ] Open app → Chats appear instantly (<100ms)
// // [ ] Open chat → Messages appear instantly (<100ms)
// // [ ] Send message → Appears immediately (0ms)
// // [ ] No loading spinners visible
// // [ ] Offline mode works fully
// // [ ] Background sync runs silently
// // [ ] Scroll is smooth (60fps)
// // [ ] Images load progressively
// // [ ] Network errors handled gracefully
//
// // ╔═══════════════════════════════════════════════════════════════╗
// // ║  RESULT: WhatsApp-like instant UI with zero loading states   ║
// // ╚═══════════════════════════════════════════════════════════════╝
