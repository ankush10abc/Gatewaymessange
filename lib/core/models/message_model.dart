import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

T safeParse<T>(
  String key,
  dynamic Function() parser, {
  required String messageId,
}) {
  try {
    return parser();
  } catch (e, stack) {
    debugPrint('❌ Error parsing key: "$key"');
    debugPrint('Message ID: $messageId');
    debugPrint('Exception: $e');
    debugPrint('StackTrace: $stack');
    rethrow; // important – so you see failure
  }
}

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String? senderName;
  final String text;
  final String type;
  final DateTime timestamp;
  final Map<String, String> status;
  final String? fileUrl;
  final String? firebaseId;
  final String? fileName;
  final int? fileSize;
  final String? replyToId;
  final String? readAt;
  final String? file_path;
  final String? msgId;
  final Message? replyToMessage;
  final bool isForwarded;
  final dynamic reply_type;
  final dynamic profile_picture_url;
  final Map<String, dynamic>? metadata;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.senderName,
    this.msgId,
    required this.text,
    required this.type,
    this.file_path,
    this.reply_type,
    required this.timestamp,
    required this.status,
    this.fileUrl,
    this.firebaseId,
    this.fileName,
    this.fileSize,
    this.replyToId,
    this.readAt,
    this.replyToMessage,
    this.isForwarded = false,
    this.metadata,
    this.profile_picture_url,
  });

  static String resolveMessageId(Map<dynamic, dynamic> json) {
    final msgIdValue = json['msgId']?.toString().trim();
    final idValue = json['id']?.toString().trim();

    if (msgIdValue != null && msgIdValue.isNotEmpty && msgIdValue != '0') {
      return msgIdValue;
    }

    if (idValue != null && idValue.isNotEmpty && idValue != '0') {
      return idValue;
    }

    return '';
  }

  static String resolveStorageKey(Message message) {
    final candidates = [
      message.firebaseId,
      message.msgId,
      message.id,
    ];

    for (final candidate in candidates) {
      final key = candidate?.trim();
      if (key != null && key.isNotEmpty && key != '0') {
        return key;
      }
    }

    return 'msg_${message.timestamp.millisecondsSinceEpoch}';
  }

  factory Message.fromJson(Map<dynamic, dynamic> json) {
    String id = '';
    // Parse status early so fallback path can use it
    final Map<String, String> status = parseStatus(json['status']);
    debugPrint("Ankush Value  fromJson status=$status");
    try {
      // Priority: msgId -> id, but skip empty/zero values.
      id = resolveMessageId(json);
    } catch (e) {
      debugPrint('Error parsing message id: $e');
      id = '';
    }
    try {
      // return Message(
      //       // id:  json['msgId'] ?? json['id']?.toString() ?? '',
      //       id:  id,
      //       chatId: json['group_id']?.toString() ?? json['receiver_id']?.toString() ?? json['chat_id']?.toString() ?? '',
      //       senderId: json['sender_id']?.toString() ?? json['sender']?['id'] ?? '',
      //       senderName: json['sender_name'] ?? json['senderName'] ?? json['sender']?['name'] ?? '',
      //       msgId: json['msgId'] ??  '',
      //       profile_picture_url: json['profile_picture_url'] ?? json['profile_picture_url'] ?? json['sender']?['profile_picture_url'],
      //       text: json['content'] ?? json['text'] ?? json['message'] ?? '',
      //       type: json['type'] ?? 'text',
      //       file_path: json['file_path'] ?? '',
      //       reply_type: json['reply_type'] ?? '',
      //       timestamp: json['created_at'] != null
      //           ? DateTime.parse(json['created_at'])
      //           : (json['timestamp'] != null
      //               ? DateTime.parse(json['timestamp'])
      //               : DateTime.now()),
      //       status: status,
      //       fileUrl: json['file_url'],
      //       fileName: json['file_name'] ?? '',
      //       fileSize: json['file_size'] ?? 0,
      //       replyToId: json['reply_to_message_id'] != null ?  json['reply_to_message_id'].toString() : '',
      //       replyToMessage: json['reply_to_message'] != null
      //           ? Message.fromJson(json['reply_to_message'] ?? json['reply_to_message']['reply_to_message'])
      //           : null,
      //       isForwarded: json['is_forwarded'] ?? false,
      //       metadata: json['metadata']?? null,
      //     );
      return Message(
        id: id,
        chatId: safeParse(
          'chatId',
          () =>
              json['group_id']?.toString() ??
              json['receiver_id']?.toString() ??
              json['chat_id']?.toString() ??
              '',
          messageId: id,
        ),
        senderId: safeParse(
          'senderId',
          () =>
              json['sender_id']?.toString() ??
              json['sender']?['id']?.toString() ??
              '',
          messageId: id,
        ),
        senderName: safeParse(
          'senderName',
          () =>
              json['sender_name'] ??
              json['senderName'] ??
              json['sender']?['name'] ??
              '',
          messageId: id,
        ),
        msgId: safeParse(
          'msgId',
          () => json['msgId']?.toString() ?? '',
          messageId: id,
        ),
        profile_picture_url: safeParse(
          'profile_picture_url',
          () =>
              json['profile_picture_url'] ??
              json['sender']?['profile_picture_url'],
          messageId: id,
        ),
        text: safeParse(
          'text',
          () => json['content'] ?? json['text'] ?? json['message'] ?? '',
          messageId: id,
        ),
        type: safeParse(
          'type',
          () => json['type'] ?? 'text',
          messageId: id,
        ),
        file_path: safeParse(
          'file_path',
          () => json['file_path'] ?? '',
          messageId: id,
        ),
        reply_type: safeParse(
          'reply_type',
          () => json['reply_type'] ?? '',
          messageId: id,
        ),
        timestamp: safeParse(
          'timestamp',
          () {
            if (json['created_at'] != null) {
              return DateTime.parse(json['created_at'].toString());
            } else if (json['timestamp'] != null) {
              return DateTime.parse(json['timestamp'].toString());
            }
            return DateTime.now();
          },
          messageId: id,
        ),
        status: safeParse(
          'status',
          () => parseStatus(json['status']),
          messageId: id,
        ),
        fileUrl: safeParse(
          'file_url',
          () => json['file_url'],
          messageId: id,
        ),
        firebaseId: safeParse(
          'firebaseId',
          () => json['firebaseId'],
          messageId: id,
        ),
        fileName: safeParse(
          'file_name',
          () => json['file_name'] ?? '',
          messageId: id,
        ),
        fileSize: safeParse(
          'file_size',
          () => int.tryParse(json['file_size']?.toString() ?? '') ?? 0,
          messageId: id,
        ),
        replyToId: safeParse(
          'reply_to_message_id',
          () => json['reply_to_message_id']?.toString() ?? '',
          messageId: id,
        ),
        readAt: safeParse(
          'read_at',
          () => json['read_at']?.toString() ?? '',
          messageId: id,
        ),
        replyToMessage: safeParse(
          'reply_to_message',
          () => json['reply_to_message'] is Map
              ? Message.fromJson(
                  Map<String, dynamic>.from(json['reply_to_message']),
                )
              : null,
          messageId: id,
        ),
        isForwarded: safeParse(
          'is_forwarded',
          () => json['is_forwarded'] == true,
          messageId: id,
        ),
        metadata: safeParse(
          'metadata',
          () {
            final meta = json['metadata'];
            if (meta == null) return null;
            if (meta is Map<String, dynamic>) return meta;
            if (meta is Map) return Map<String, dynamic>.from(meta);
            return null;
          },
          messageId: id,
        ),
      );
    } catch (e) {
      print("Error parsing message Model $e");
      final fallbackId = resolveMessageId(json);
      return Message(
        id: fallbackId,
        chatId: json['group_id']?.toString() ??
            json['receiver_id']?.toString() ??
            json['chat_id']?.toString() ??
            '',
        senderId: json['sender_id']?.toString() ?? json['sender']?['id'] ?? '',
        senderName: json['sender_name'] ??
            json['senderName'] ??
            json['sender']?['name'] ??
            '',
        msgId: json['msgId']?.toString() ?? '',
        profile_picture_url: json['profile_picture_url'] ??
            json['profile_picture_url'] ??
            json['sender']?['profile_picture_url'],
        text: json['content'] ?? json['text'] ?? json['message'] ?? '',
        type: json['type'] ?? 'text',
        file_path: json['file_path'] ?? '',
        reply_type: json['reply_type'] ?? '',
        timestamp: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : (json['timestamp'] != null
                ? DateTime.parse(json['timestamp'])
                : DateTime.now()),
        status: status,
        fileUrl: json['file_url'],
        fileName: json['file_name'] ?? '',
        fileSize: json['file_size'] ?? 0,
        replyToId: json['reply_to_message_id'] != null
            ? json['reply_to_message_id'].toString()
            : '',
        readAt: json['read_at'] != null ? json['read_at'].toString() : '',
        // replyToMessage: json['reply_to_message'] != null
        //     ? Message.fromJson(json['reply_to_message'] ?? json['reply_to_message']['reply_to_message'])
        //     : null,
        isForwarded: json['is_forwarded'] ?? false,
        metadata: json['metadata'] ?? null,
      );
    }
  }

  // Firebase Firestore conversion
  factory Message.fromFirestore(Map<String, dynamic> data, String id) {
    return Message(
      id: id,
      chatId: data['chatId'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'],
      text: data['text'] ?? '',
      type: data['type'] ?? 'text',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: parseStatus(data['status']),
      fileUrl: data['fileUrl'],
      fileName: data['fileName'],
      fileSize: data['fileSize'],
      msgId: data['msgId'],
      replyToId: data['replyToId'],
      readAt: data['read_at'],
      replyToMessage: data['replyToMessage'] != null
          ? Message.fromFirestore(
              Map<String, dynamic>.from(data['replyToMessage']), '')
          : null,
      isForwarded: data['isForwarded'] ?? false,
      metadata: data['metadata'],
      profile_picture_url: data['profile_picture_url'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'chatId': chatId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'type': type,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'replyToId': replyToId,
      'read_at': readAt,
      'replyToMessage': replyToMessage?.toFirestore(),
      'isForwarded': isForwarded,
      'metadata': metadata,
      'profile_picture_url': profile_picture_url,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'msgId': msgId,
      'firebaseId': firebaseId,
      'chat_id': chatId,
      'senderId': senderId,
      'sender_id': senderId,
      'senderName': senderName,
      'sender_name': senderName,
      'text': text,
      'content': text,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
      'file_url': fileUrl,
      'file_path': file_path,
      'file_name': fileName,
      'file_size': fileSize,
      'reply_to_id': replyToId,
      'reply_to_message_id': replyToId,
      'read_at': readAt,
      'reply_to_message': replyToMessage?.toJson(),
      'is_forwarded': isForwarded,
      'reply_type': reply_type,
      'metadata': metadata,
      'profile_picture_url': profile_picture_url,
    };
  }

  bool get isTextMessage => type == 'text';
  bool get isImageMessage => type == 'image';
  bool get isFileMessage => type == 'file';
  bool get isVideoMessage => type == 'video';

  String getStatusForUser(String userId) {
    debugPrint("firebaseId userId$userId");
    debugPrint("firebaseId status${status.toString()}");
    return status[userId] ?? 'sent';
  }

  bool isReadBy(String userId) {
    return getStatusForUser(userId) == 'read';
  }

  bool isDeliveredTo(String userId) {
    final userStatus = getStatusForUser(userId);
    return userStatus == 'delivered' || userStatus == 'read';
  }

  // Get display status for message (single tick, double tick, blue tick)
  String getDisplayStatus(List<String> participants) {
    final otherParticipants =
        participants.where((id) => id != senderId).toList();
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

    if (allRead && otherParticipants.isNotEmpty) return 'read';
    if (anyDelivered) return 'delivered';
    return 'sent';
  }

  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? senderName,
    String? text,
    String? type,
    DateTime? timestamp,
    Map<String, String>? status,
    String? fileUrl,
    String? file_path,
    String? firebaseId,
    String? fileName,
    int? fileSize,
    String? replyToId,
    String? readAt,
    String? reply_type,
    Message? replyToMessage,
    bool? isForwarded,
    dynamic? profile_picture_url,
    Map<String, dynamic>? metadata,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      text: text ?? this.text,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      fileUrl: fileUrl ?? this.fileUrl,
      file_path: file_path ?? this.file_path,
      firebaseId: firebaseId ?? this.firebaseId,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      replyToId: replyToId ?? this.replyToId,
      readAt: readAt ?? this.readAt,
      reply_type: reply_type ?? this.reply_type,
      replyToMessage: replyToMessage ?? this.replyToMessage,
      isForwarded: isForwarded ?? this.isForwarded,
      metadata: metadata ?? this.metadata,
      profile_picture_url: profile_picture_url ?? this.profile_picture_url,
    );
  }
}

/// Prefix a userId so Firebase never converts the status map to an array.
/// Firebase converts maps with small consecutive integer keys (e.g. {1:x, 3:x})
/// to arrays ([null,x,null,x]) when max_key < 2*count. Prefixing with 'u'
/// makes keys non-numeric, preventing the conversion entirely.
String statusKey(String userId) {
  if (userId.isEmpty || userId == 'default') return userId;
  // Already prefixed — idempotent
  if (userId.startsWith('u') && int.tryParse(userId.substring(1)) != null) {
    return userId;
  }
  // Only prefix purely numeric IDs
  if (int.tryParse(userId) != null) return 'u$userId';
  return userId;
}

/// Reverse of statusKey — strip the 'u' prefix to get the raw userId.
String rawUserId(String key) {
  if (key.startsWith('u') && int.tryParse(key.substring(1)) != null) {
    return key.substring(1);
  }
  return key;
}

Map<String, String> parseStatus(dynamic value) {
  if (value is String) {
    // Legacy: single string status stored as default key
    return {'default': value};
  } else if (value is List) {
    // Firebase converted the map to an array because keys were small integers
    // e.g. {'1':'sent','3':'sent'} → [null,'sent',null,'sent']
    // Reconstruct as prefixed map: index → 'u{index}' key
    final result = <String, String>{};
    for (var i = 0; i < value.length; i++) {
      final v = value[i];
      if (v == null) continue;
      // Use prefixed key so future writes stay as map
      result[statusKey(i.toString())] = v.toString();
    }
    return result;
  } else if (value is Map) {
    // Convert any Map — normalize keys to prefixed form and values to String
    final result = <String, String>{};
    for (final entry in value.entries) {
      final k = entry.key?.toString();
      final v = entry.value;
      if (k == null || k.isEmpty) continue;
      if (v == null) continue;
      // Normalize key: prefix numeric IDs, keep 'default' and already-prefixed keys
      result[statusKey(k)] = v.toString();
    }
    return result;
  }
  return {};
}
