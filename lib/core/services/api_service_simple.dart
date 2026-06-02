import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../models/chat_list_model.dart';
import '../storage/storage_service.dart';
import '../utils/internet_checker.dart';
import 'dart:io';

// Request/Response Models
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

class RegisterRequest {
  final String name;
  final String mobile;
  final String password;
  final String role;

  RegisterRequest({
    required this.name,
    required this.mobile,
    required this.password,
    required this.role,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'mobile': mobile,
    'password': password,
    'role': role,
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
  final Map user;
  final int total;
  final int page;
  final int limit;

  PaginatedResponse({
    required this.data,
    required this.user,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    debugPrint("Ankush Banawade ${json['data']}");
    debugPrint("Ankush Banawade fromJsonT ${fromJsonT}");
    return PaginatedResponse(
    data: (json['data'] as List).map((item) => fromJsonT(item)).toList(),
      user: json['user'],
    total: json['total'] ?? 0,
    page: json['page'] ?? 1,
    limit: json['limit'] ?? 50,
  );
  }
}

class FileUploadResponse {
  final String filePath;
  final String fileName;
  final int fileSize;
   String? url ='';

  FileUploadResponse({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
     this.url,
  });

  factory FileUploadResponse.fromJson(Map<String, dynamic> json) => FileUploadResponse(
    filePath: json['file_path'],
    fileName: json['file_name'],
    fileSize: json['file_size'],
    url: json['url'] ??'',
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
// Parents -
// Phone : 8528996384
// Pass : 12345678

// "mobile": "9792957332",
// "password": "rainsingh",
//
// Phone - 8840165748
// Password - 12345678

// 8896946242
// 272175
class ApiService {
  final Dio _dio;
  static const String baseUrl = 'https://gatewayreports.in';
  static void Function()? onUnauthorized;
  static BuildContext? _context;

  static int messageCount =15;

  static void setContext(BuildContext context) {
    _context = context;
  }

  ApiService(this._dio) {
    _dio.options.baseUrl = baseUrl;
    _dio.options.headers['Accept'] = 'application/json';
    _dio.options.headers['Content-Type'] = 'application/json';
    
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 || error.response?.statusCode == 403) {
          await _handle401Error();
        }
        handler.next(error);
      },
    ));
  }

  Future<void> _handle401Error() async {
    final storage = StorageService();
    bool hasInternet =   await InternetChecker.hasInternet();
    if(hasInternet){
      await storage.clearAll();
      clearAuthToken();

    }

    if (onUnauthorized != null) {
      onUnauthorized!();
    }
  }

  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
    debugPrint("Ankush banawade Bearer $token");
  }

  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  // Authentication APIs
  Future<AuthResponse> login(LoginRequest request) async {
    debugPrint('API Call: POST $baseUrl/api/login - Request: ${request.toJson()}');
    final response = await _dio.post('/api/login', data: request.toJson());
    debugPrint('API Response: POST $baseUrl/api/login - ${response.data}');
    final authResponse = AuthResponse.fromJson(response.data);
    setAuthToken(authResponse.token);
    debugPrint("Ankush Banawade ${authResponse.user.role}");
    return authResponse;
  }

  Future<User> getCurrentUser() async {
    debugPrint('API Call: GET $baseUrl/api/me');
    final response = await _dio.get('/api/me');
    debugPrint('API Response: GET $baseUrl/api/me - ${response.data}');
    return User.fromJson(response.data);
  }

  Future<void> logout() async {
    debugPrint('API Call: POST $baseUrl/api/logout');
    await _dio.post('/api/logout');
    debugPrint('API Response: POST $baseUrl/api/logout - Success');
    clearAuthToken();
  }

  // Groups APIs
  Future<List<ChatModel>> getMyGroups() async {
    debugPrint('API Call: GET $baseUrl/api/my-groups');
    final response = await _dio.get('/api/my-groups');
    debugPrint('API Response: GET $baseUrl/api/my-groups - ${response.data}');
    return (response.data as List).map((item) => ChatModel.fromJson(item)).toList();
  }

  // Users & Chat APIs
  Future<List<dynamic>> getChatList() async {
    debugPrint('API Call: GET $baseUrl/api/users/chat-list');
    final response = await _dio.get('/api/users/chat-list');
    debugPrint('API Response: GET $baseUrl/api/users/chat-list - ${response.data}');
    return response.data as List<dynamic>;
  }

  Future<List<User>> searchUsers(String query) async {
    debugPrint('API Call: GET $baseUrl/api/users/search?query=$query');
    final response = await _dio.get('/api/users/search', queryParameters: {'query': query});
    debugPrint('API Response: GET $baseUrl/api/users/search - ${response.data}');
    return (response.data as List).map((item) => User.fromJson(item)).toList();
  }

  Future<List<User>> getTeachers() async {
    debugPrint('API Call: GET $baseUrl/api/users/teachers');
    final response = await _dio.get('/api/users/teachers');
    debugPrint('API Response: GET $baseUrl/api/users/teachers - ${response.data}');
    return (response.data as List).map((item) => User.fromJson(item)).toList();
  }

  Future<List<User>> getParents() async {
    debugPrint('API Call: GET $baseUrl/api/users/parents');
    final response = await _dio.get('/api/users/parents');
    debugPrint('API Response: GET $baseUrl/api/users/parents - ${response.data}');
    return (response.data as List).map((item) => User.fromJson(item)).toList();
  }

  Future<List<User>> getChatPermissions() async {
    debugPrint('API Call: GET $baseUrl/api/users/chat-permissions');
    final response = await _dio.get('/api/users/chat-permissions');
    debugPrint('API Response: GET $baseUrl/api/users/chat-permissions - ${response.data}');
    return (response.data as List).map((item) => User.fromJson(item)).toList();
  }

  // Messages APIs
  Future<Message> sendMessage({
    required String message,
    String? receiverId,
    String? groupId,
    required String messageType,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? firebaseKey,
    String? replyToMessageId,
    String? old_firebase_message_id,
  }) async {
    final Map<String, dynamic> request = {
      'message': message,
      'message_type': messageType,
      'firebase_message_id': firebaseKey,
    };

    if (groupId != null) {
      request['group_id'] = int.parse(groupId);
      request['receiver_id'] = null;
    } else if (receiverId != null) {
      request['receiver_id'] = int.parse(receiverId);
    }

    if (filePath != null) request['file_path'] = filePath;
    if (fileName != null) request['file_name'] = fileName;
    if (fileSize != null) request['file_size'] = fileSize;
    if (replyToMessageId != null) request['reply_to_message_id'] = int.parse(replyToMessageId);
    if (old_firebase_message_id != null) request['old_firebase_message_id'] = old_firebase_message_id;

    debugPrint('API Call: POST $baseUrl/api/message/save - Request: $request');
    final response = await _dio.post('/api/message/save', data: request);
    debugPrint('API Response: POST $baseUrl/api/message/save - ${response.data}');
    return Message.fromJson(response.data);
  }

  Future<FileUploadResponse> uploadFile(File file, String messageType) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path),
      'message_type': messageType,
    });

    debugPrint('API Call: POST $baseUrl/api/message/upload - File: ${file.path}, Type: $messageType');
    final response = await _dio.post('/api/message/upload', data: formData);
    debugPrint('API Response: POST $baseUrl/api/message/upload - ${response.data}');
    return FileUploadResponse.fromJson(response.data);
  }

  Future<PaginatedResponse<Message>> getConversation(int userId, int page, int limit) async {
    debugPrint('API Call: GET $baseUrl/api/messages/conversation/$userId?page=$page&limit=$limit');
    final response = await _dio.get(
      '/api/messages/conversation/$userId?page=$page&limit=$limit',
      queryParameters: {'page': page, 'limit': limit},
    );
    debugPrint('API Response: GET $baseUrl/api/messages/conversation/$userId - ${response.data}');
    List<Message> messages =[];
    final data = response.data as Map<String, dynamic>;
    try {
       messages = (data['messages']['data'] as List).map((json) => Message.fromJson(json)).toList();
    } catch (e) {
      print(e);
    }
    debugPrint(" API sync error: ${ data['user'] }");
    final user =  data['user'] ?? data['group'];

    return PaginatedResponse(
      data: messages,
      user: user,
      total: data['total'] ?? 0,
      page: data['current_page'] ?? 1,
      limit: data['per_page'] ?? 50,
    );
  }

  Future<PaginatedResponse<Message>> getGroupMessages(int groupId, int page, int limit) async {
    debugPrint('API Call: GET $baseUrl/api/messages/group/$groupId?page=$page&limit=$limit');
    final response = await _dio.get(
      '/api/messages/group/$groupId',
      queryParameters: {'page': page, 'limit': limit},
    );
    debugPrint('API Response: GET $baseUrl/api/messages/group/$groupId - ${response.data}');
    
    final data = response.data as Map<String, dynamic>;
    final messages = (data['messages']['data'] as List).map((json) {

      return Message.fromJson(json);
    }).toList();
    final user =  data['user']?? data['group'];
    debugPrint("Ankush Banawade Messahes $messages");
    debugPrint("Ankush Banawade Messahes $user");
    return PaginatedResponse(
      data: messages,
      user: user,
      total: data['total'] ?? 0,
      page: data['current_page'] ?? 1,
      limit: data['per_page'] ?? 50,
    );
  }

  Future<void> markMessageAsDelivered(int messageId) async {
    debugPrint('API Call: PATCH $baseUrl/api/message/$messageId/delivered');
    await _dio.patch('/api/message/$messageId/delivered');
    debugPrint('API Response: PATCH $baseUrl/api/message/$messageId/delivered - Success');
  }

  Future<void> markMessageAsRead(int messageId) async {
    debugPrint('API Call: PATCH $baseUrl/api/message/$messageId/read');
    debugPrint('_markMessageAsRead $baseUrl/api/message/$messageId/read');
   var data= await _dio.patch('/api/message/$messageId/read');
    debugPrint('API Response: PATCH $baseUrl/api/message/$messageId/read - $data Success');
    debugPrint('_markMessageAsRead $baseUrl/api/message/$messageId/read - $data Success');
  }

  Future<Map<String, dynamic>> jumpToMessage(int messageId, String userId) async {
    debugPrint('API Call: GET $baseUrl/api/message/$messageId/jump?user_id=$userId');
    final response = await _dio.get('/api/message/$messageId/jump', queryParameters: {'user_id': userId});
    debugPrint('API Response: GET $baseUrl/api/message/$messageId/jump - ${response.data}');
    return response.data;
  }

  // User Status APIs
  Future<void> setOnlineStatus() async {
    debugPrint('API Call: POST /api/user/status/online');
    await _dio.post('/api/user/status/online');
    debugPrint('API Response: POST /api/user/status/online - Success');
  }

  Future<void> setOfflineStatus() async {
    debugPrint('API Call: POST /api/user/status/offline');
    await _dio.post('/api/user/status/offline');
    debugPrint('API Response: POST /api/user/status/offline - Success');
  }

  Future<Map<String, dynamic>> getUserStatus(int userId) async {
    debugPrint('API Call: GET /api/user/$userId/status');
    final response = await _dio.get('/api/user/$userId/status');
    debugPrint('API Response: GET /api/user/$userId/status - ${response.data}');
    return response.data;
  }

  // Profile APIs
  Future<ProfilePictureResponse> uploadProfilePicture(File profilePicture) async {
    debugPrint('API Call: POST /api/profile/upload-picture - File: ${profilePicture.path}');
    final formData = FormData.fromMap({
      'profile_picture': await MultipartFile.fromFile(profilePicture.path),
    });

    final response = await _dio.post('/api/profile/upload-picture', data: formData);
    debugPrint('API Response: POST /api/profile/upload-picture - ${response.data}');
    debugPrint("response ${response.data}");
    return ProfilePictureResponse.fromJson(response.data);
  }

  Future<void> removeProfilePicture() async {
    debugPrint('API Call: DELETE /api/profile/remove-picture');
    await _dio.delete('/api/profile/remove-picture');
    debugPrint('API Response: DELETE /api/profile/remove-picture - Success');
  }

  // Firebase Sync APIs
  Future<void> syncMessageFromFirebase(Map<String, dynamic> data) async {
    debugPrint('API Call: POST /api/firebase/sync-message - Data: $data');
    await _dio.post('/api/firebase/sync-message', data: data);
    debugPrint('API Response: POST /api/firebase/sync-message - Success');
  }

  Future<void> deleteUserFromFirebase(Map<String, dynamic> data) async {
    debugPrint('API Call: POST /api/firebase/delete-user - Data: $data');
    await _dio.post('/api/firebase/delete-user', data: data);
    debugPrint('API Response: POST /api/firebase/delete-user - Success');
  }

  Future<void> deleteGroupFromFirebase(Map<String, dynamic> data) async {
    debugPrint('API Call: POST /api/firebase/delete-group - Data: $data');
    await _dio.post('/api/firebase/delete-group', data: data);
    debugPrint('API Response: POST /api/firebase/delete-group - Success');
  }

  // Attendance APIs
  Future<void> markAttendance({
    required int groupId,
    required String action,
    required double latitude,
    required double longitude,
    String? remark,
  }) async {
    final request = {
      'group_id': groupId,
      'action': action,
      'latitude': latitude,
      'longitude': longitude,
      'remark': remark ?? '',
    };
    debugPrint('API Call: POST $baseUrl/api/attendance/mark - Request: $request');
    try {
      final response = await _dio.post('/api/attendance/mark', data: request);
      debugPrint('API Response: POST $baseUrl/api/attendance/mark - $response Success');
    } on DioException catch (e) {
      final message = e.response?.data['message'] ?? 'Failed to mark attendance';
      throw Exception('$message' );
    }
  }

  Future<Map<String, dynamic>> getTodayAttendanceStatus(int groupId) async {
    debugPrint('API Call: GET $baseUrl/api/attendance/today-status?group_id=$groupId');
    final response = await _dio.get(
      '/api/attendance/today-status',
      queryParameters: {'group_id': groupId},
    );
    debugPrint('API Response: GET $baseUrl/api/attendance/today-status - ${response.data}');
    return response.data;
  }
}
