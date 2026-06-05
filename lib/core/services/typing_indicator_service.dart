import 'package:firebase_database/firebase_database.dart';

class TypingIndicatorService {
  static final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Set typing status for a chat
  static Future<void> setTyping(String chatId, String userId, bool isTyping) async {
    try {
      await _database
          .child('typing')
          .child(chatId)
          .child(userId)
          .set(isTyping ? ServerValue.timestamp : null);
    } catch (e) {
      print('Error setting typing status: $e');
    }
  }

  // Listen to typing indicators for a chat
  static Stream<Map<String, bool>> listenToTyping(String chatId, String currentUserId) {
    return _database
        .child('typing')
        .child(chatId)
        .onValue
        .map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <String, bool>{};

      final typingUsers = <String, bool>{};
      data.forEach((userId, timestamp) {
        if (userId != currentUserId && timestamp != null) {
          // Consider user typing if timestamp is within last 3 seconds
          final now = DateTime.now().millisecondsSinceEpoch;
          final typingTime = timestamp as int;
          typingUsers[userId] = (now - typingTime) < 3000;
        }
      });
      return typingUsers;
    });
  }

  // Clear typing status when user stops typing
  static Future<void> clearTyping(String chatId, String userId) async {
    try {
      await _database
          .child('typing')
          .child(chatId)
          .child(userId)
          .remove();
    } catch (e) {
      print('Error clearing typing status: $e');
    }
  }
}