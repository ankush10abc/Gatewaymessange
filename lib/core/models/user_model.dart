class User {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final String actual_role;
  final String? profilePicture;
  final bool isOnline;
  final bool can_send_attachments;
  final DateTime? lastSeen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? permissions;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    required this.actual_role,
    this.profilePicture,
    this.isOnline = false,
    this.can_send_attachments = true,
    this.lastSeen,
    required this.createdAt,
    required this.updatedAt,
    this.permissions,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['mobile'] ?? json['phone'], // Handle both mobile and phone fields
      role: json['role'] ?? 'user',
      actual_role: json['actual_role'] ?? 'no user',
      can_send_attachments: json['can_send_attachments'] == true || json['can_send_attachments'] == 1,
      profilePicture: json['profile_picture'],
      isOnline: json['is_online'] ?? false,
      lastSeen: json['last_seen_at'] != null 
          ? DateTime.parse(json['last_seen_at'])
          : (json['last_seen'] != null 
              ? DateTime.parse(json['last_seen'])
              : null),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
      permissions: json['permissions'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'actual_role': actual_role,
      'profile_picture': profilePicture,
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'permissions': permissions,
    };
  }

  bool get isAdmin => role == 'admin';
  bool get isTeacher => role == 'teacher';
  bool get isParent => role == 'parent';

  bool canChatWith(User otherUser) {
    if (isAdmin) return true;
    if (isTeacher) {
      return otherUser.isAdmin || otherUser.isTeacher || 
             (otherUser.isParent && hasPermissionToChat(otherUser.id));
    }
    if (isParent) {
      return otherUser.isAdmin || 
             (otherUser.isTeacher && otherUser.hasPermissionToChat(id));
    }
    return false;
  }

  bool hasPermissionToChat(String userId) {
    return permissions?['chat_with']?.contains(userId) ?? false;
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? role,
    String? actual_role,
    String? profilePicture,
    bool? isOnline,
    DateTime? lastSeen,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? permissions,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      actual_role: actual_role ?? this.actual_role,
      profilePicture: profilePicture ?? this.profilePicture,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      permissions: permissions ?? this.permissions,
    );
  }
}