import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';

class ChatListManager {
  static Box? _chatListBox;
  static bool _initialized = false;
  static String? _currentUserId;

  static Future<void> init(String currentUserId) async {
    if (_initialized) return;
    try {
      _currentUserId = currentUserId;
      _chatListBox = await Hive.openBox('whatsapp_chat_list_$currentUserId');
      _initialized = true;
      debugPrint('✅ ChatListManager initialized for user: $currentUserId');
    } catch (e) {
      debugPrint('❌ ChatListManager init error: $e');
    }
  }

  /// Get sorted chat list (pinned first, then by lastMessageTime descending)
  static List<Chat> getSortedChatList() {
    if (!_initialized || _chatListBox == null) return [];
    
    try {
      final chatMaps = _chatListBox!.values.cast<Map>().toList();
      final chats = chatMaps
          .map((e) => Chat.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      
      return _sortChats(chats);
    } catch (e) {
      debugPrint('❌ Get sorted chat list error: $e');
      return [];
    }
  }

  /// Sort chats: pinned first, then by lastMessageTime descending
  static List<Chat> _sortChats(List<Chat> chats) {
    chats.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      
      final aTime = a.getLastMessageTime();
      final bTime = b.getLastMessageTime();
      return bTime.compareTo(aTime);
    });
    
    return chats;
  }

  /// Update chat when user sends a message (instant update, move to top)
  static Future<void> onMessageSent({
    required String chatId,
    required String chatType,
    required Message message,
    required String currentUserId,
  }) async {
    if (!_initialized || _chatListBox == null) return;

    try {
      final existingChatData = _chatListBox!.get(chatId);
      
      if (existingChatData != null) {
        final chat = Chat.fromJson(Map<String, dynamic>.from(existingChatData));
        
        final updatedChat = chat.copyWith(
          lastMessage: message,
          lastMessageTime: message.timestamp,
          updatedAt: message.timestamp,
        );
        
        await _chatListBox!.put(chatId, updatedChat.toJson());
        debugPrint('✅ Updated chat $chatId after sending message (time: ${message.timestamp})');
      } else {
        await _createNewChat(
          chatId: chatId,
          chatType: chatType,
          message: message,
          currentUserId: currentUserId,
        );
      }
    } catch (e) {
      debugPrint('❌ onMessageSent error: $e');
    }
  }

  /// Update chat when receiving a message (real-time update, move to top, increment unread)
  static Future<void> onMessageReceived({
    required String chatId,
    required String chatType,
    required Message message,
    required String currentUserId,
    required bool isChatScreenOpen,
  }) async {
    if (!_initialized || _chatListBox == null) return;

    try {
      final existingChatData = _chatListBox!.get(chatId);
      
      if (existingChatData != null) {
        final chat = Chat.fromJson(Map<String, dynamic>.from(existingChatData));
        
        final newUnreadCount = Map<String, int>.from(chat.unreadCount);
        if (!isChatScreenOpen && message.senderId != currentUserId) {
          newUnreadCount[currentUserId] = (newUnreadCount[currentUserId] ?? 0) + 1;
        }
        
        int apiUnreadCount = 0;
        if (chat.unread_count != null) {
          if (chat.unread_count is int) {
            apiUnreadCount = !isChatScreenOpen && message.senderId != currentUserId 
                ? (chat.unread_count as int) + 1 
                : (chat.unread_count as int);
          }
        } else if (!isChatScreenOpen && message.senderId != currentUserId) {
          apiUnreadCount = 1;
        }
        
        final updatedChat = chat.copyWith(
          lastMessage: message,
          lastMessageTime: message.timestamp,
          updatedAt: message.timestamp,
          unreadCount: newUnreadCount,
          unread_count: apiUnreadCount,
        );
        
        await _chatListBox!.put(chatId, updatedChat.toJson());
        debugPrint('✅ Updated chat $chatId after receiving message (unread: $apiUnreadCount, time: ${message.timestamp})');
      } else {
        await _createNewChat(
          chatId: chatId,
          chatType: chatType,
          message: message,
          currentUserId: currentUserId,
          isIncoming: true,
          isChatScreenOpen: isChatScreenOpen,
        );
      }
    } catch (e) {
      debugPrint('❌ onMessageReceived error: $e');
    }
  }

  /// Create new chat entry when first message arrives
  static Future<void> _createNewChat({
    required String chatId,
    required String chatType,
    required Message message,
    required String currentUserId,
    bool isIncoming = false,
    bool isChatScreenOpen = false,
  }) async {
    if (_chatListBox == null) return;

    try {
      final unreadCount = <String, int>{};
      if (isIncoming && !isChatScreenOpen && message.senderId != currentUserId) {
        unreadCount[currentUserId] = 1;
      }

      final newChat = Chat(
        id: chatId,
        type: chatType,
        participants: [currentUserId, message.senderId],
        lastMessage: message,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastMessageTime: message.timestamp,
        unreadCount: unreadCount,
        groupName: message.senderName,
      );

      await _chatListBox!.put(chatId, newChat.toJson());
      debugPrint('✅ Created new chat $chatId');
    } catch (e) {
      debugPrint('❌ Create new chat error: $e');
    }
  }

  /// Reset unread count when user opens chat screen
  static Future<void> resetUnreadCount(String chatId, String currentUserId) async {
    if (!_initialized || _chatListBox == null) return;

    try {
      final existingChatData = _chatListBox!.get(chatId);
      if (existingChatData != null) {
        final chat = Chat.fromJson(Map<String, dynamic>.from(existingChatData));
        
        final newUnreadCount = Map<String, int>.from(chat.unreadCount);
        newUnreadCount[currentUserId] = 0;
        
        final updatedChat = chat.copyWith(unreadCount: newUnreadCount);
        await _chatListBox!.put(chatId, updatedChat.toJson());
        
        debugPrint('✅ Reset unread count for chat $chatId');
      }
    } catch (e) {
      debugPrint('❌ Reset unread count error: $e');
    }
  }

  /// Get specific chat
  static Chat? getChat(String chatId) {
    if (!_initialized || _chatListBox == null) return null;
    
    try {
      final chatData = _chatListBox!.get(chatId);
      if (chatData != null) {
        return Chat.fromJson(Map<String, dynamic>.from(chatData));
      }
    } catch (e) {
      debugPrint('❌ Get chat error: $e');
    }
    return null;
  }

  /// Bulk update chat list from API (merge with existing, avoid duplicates)
  static Future<void> syncFromAPI(List<Chat> apiChats) async {
    if (!_initialized || _chatListBox == null) return;

    try {
      for (final apiChat in apiChats) {
        final existingChatData = _chatListBox!.get(apiChat.id);
        
        if (existingChatData != null) {
          final existingChat = Chat.fromJson(Map<String, dynamic>.from(existingChatData));
          
          final apiLastMessageTime = apiChat.getLastMessageTime();
          final existingLastMessageTime = existingChat.getLastMessageTime();
          
          if (apiLastMessageTime.isAfter(existingLastMessageTime) || 
              apiLastMessageTime.isAtSameMomentAs(existingLastMessageTime)) {
            final mergedChat = existingChat.copyWith(
              lastMessage: apiChat.lastMessage ?? existingChat.lastMessage,
              lastMessageTime: apiChat.lastMessageTime ?? existingChat.lastMessageTime,
              updatedAt: apiChat.updatedAt,
              isPinned: apiChat.isPinned,
              groupName: apiChat.groupName ?? existingChat.groupName,
              profile_picture: apiChat.profile_picture ?? existingChat.profile_picture,
              unread_count: apiChat.unread_count ?? existingChat.unread_count,
              actual_role: apiChat.actual_role ?? existingChat.actual_role,
              attendance_group: apiChat.attendance_group ?? existingChat.attendance_group,
            );
            await _chatListBox!.put(apiChat.id, mergedChat.toJson());
          }
        } else {
          await _chatListBox!.put(apiChat.id, apiChat.toJson());
        }
      }
      
      debugPrint('✅ Synced ${apiChats.length} chats from API');
    } catch (e) {
      debugPrint('❌ Sync from API error: $e');
    }
  }

  /// Delete chat
  static Future<void> deleteChat(String chatId) async {
    if (!_initialized || _chatListBox == null) return;
    
    try {
      await _chatListBox!.delete(chatId);
      debugPrint('✅ Deleted chat $chatId');
    } catch (e) {
      debugPrint('❌ Delete chat error: $e');
    }
  }

  /// Clear all chats
  static Future<void> clearAll() async {
    if (!_initialized || _chatListBox == null) return;
    
    try {
      await _chatListBox!.clear();
      debugPrint('✅ Cleared all chats');
    } catch (e) {
      debugPrint('❌ Clear all chats error: $e');
    }
  }

  /// Check if chat exists
  static bool chatExists(String chatId) {
    if (!_initialized || _chatListBox == null) return false;
    return _chatListBox!.containsKey(chatId);
  }
}
