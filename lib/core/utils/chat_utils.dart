class ChatUtils {
  /// Generate consistent chat ID for both group and one-to-one chats
  static String generateChatId(String chatId, {String? currentUserId, String? otherUserId, String? chatType, bool? attendanceGroup}) {
    // Use chatType if provided
    if (chatType == 'group') {
      return attendanceGroup == true ? 'group_${chatId}true' : 'group_$chatId';
    }
    
    if (chatType == 'private' || chatType == 'user') {
      if (currentUserId != null && otherUserId != null) {
        final ids = [currentUserId, otherUserId]..sort();
        return 'private_${ids[0]}_${ids[1]}';
      }
      return 'private_$chatId';
    }
    
    // Fallback: detect from chatId format
    if (chatType!.contains('group') ) {
      return attendanceGroup == true ? 'group_${chatId}true' : 'group_$chatId';
    }
    
    // Default to private chat
    if (currentUserId != null && otherUserId != null) {
      final ids = [currentUserId, otherUserId]..sort();
      return 'private_${ids[0]}_${ids[1]}';
    }
    
    return 'private_$chatId';
  }
  
  /// Update message read status
  static Map<String, String> updateMessageStatus(Map<String, String> currentStatus, String userId, String status) {
    final updatedStatus = Map<String, String>.from(currentStatus);
    updatedStatus[userId] = status;
    return updatedStatus;
  }
  
  /// Check if message is read by user
  static bool isMessageRead(Map<String, String> status, String userId) {
    return status[userId] == 'read';
  }
  
  /// Get message status for display (single tick, double tick, blue tick)
  static String getMessageStatusDisplay(Map<String, String> status, String senderId, List<String> participants) {
    if (status.isEmpty) return 'sent';
    
    final otherParticipants = participants.where((id) => id != senderId).toList();
    if (otherParticipants.isEmpty) return 'sent';
    
    bool allRead = true;
    bool anyDelivered = false;
    
    for (final userId in otherParticipants) {
      final userStatus = status[userId] ?? 'sent';
      if (userStatus == 'read') {
        continue;
      } else if (userStatus == 'delivered') {
        allRead = false;
        anyDelivered = true;
      } else {
        allRead = false;
      }
    }
    
    if (allRead) return 'read';
    if (anyDelivered) return 'delivered';
    return 'sent';
  }
}