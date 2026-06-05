class ChatModel {
  final String? id;
  final String? type;
  final List<String>? participants;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, int>? unreadCount;
  final bool? isPinned;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final String? groupName;
  final String? groupDescription;
  final String? groupImage;
  final int? userId;
  final int? groupId;
  final String? userName;
  final String? userProfilePicture;
  final bool? isOnline;
  final String? userRole;

  ChatModel({
    this.id,
    this.type,
    this.participants,
    this.createdAt,
    this.updatedAt,
    this.unreadCount,
    this.isPinned,
    this.lastMessage,
    this.lastMessageTime,
    this.groupName,
    this.groupDescription,
    this.groupImage,
    this.userId,
    this.groupId,
    this.userName,
    this.userProfilePicture,
    this.isOnline,
    this.userRole,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    return ChatModel(
      id: json['id']?.toString(),
      type: json['type'],
      participants: json['participants'] != null 
          ? List<String>.from(json['participants'])
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'])
          : null,
      unreadCount: json['unread_count'] != null 
          ? Map<String, int>.from(json['unread_count'])
          : null,
      isPinned: json['is_pinned'] ?? false,
      lastMessage: json['last_message'],
      lastMessageTime: json['last_message_time'] != null 
          ? DateTime.parse(json['last_message_time'])
          : null,
      groupName: json['group_name'] ?? json['name'],
      groupDescription: json['group_description'] ?? json['description'],
      groupImage: json['group_image'] ?? json['image'],
      userId: json['user_id'],
      groupId: json['group_id'],
      userName: json['user_name'] ?? json['name'],
      userProfilePicture: json['user_profile_picture'] ?? json['profile_picture'],
      isOnline: json['is_online'] ?? false,
      userRole: json['user_role'] ?? json['role'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'participants': participants,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'unread_count': unreadCount,
      'is_pinned': isPinned,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'group_name': groupName,
      'group_description': groupDescription,
      'group_image': groupImage,
      'user_id': userId,
      'group_id': groupId,
      'user_name': userName,
      'user_profile_picture': userProfilePicture,
      'is_online': isOnline,
      'user_role': userRole,
    };
  }

  ChatModel copyWith({
    String? id,
    String? type,
    List<String>? participants,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, int>? unreadCount,
    bool? isPinned,
    String? lastMessage,
    DateTime? lastMessageTime,
    String? groupName,
    String? groupDescription,
    String? groupImage,
    int? userId,
    int? groupId,
    String? userName,
    String? userProfilePicture,
    bool? isOnline,
    String? userRole,
  }) {
    return ChatModel(
      id: id ?? this.id,
      type: type ?? this.type,
      participants: participants ?? this.participants,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      groupName: groupName ?? this.groupName,
      groupDescription: groupDescription ?? this.groupDescription,
      groupImage: groupImage ?? this.groupImage,
      userId: userId ?? this.userId,
      groupId: groupId ?? this.groupId,
      userName: userName ?? this.userName,
      userProfilePicture: userProfilePicture ?? this.userProfilePicture,
      isOnline: isOnline ?? this.isOnline,
      userRole: userRole ?? this.userRole,
    );
  }

  bool get isGroup => type == 'group';
  bool get isPrivate => type == 'private';
  
  String get displayName => isGroup ? (groupName ?? 'Group') : (userName ?? 'User');
  String? get displayImage => isGroup ? groupImage : userProfilePicture;
  int get totalUnreadCount => unreadCount?.values.fold(0, (sum, count) => (sum ?? 0) + count) ?? 0;
}