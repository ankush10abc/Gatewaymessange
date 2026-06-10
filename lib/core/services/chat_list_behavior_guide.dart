/// WhatsApp-like Chat List Behavior Implementation
/// 
/// This implementation ensures that:
/// 1. When you send a message to any user, that conversation moves to the top
/// 2. When you receive a message, that conversation moves to the top
/// 3. Chat list is always sorted by most recent message (lastMessageTime)
/// 4. Unread counts are incremented only for incoming messages
/// 5. Updates happen instantly without full API refresh
/// 6. No loading indicators during chat position updates
/// 
/// Architecture:
/// 
/// ┌─────────────────┐
/// │   HomeScreen    │ ← Displays chat list sorted by lastMessageTime
/// └────────┬────────┘
///          │
///          ↓
/// ┌─────────────────────────┐
/// │ OptimizedChatProvider   │ ← Manages chat list state
/// └────────┬────────────────┘
///          │
///          ↓
/// ┌─────────────────────────┐
/// │   ChatRepository        │ ← Business logic layer
/// └────────┬────────────────┘
///          │
///          ↓
/// ┌─────────────────────────┐
/// │  HiveChatDataSource     │ ← Local storage with auto-sorting
/// └─────────────────────────┘
///
/// 
/// Flow for Outgoing Message:
/// 
/// 1. User types message in ChatScreen
/// 2. Message sent via _sendMessage()
/// 3. After successful send, ChatListUpdateService.updateOnMessageSent() is called
/// 4. This updates Hive with new lastMessage and lastMessageTime
/// 5. Chat is automatically moved to top due to sorting logic
/// 6. HomeScreen UI updates instantly (no loader)
/// 
/// 
/// Flow for Incoming Message:
/// 
/// 1. Firebase notification received in HomeScreen
/// 2. _handleIncomingMessage() processes the notification
/// 3. Calls optimizedChatProvider.updateChatWithMessage()
/// 4. Updates Hive with new message and increments unread count
/// 5. Chat moves to top automatically
/// 6. UI updates instantly
/// 
/// 
/// Key Files:
/// 
/// - lib/features/home/home_screen.dart
///   → Displays chat list
///   → Handles incoming message notifications
///   
/// - lib/features/chat/chat_screen.dart
///   → Calls ChatListUpdateService when message is sent
///   
/// - lib/shared/providers/optimized_chat_provider.dart
///   → updateChatWithMessage() method for real-time updates
///   
/// - lib/core/repositories/chat_repository.dart
///   → updateChatWithNewMessage() handles business logic
///   
/// - lib/core/data/hive_chat_data_source.dart
///   → getAllChats() returns chats sorted by lastMessageTime (descending)
///   → updateChatLastMessage() updates message and timestamp
///   
/// - lib/core/services/chat_list_update_service.dart
///   → Helper service called from ChatScreen after sending messages
///   
/// 
/// Sorting Logic (in HiveChatDataSource.getAllChats()):
/// 
/// chats.sort((a, b) {
///   // 1. Pinned chats first
///   if (a.isPinned && !b.isPinned) return -1;
///   if (!a.isPinned && b.isPinned) return 1;
///   
///   // 2. Then by lastMessageTime (newest first)
///   final aTime = a.lastMessageTime ?? a.updatedAt;
///   final bTime = b.lastMessageTime ?? b.updatedAt;
///   return bTime.compareTo(aTime); // Descending
/// });
/// 
/// 
/// Performance Optimizations:
/// 
/// 1. No API call needed for position updates
/// 2. All updates happen in local Hive storage (instant)
/// 3. Chat list re-sorts automatically when timestamp changes
/// 4. Background API sync keeps data fresh without blocking UI
/// 5. No duplicate chat entries (using chatId as key)
/// 
/// 
/// Offline Support:
/// 
/// - Outgoing messages: Queued and chat list updated immediately
/// - Incoming messages: Applied when connection restored
/// - Chat list positions preserved across app restarts
/// - Syncs with server when online to ensure consistency
