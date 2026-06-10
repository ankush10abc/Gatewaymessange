import 'message_model.dart';
import 'user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Chat {
  final String id;
  final String type;
  final List<String> participants;
  final Message? lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageTime;
  final bool isPinned;
  final Map<String, int> unreadCount;
  final String? groupName;
  final String? groupDescription;
  final String? groupImage;
  final String? profile_picture;
  final bool? attendance_group;
  final dynamic? unread_count;
  final dynamic? actual_role;

  final Map<String, String>? groupRoles;

  Chat({
    required this.id,
    required this.type,
    required this.participants,
    this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageTime,
    this.isPinned = false,
    required this.unreadCount,
    this.groupName,
    this.groupDescription,
    this.groupImage,
    this.profile_picture,
    this.attendance_group,
    this.unread_count,
    this.actual_role,
    this.groupRoles,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    DateTime? parsedLastMessageTime;
    try {
      if (json['last_message_time'] != null) {
        parsedLastMessageTime = DateTime.parse(json['last_message_time']);
      } else if (json['sort_time'] != null) {
        parsedLastMessageTime = DateTime.parse(json['sort_time']);
      } else if (json['last_message'] != null) {
        final lastMsg = json['last_message'];
        if (lastMsg['timestamp'] != null) {
          parsedLastMessageTime = DateTime.parse(lastMsg['timestamp']);
        } else if (lastMsg['created_at'] != null) {
          parsedLastMessageTime = DateTime.parse(lastMsg['created_at']);
        }
      }
    } catch (e) {
      // Error parsing - use fallback
    }

    return Chat(
      id: json['id']?.toString() ?? '',
      type: json['type'] ?? 'private',
      participants: json['participants'] != null 
          ? List<String>.from(json['participants'])
          : (json['type'] == 'user' ? [json['id']?.toString() ?? ''] : []),
      lastMessage: json['last_message'] != null 
          ? Message.fromJson(json['last_message'])
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
      lastMessageTime: parsedLastMessageTime,
      isPinned: json['is_pinned'] ?? false,
      unreadCount: Map<String, int>.from(json['unread_count'] is Map ? json['unread_count'] : {}),
      groupName: json['name'] ?? json['group_name'],
      groupDescription: json['group_description'],
      groupImage: json['group_image'],
      profile_picture: json['profile_picture'],
      attendance_group: json['attendance_group'],
      unread_count: json['unread_count'],
      actual_role: json['actual_role'] ?? json['role'],
      groupRoles: json['group_roles'] != null
          ? Map<String, String>.from(json['group_roles'])
          : null,
    );
  }

  factory Chat.fromFirestore(Map<String, dynamic> data, String id) {
    return Chat(
      id: id,
      type: data['type'] ?? 'private',
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: data['lastMessage'] != null
          ? Message.fromFirestore(Map<String, dynamic>.from(data['lastMessage']), '')
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMessageTime: (data['lastMessageTime'] as Timestamp?)?.toDate(),
      isPinned: data['isPinned'] ?? false,
      unreadCount: Map<String, int>.from(data['unreadCount'] ?? {}),
      groupName: data['groupName'],
      groupDescription: data['groupDescription'],
      attendance_group: data['attendance_group'],
      groupImage: data['groupImage'],
      groupRoles: data['groupRoles'] != null
          ? Map<String, String>.from(data['groupRoles'])
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'participants': participants,
      'lastMessage': lastMessage?.toFirestore(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'lastMessageTime': lastMessageTime != null ? Timestamp.fromDate(lastMessageTime!) : null,
      'isPinned': isPinned,
      'unreadCount': unreadCount,
      'groupName': groupName,
      'groupDescription': groupDescription,
      'groupImage': groupImage,
      'attendance_group': attendance_group,
      'groupRoles': groupRoles,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'participants': participants,
      'last_message': lastMessage?.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_message_time': lastMessageTime?.toIso8601String(),
      'is_pinned': isPinned,
      'unread_count': unreadCount,
      'actual_role': actual_role,
      'group_name': groupName,
      'group_description': groupDescription,
      'group_image': groupImage,
      'profile_picture': profile_picture,
      'attendance_group': attendance_group,
      'group_roles': groupRoles,
    };
  }

  bool get isGroup => type == 'group';
  bool get isPrivate => type == 'private';

  DateTime getLastMessageTime() {
    return lastMessageTime ?? lastMessage?.timestamp ?? updatedAt;
  }

  String getDisplayName(String currentUserId, List<User> users) {
    if (isGroup) {
      return groupName ?? 'Group Chat';
    }
    
    if (groupName != null && groupName!.isNotEmpty) {
      return groupName!;
    }
    
    try {
      final otherUserId = participants.firstWhere((id) => id != currentUserId, orElse: () => '');
      if (otherUserId.isEmpty) return 'Unknown User';
      
      final otherUser = users.firstWhere((user) => user.id == otherUserId, orElse: () => User(
        id: otherUserId,
        name: 'Unknown User',
        email: '',
        role: 'user',
        actual_role: 'user',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      return otherUser.name;
    } catch (e) {
      return 'Unknown User';
    }
  }

  String? getDisplayImage(String currentUserId, List<User> users) {
    if (isGroup) {
      return groupImage ?? profile_picture;
    }
    
    if (profile_picture != null && profile_picture!.isNotEmpty) {
      return profile_picture;
    }
    
    try {
      final otherUserId = participants.firstWhere((id) => id != currentUserId, orElse: () => '');
      if (otherUserId.isEmpty) return null;
      
      final otherUser = users.firstWhere((user) => user.id == otherUserId, orElse: () => User(
        id: otherUserId,
        name: 'Unknown User',
        email: '',
        role: 'user',
        actual_role: 'user',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      return otherUser.profilePicture;
    } catch (e) {
      return profile_picture;
    }
  }

  int getUnreadCountForUser(String userId) {
    if (unread_count != null) {
      if (unread_count is int) {
        return unread_count as int;
      } else if (unread_count is Map) {
        final countMap = unread_count as Map<String, dynamic>;
        return countMap[userId] ?? 0;
      }
    }
    return unreadCount[userId] ?? 0;
  }

  bool isUserAdmin(String userId) {
    return groupRoles?[userId] == 'admin';
  }

  Chat copyWith({
    String? id,
    String? type,
    List<String>? participants,
    Message? lastMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastMessageTime,
    bool? isPinned,
    Map<String, int>? unreadCount,
    String? groupName,
    String? groupDescription,
    String? groupImage,
    String? profile_picture,
    bool? attendance_group,
    dynamic? unread_count,
    dynamic? actual_role,
    Map<String, String>? groupRoles,
  }) {
    return Chat(
      id: id ?? this.id,
      type: type ?? this.type,
      participants: participants ?? this.participants,
      lastMessage: lastMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      isPinned: isPinned ?? this.isPinned,
      unreadCount: unreadCount ?? this.unreadCount,
      groupName: groupName ?? this.groupName,
      groupDescription: groupDescription ?? this.groupDescription,
      groupImage: groupImage ?? this.groupImage,
      groupRoles: groupRoles ?? this.groupRoles,
      profile_picture: profile_picture ?? this.profile_picture,
      attendance_group: attendance_group ?? this.attendance_group,
      unread_count: unread_count ?? this.unread_count,
      actual_role: actual_role ?? this.actual_role,
    );
  }
}