import 'package:flutter/cupertino.dart';
import 'package:hive/hive.dart';
import 'chat_hive_model_adapter.dart';

@HiveType(typeId: 1)
class ChatHiveModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String type; // 'group' or 'user'

  @HiveField(2)
  final String name;

  @HiveField(3)
  final String? profilePicture;

  @HiveField(14)
  final String? localImagePath; // Cached local image path

  @HiveField(4)
  final String? lastMessage;

  @HiveField(5)
  final DateTime? lastMessageTime;

  @HiveField(6)
  final int unreadCount;

  @HiveField(7)
  final bool isPinned;

  @HiveField(8)
  final bool? attendanceGroup;

  @HiveField(9)
  final String? actualRole;

  @HiveField(10)
  final DateTime createdAt;

  @HiveField(11)
  final DateTime updatedAt;

  @HiveField(12)
  final DateTime? lastReadAt;

  @HiveField(13)
  final int? memberCount;

  @HiveField(15)
  final String? groupType;

  @HiveField(16)
  final String? role;

  @HiveField(17)
  final String? mobile;

  @HiveField(18)
  final String? className;

  @HiveField(19)
  final String? sectionName;

  @HiveField(20)
  final DateTime? sortTime;

  ChatHiveModel({
    required this.id,
    required this.type,
    required this.name,
    this.profilePicture,
    this.localImagePath,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isPinned = false,
    this.attendanceGroup,
    this.actualRole,
    required this.createdAt,
    required this.updatedAt,
    this.lastReadAt,
    this.memberCount,
    this.groupType,
    this.role,
    this.mobile,
    this.className,
    this.sectionName,
    this.sortTime,
  });

  static bool parseAttendanceGroup(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value == 1;

    final normalized = value.toString().trim().toLowerCase();
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'y';
  }

  static String buildKey({
    required String id,
    required String type,
    dynamic attendanceGroup,
  }) {
    final isAttendanceGroup = parseAttendanceGroup(attendanceGroup);
    return isAttendanceGroup ? '${type}_$id$isAttendanceGroup' : '${type}_$id';
  }

  // Factory from API response
  factory ChatHiveModel.fromApi(Map<String, dynamic> json, {String? localImagePath}) {
    final lastMsgTime = json['last_message_time'] != null
        ? DateTime.tryParse(json['last_message_time'])
        : null;
    
    final sortTime = json['sort_time'] != null
        ? DateTime.tryParse(json['sort_time'])
        : lastMsgTime;
    // debugPrint("💬 Upserted chat:attendanceGroup ${json.toString()}");
    return ChatHiveModel(
      id: json['id'].toString(),
      type: json['type']?.toString() ?? 'user',
      name: json['name'] ?? 'Unknown',
      profilePicture: json['profile_picture'],
      localImagePath: localImagePath,
      lastMessage: json['last_message'],
      lastMessageTime: lastMsgTime,
      unreadCount: (json['unread_count'] is int) ? json['unread_count'] : (int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0),
      isPinned: parseAttendanceGroup(json['is_pinned']),
      attendanceGroup: parseAttendanceGroup(json['attendance_group']),
      actualRole: json['actual_role']?.toString(),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      lastReadAt: json['last_read_at'] != null
          ? DateTime.tryParse(json['last_read_at'])
          : null,
      memberCount: int.tryParse(json['member_count']?.toString() ?? ''),
      groupType: json['group_type']?.toString(),
      role: json['role']?.toString(),
      mobile: json['mobile']?.toString(),
      className: json['class_name']?.toString(),
      sectionName: json['section_name']?.toString(),
      sortTime: sortTime,
    );
  }

  // Convert to domain Chat model
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'profile_picture': profilePicture,
      'local_image_path': localImagePath,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'unread_count': unreadCount,
      'is_pinned': isPinned,
      'attendance_group': attendanceGroup,
      'actual_role': actualRole,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_read_at': lastReadAt?.toIso8601String(),
      'member_count': memberCount,
      'group_type': groupType,
      'role': role,
      'mobile': mobile,
      'class_name': className,
      'section_name': sectionName,
      'sort_time': sortTime?.toIso8601String(),
    };
  }

  // Check if chat needs update
  bool needsUpdate(ChatHiveModel other) {
    final thisTime = sortTime ?? lastMessageTime ?? updatedAt;
    final otherTime = other.sortTime ?? other.lastMessageTime ?? other.updatedAt;
    
    return thisTime.isBefore(otherTime) ||
        unreadCount != other.unreadCount ||
        isPinned != other.isPinned ||
        lastMessage != other.lastMessage ||
        name != other.name ||
        profilePicture != other.profilePicture ||
        attendanceGroup != other.attendanceGroup;
  }

  // Get image path (local first, then remote)
  String? get imagePath => localImagePath ?? profilePicture;

  // Copy with for updates
  ChatHiveModel copyWith({
    String? name,
    String? profilePicture,
    String? localImagePath,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isPinned,
    DateTime? updatedAt,
    DateTime? lastReadAt,
  }) {
    return ChatHiveModel(
      id: id,
      type: type,
      name: name ?? this.name,
      profilePicture: profilePicture ?? this.profilePicture,
      localImagePath: localImagePath ?? this.localImagePath,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      attendanceGroup: attendanceGroup,
      actualRole: actualRole,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      memberCount: memberCount,
      groupType: groupType,
      role: role,
      mobile: mobile,
      className: className,
      sectionName: sectionName,
      sortTime: sortTime,
    );
  }

  String getUniqueKey() {
    final key = buildKey(
      id: id,
      type: type,
      attendanceGroup: attendanceGroup,
    );
    // debugPrint("💬 Upserted chat:attendanceGroup $key");
    return key;
  }
}
