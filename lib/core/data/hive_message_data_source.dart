import 'package:hive_flutter/hive_flutter.dart';
import '../models/message_hive_model.dart';
import '../models/message_model.dart';

class HiveMessageDataSource {
  static final HiveMessageDataSource _instance = HiveMessageDataSource._internal();
  factory HiveMessageDataSource() => _instance;
  HiveMessageDataSource._internal();

  static const String _boxPrefix = 'messages_';

  Future<Box<MessageHiveModel>> _getBox(String chatId) async {
    final boxName = '$_boxPrefix$chatId';
    if (!Hive.isBoxOpen(boxName)) {
      return await Hive.openBox<MessageHiveModel>(boxName);
    }
    return Hive.box<MessageHiveModel>(boxName);
  }

  Future<void> saveMessages(String chatId, List<Message> messages) async {
    final box = await _getBox(chatId);
    final Map<String, MessageHiveModel> messagesMap = {};
    
    for (final message in messages) {
      final key = message.firebaseId ?? message.msgId ?? message.id;
      if (key.isNotEmpty) {
        messagesMap[key] = MessageHiveModel.fromMessage(message);
      }
    }
    
    await box.putAll(messagesMap);
  }

  Future<void> saveMessage(String chatId, Message message) async {
    final box = await _getBox(chatId);
    final key = message.firebaseId ?? message.msgId ?? message.id;
    if (key.isNotEmpty) {
      await box.put(key, MessageHiveModel.fromMessage(message));
    }
  }

  Future<List<Message>> getMessages(String chatId, {int limit = 50}) async {
    final box = await _getBox(chatId);
    final messages = box.values
        .map((hiveMsg) => hiveMsg.toMessage())
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return limit > 0 ? messages.take(limit).toList() : messages;
  }

  Stream<List<Message>> watchMessages(String chatId, {int limit = 50}) async* {
    final box = await _getBox(chatId);
    
    yield* box.watch().map((_) {
      final messages = box.values
          .map((hiveMsg) => hiveMsg.toMessage())
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      return limit > 0 ? messages.take(limit).toList() : messages;
    });
  }

  Future<void> deleteMessage(String chatId, String messageId) async {
    final box = await _getBox(chatId);
    await box.delete(messageId);
  }

  Future<void> clearMessages(String chatId) async {
    final box = await _getBox(chatId);
    await box.clear();
  }
}
