import 'package:hive/hive.dart';
import '../models/message_model.dart';

// part 'message_hive_model.g.dart';

@HiveType(typeId: 2)
class MessageHiveModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String chatId;

  @HiveField(2)
  final String senderId;

  @HiveField(3)
  final String? senderName;

  @HiveField(4)
  final String text;

  @HiveField(5)
  final String type;

  @HiveField(6)
  final String timestamp;

  @HiveField(7)
  final Map<String, String> status;

  @HiveField(8)
  final String? fileUrl;

  @HiveField(9)
  final String? firebaseId;

  @HiveField(10)
  final String? fileName;

  @HiveField(11)
  final int? fileSize;

  @HiveField(12)
  final String? msgId;

  @HiveField(13)
  final String? replyToId;

  @HiveField(14)
  final bool isForwarded;

  MessageHiveModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.senderName,
    required this.text,
    required this.type,
    required this.timestamp,
    required this.status,
    this.fileUrl,
    this.firebaseId,
    this.fileName,
    this.fileSize,
    this.msgId,
    this.replyToId,
    this.isForwarded = false,
  });

  factory MessageHiveModel.fromMessage(Message message) {
    return MessageHiveModel(
      id: message.id,
      chatId: message.chatId,
      senderId: message.senderId,
      senderName: message.senderName,
      text: message.text,
      type: message.type,
      timestamp: message.timestamp.toIso8601String(),
      status: message.status,
      fileUrl: message.fileUrl,
      firebaseId: message.firebaseId,
      fileName: message.fileName,
      fileSize: message.fileSize,
      msgId: message.msgId,
      replyToId: message.replyToId,
      isForwarded: message.isForwarded,
    );
  }

  Message toMessage() {
    return Message(
      id: id,
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      type: type,
      timestamp: DateTime.parse(timestamp),
      status: status,
      fileUrl: fileUrl,
      firebaseId: firebaseId,
      fileName: fileName,
      fileSize: fileSize,
      msgId: msgId,
      replyToId: replyToId,
      isForwarded: isForwarded,
    );
  }
}
