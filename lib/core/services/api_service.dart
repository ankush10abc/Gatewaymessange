import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../models/chat_list_model.dart';

class LoginRequest {
  final String mobile;
  final String password;
  final String? fcmToken;

  LoginRequest({required this.mobile, required this.password, this.fcmToken});

  Map<String, dynamic> toJson() => {
    'mobile': mobile,
    'password': password,
    if (fcmToken != null) 'fcm_token': fcmToken,
  };
}

class AuthResponse {
  final String token;
  final User user;

  AuthResponse({required this.token, required this.user});

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
    token: json['token'],
    user: User.fromJson(json['user']),
  );
}

class SendMessageRequest {
  final int? receiverId;
  final int? groupId;
  final String message;
  final String messageType;
  final String firebaseMessageId;
  final int? replyToMessageId;
  final String? filePath;
  final String? fileName;
  final int? fileSize;

  SendMessageRequest({
    this.receiverId,
    this.groupId,
    required this.message,
    required this.messageType,
    required this.firebaseMessageId,
    this.replyToMessageId,
    this.filePath,
    this.fileName,
    this.fileSize,
  });

  Map<String, dynamic> toJson() => {
    if (receiverId != null) 'receiver_id': receiverId,
    if (groupId != null) 'group_id': groupId,
    'message': message,
    'message_type': messageType,
    'firebase_message_id': firebaseMessageId,
    if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
    if (filePath != null) 'file_path': filePath,
    if (fileName != null) 'file_name': fileName,
    if (fileSize != null) 'file_size': fileSize,
  };
}

class PaginatedResponse<T> {
  final List<T> data;
  final int total;
  final int page;
  final int limit;

  PaginatedResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) => PaginatedResponse(
    data: (json['data'] as List).map((item) => fromJsonT(item)).toList(),
    total: json['total'] ?? 0,
    page: json['page'] ?? 1,
    limit: json['limit'] ?? 50,
  );
}

class FileUploadResponse {
  final String filePath;
  final String fileName;
  final int fileSize;
  final String url;

  FileUploadResponse({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.url,
  });

  factory FileUploadResponse.fromJson(Map<String, dynamic> json) => FileUploadResponse(
    filePath: json['file_path'],
    fileName: json['file_name'],
    fileSize: json['file_size'],
    url: json['url'],
  );
}

class ProfilePictureResponse {
  final String profilePicture;
  final String message;

  ProfilePictureResponse({required this.profilePicture, required this.message});

  factory ProfilePictureResponse.fromJson(Map<String, dynamic> json) => ProfilePictureResponse(
    profilePicture: json['profile_picture'],
    message: json['message'],
  );
}

class ApiService {
  final Dio _dio;
  static const String baseUrl = 'http://localhost:8000/api';
  static const int messageCount = 20;

  ApiService(this._dio) {
    _dio.options.baseUrl = baseUrl;
    _dio.options.headers['Accept'] = 'application/json';
  }

  Future<AuthResponse> login(LoginRequest request) async {
    debugPrint('API Call: POST /login - ${request.toJson()}');
    final response = await _dio.post('/login', data: request.toJson());
    debugPrint('API Response: POST /login - ${response.data}');
    return AuthResponse.fromJson(response.data);
  }

  Future<User> getCurrentUser() async {
    debugPrint('API Call: GET /me');
    final response = await _dio.get('/me');
    debugPrint('API Response: GET /me - ${response.data}');
    return User.fromJson(response.data);
  }

  Future<void> logout() async {
    debugPrint('API Call: POST /logout');
    await _dio.post('/logout');
    debugPrint('API Response: POST /logout - Success');
  }

  Future<List<ChatModel>> getMyGroups() async {
    debugPrint('API Call: GET $baseUrl/my-groups');
    final response = await _dio.get('/my-groups');
    debugPrint('API Response: GET $baseUrl/my-groups - ${response.data}');
    return (response.data as List).map((item) => ChatModel.fromJson(item)).toList();
  }

  Future<List<ChatModel>> getChatList() async {
    debugPrint('API Call: GET $baseUrl/users/chat-list');
    final response = await _dio.get('/users/chat-list');
    debugPrint('API Response: GET $baseUrl/users/chat-list - ${response.data}');
    return (response.data as List).map((item) => ChatModel.fromJson(item)).toList();
  }

  Future<List<User>> searchUsers(String query, {int page = 1}) async {
    debugPrint('API Call: GET $baseUrl/users/search?query=$query&page=$page');
    final response = await _dio.get('/users/search', queryParameters: {
      'query': query,
      'page': page,
    });
    debugPrint('API Response: GET $baseUrl/users/search - ${response.data}');
    
    // Handle response structure: {data: [...]} or [...]
    final List<dynamic> userList;
    if (response.data is Map && response.data['data'] != null) {
      userList = response.data['data'] as List;
    } else if (response.data is List) {
      userList = response.data as List;
    } else {
      return [];
    }
    
    return userList.map((item) => User.fromJson(item)).toList();
  }

  Future<List<User>> getTeachers() async {
    final response = await _dio.get('/users/teachers');
    return (response.data as List).map((item) => User.fromJson(item)).toList();
  }

  Future<List<User>> getParents() async {
    final response = await _dio.get('/users/parents');
    return (response.data as List).map((item) => User.fromJson(item)).toList();
  }

  Future<List<User>> getChatPermissions() async {
    final response = await _dio.get('/users/chat-permissions');
    return (response.data as List).map((item) => User.fromJson(item)).toList();
  }

  Future<Message> sendMessage({
    required String message,
    String? receiverId,
    String? groupId,
    required String messageType,
    String? filePath,
    String? fileName,
    String? replyToMessageId,
  }) async {
    final request = SendMessageRequest(
      receiverId: receiverId != null ? int.tryParse(receiverId) : null,
      groupId: groupId != null ? int.tryParse(groupId) : null,
      message: message,
      messageType: messageType,
      firebaseMessageId: DateTime.now().millisecondsSinceEpoch.toString(),
      replyToMessageId: replyToMessageId != null ? int.tryParse(replyToMessageId) : null,
      filePath: filePath,
      fileName: fileName,
    );

    final response = await _dio.post('/message/save', data: request.toJson());
    return Message.fromJson(response.data);
  }

  Future<FileUploadResponse> uploadFile(File file, String messageType) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path),
      'message_type': messageType,
    });

    final response = await _dio.post('/message/upload', data: formData);
    return FileUploadResponse.fromJson(response.data);
  }

  Future<PaginatedResponse<Message>> getConversation(int userId, int page, int limit) async {
    final response = await _dio.get(
      '/messages/conversation/$userId',
      queryParameters: {'page': page, 'limit': limit},
    );
    return PaginatedResponse.fromJson(response.data, (json) => Message.fromJson(json));
  }

  Future<PaginatedResponse<Message>> getGroupMessages(int groupId, int page, int limit) async {
    final response = await _dio.get(
      '/messages/group/$groupId',
      queryParameters: {'page': page, 'limit': limit},
    );
    return PaginatedResponse.fromJson(response.data, (json) => Message.fromJson(json));
  }

  Future<void> markMessageAsDelivered(int messageId) async {
    await _dio.patch('/message/$messageId/delivered');
  }

  Future<void> markMessageAsRead(int messageId) async {
    debugPrint('API Call: PATCH /message/$messageId/read');
    await _dio.patch('/message/$messageId/read');
    debugPrint('API Response: PATCH /message/$messageId/read - Success');
  }

  Future<void> setOnlineStatus() async {
    await _dio.post('/user/status/online');
  }

  Future<void> setOfflineStatus() async {
    await _dio.post('/user/status/offline');
  }

  Future<Map<String, dynamic>> getUserStatus(int userId) async {
    final response = await _dio.get('/user/$userId/status');
    return response.data;
  }

  Future<ProfilePictureResponse> uploadProfilePicture(File profilePicture) async {
    final formData = FormData.fromMap({
      'profile_picture': await MultipartFile.fromFile(profilePicture.path),
    });

    final response = await _dio.post('/profile/upload-picture', data: formData);
    return ProfilePictureResponse.fromJson(response.data);
  }

  Future<void> removeProfilePicture() async {
    await _dio.delete('/profile/remove-picture');
  }

  Future<void> syncMessageFromFirebase(Map<String, dynamic> data) async {
    await _dio.post('/firebase/sync-message', data: data);
  }

  Future<void> deleteUserFromFirebase(Map<String, dynamic> data) async {
    await _dio.post('/firebase/delete-user', data: data);
  }

  Future<void> deleteGroupFromFirebase(Map<String, dynamic> data) async {
    await _dio.post('/firebase/delete-group', data: data);
  }

  Future<Object?> batchSendMessages(List<Map<String, String>> testMessages) async {

  }
}
