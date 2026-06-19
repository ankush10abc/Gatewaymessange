import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/chat_list_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../storage/storage_service.dart';
import '../utils/internet_checker.dart';

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
    debugPrint("Ankush Banawade fromJsonT $fromJsonT");
    return PaginatedResponse(
      data: (json['data'] as List).map((item) => fromJsonT(item)).toList(),
      user: json['user'] is Map
          ? Map<String, dynamic>.from(json['user'])
          : <String, dynamic>{},
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
  String? url = '';

  FileUploadResponse({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    this.url,
  });

  factory FileUploadResponse.fromJson(Map<String, dynamic> json) =>
      FileUploadResponse(
        filePath: json['file_path'],
        fileName: json['file_name'],
        fileSize: json['file_size'],
        url: json['url'] ?? '',
      );
}

class ProfilePictureResponse {
  final String profilePicture;
  final String message;

  ProfilePictureResponse({required this.profilePicture, required this.message});

  factory ProfilePictureResponse.fromJson(Map<String, dynamic> json) =>
      ProfilePictureResponse(
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

//9005147759
//MSakhtar@008#
// Future<void> _initializeChat() async {
//   debugPrint('📴 Offline - skipping Firebase presence update');
//   final user = ref.read(authProvider).user;
//   debugPrint('📴 Offline - skipping Firebase presence update$user');
//   if (user == null) return;
//
//   _currentUserId = user.id;
//   await _initializeAuth();
//   debugPrint('AnkushuserRole three $user');
//   try {
//     // Check internet before Firebase operations
//     final hasInternet = await InternetChecker.hasInternet();
//     debugPrint('AnkushuserRole five $hasInternet');
//     try {
//       if (hasInternet) {
//         await _loadInitialMessages();
//         await FirebaseRealtimeService.setUserOnline(user.id);
//       } else {
//         await _loadInitialMessages();
//         debugPrint('📴 Offline - skipping Firebase presence update');
//       }
//     } catch (e) {
//       print(e);
//     }
//     debugPrint('AnkushuserRole four $user');
//
//
//     debugPrint(
//         "🔥 _setupRealtimeListeners check: attendance_group=$_isAttendanceGroup");
//
//     // Setup Firebase listeners ONLY if online and not attendance group
//     if (hasInternet && _isAttendanceGroup != true) {
//       debugPrint("✅ Setting up Firebase listeners for regular chat");
//       _setupRealtimeListeners();
//     } else if (!hasInternet) {
//       debugPrint("📴 Offline - skipping Firebase listeners");
//     } else {
//       debugPrint("⏭️ Skipping Firebase listeners for attendance group");
//     }
//
//     // Start background sync ONLY if online
//     if (hasInternet) {
//       _syncService.startBackgroundSync(
//         chatId: widget.chatId,
//         chatType: widget.chatType,
//         apiService: _apiService,
//         currentUserId: _currentUserId,
//         userRole: _userRoleCache,
//         isAttendanceGroup: _isAttendanceGroup,
//         otherUserId: _firebaseOtherUserId,
//       );
//     } else {
//       debugPrint('📴 Offline - skipping background sync');
//     }
//
//     ref.read(chatProvider.notifier).resetUnreadCount(widget.chatId);
//
//     // Mark messages as read ONLY if online
//     if (hasInternet) {
//       Future.delayed(const Duration(milliseconds: 300), () {
//         if (mounted) {
//           FirebaseRealtimeService.markMessagesAsRead(
//               widget.chatType, widget.chatId, user.id,
//               currentUserId: _currentUserId,
//               otherUserId: _firebaseOtherUserId,
//               attendanceGroup: _isAttendanceGroup,
//               groupMembers: widget.chatType == 'group' && _user != null
//                   ? _user!['member_list']
//                   : null);
//
//           // Update chat list to reset unread count
//           ChatListUpdateService.updateOnMessageReceived(
//             chatId: widget.chatId,
//             chatType: widget.chatType,
//             attendanceGroup: _isAttendanceGroup == true,
//             lastMessage: _messages.isNotEmpty ? _messages.first.text : '',
//             incrementUnread: false,
//           );
//         }
//       });
//     }
//   } catch (e) {
//     // if (mounted) {
//     //   setState(() {
//     //     _isLoadingOldMessages = false;
//     //   });
//     //   ScaffoldMessenger.of(context).showSnackBar(
//     //     SnackBar(content: Text('Failed to initialize chat: $e')),
//     //   );
//     // }
//     // debugPrint('Error in _initializeChat: $e');
//   }
//
//   Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
// }



class ApiService {
  final Dio _dio;
  static const String baseUrl = 'https://gatewayreports.in';
  static void Function()? onUnauthorized;
  static BuildContext? _context;

  static int messageCount = 15;

  static void setContext(BuildContext context) {
    _context = context;
  }

  ApiService(this._dio) {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 60);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
    _dio.options.sendTimeout = const Duration(seconds: 60);

    // Set default headers for all requests
    _dio.options.headers['Accept'] = 'application/json';
    _dio.options.headers['Content-Type'] = 'application/json';

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Ensure headers are always present on every request
        options.headers['Accept'] = 'application/json';
        final StorageService _storage = StorageService();
        final token = await _storage.getToken();
        // debugPrint("API Request Headers: $token");
        if (token != null && token.isNotEmpty) {
          _dio.options.headers['Authorization'] = 'Bearer $token';
        }

        if (options.data is! FormData) {
          options.headers['Content-Type'] = 'application/json';
        }
        // debugPrint('API Request Headers: ${options.headers}');
        handler.next(options);
      },
      onError: (error, handler) async {
        // Log detailed error information with URL and request details
        debugPrint('\n========================================');
        debugPrint('❌ API ERROR');
        debugPrint('========================================');
        debugPrint('URL: ${error.requestOptions.uri}');
        debugPrint('Method: ${error.requestOptions.method}');
        debugPrint('Status Code: ${error.response?.statusCode}');
        debugPrint('Headers: ${error.requestOptions.headers}');
        
        if (error.requestOptions.data != null) {
          if (error.requestOptions.data is FormData) {
            debugPrint('Request Data: FormData (${(error.requestOptions.data as FormData).fields.length} fields)');
          } else {
            debugPrint('Request Data: ${error.requestOptions.data}');
          }
        }
        
        if (error.response?.data != null) {
          debugPrint('Response: ${error.response?.data}');
        }
        
        debugPrint('Error Type: ${error.type}');
        debugPrint('Error Message: ${error.message}');
        debugPrint('========================================\n');
        
        // Handle 401/403 errors
        if (error.response?.statusCode == 401 ||
            error.response?.statusCode == 403) {
          await _handle401Error();
        }
        handler.next(error);
      },
    ));
  }

  Map<String, dynamic> _metadataFromResponse(
    Map<String, dynamic> data, {
    required int id,
    required String type,
    required String fallbackName,
  }) {
    final rawMetadata = data['user'] ?? data['group'] ?? data['chat'];
    final metadata = rawMetadata is Map
        ? Map<String, dynamic>.from(rawMetadata)
        : <String, dynamic>{};

    metadata.putIfAbsent('id', () => id.toString());
    metadata.putIfAbsent('type', () => type);
    metadata.putIfAbsent('name', () => fallbackName);

    if (type == 'group') {
      metadata.putIfAbsent(
        'attendance_group',
        () => data['attendance_group'] ?? false,
      );
      metadata.putIfAbsent('member_list', () => <dynamic>[]);
    }

    return metadata;
  }

  // Helper function to log DioException with full details
  void _logApiError(DioException e, String context) {
    debugPrint('\n========================================');
    debugPrint('❌ API ERROR - $context');
    debugPrint('========================================');
    debugPrint('URL: ${e.requestOptions.uri}');
    debugPrint('Method: ${e.requestOptions.method}');
    debugPrint('Status Code: ${e.response?.statusCode}');
    debugPrint('Headers: ${e.requestOptions.headers}');
    
    if (e.requestOptions.data != null) {
      if (e.requestOptions.data is FormData) {
        debugPrint('Request Data: FormData (${(e.requestOptions.data as FormData).fields.length} fields)');
      } else {
        debugPrint('Request Data: ${e.requestOptions.data}');
      }
    }
    
    if (e.response?.data != null) {
      debugPrint('Response: ${e.response?.data}');
    }
    
    debugPrint('Error Type: ${e.type}');
    debugPrint('Error Message: ${e.message}');
    debugPrint('========================================\n');
  }

  List<Message> _messagesFromResponse(dynamic messagesPayload) {
    final rawMessages = messagesPayload is Map
        ? messagesPayload['data']
        : messagesPayload is List
            ? messagesPayload
            : null;

    if (rawMessages is! List) return <Message>[];

    final messages = <Message>[];
    for (final item in rawMessages) {
      try {
        if (item is Map) {
          messages.add(Message.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (e) {
        debugPrint('⚠️ Failed to parse API message: $e');
      }
    }

    return messages;
  }

  Future<void> _handle401Error() async {
    final storage = StorageService();
    bool hasInternet = await InternetChecker.hasInternet();
    if (hasInternet) {
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
    debugPrint(
        'API Call: POST $baseUrl/api/login - Request:lo ${request.toJson()}');
    try {
      final response = await _dio.post(
        '/api/login',
        data: request.toJson(),
      );
      debugPrint(
          'API Response: POST $baseUrl/api/login - ${response.statusCode}');
      final authResponse = AuthResponse.fromJson(response.data);
      setAuthToken(authResponse.token);
      debugPrint("Ankush Banawade ${authResponse.user.role}");
      return authResponse;
    } on DioException catch (e) {
      debugPrint('\n========================================');
      debugPrint('❌ LOGIN ERROR');
      debugPrint('========================================');
      debugPrint('URL: ${e.requestOptions.uri}');
      debugPrint('Method: ${e.requestOptions.method}');
      debugPrint('Status Code: ${e.response?.statusCode}');
      debugPrint('Request Headers: ${e.requestOptions.headers}');
      debugPrint('Request Data: ${e.requestOptions.data}');
      debugPrint('Response Data: ${e.response?.data}');
      debugPrint('========================================\n');

      // Extract error message from response
      String errorMessage = 'Login failed';

      if (e.response?.data != null) {
        final responseData = e.response!.data;

        // Handle different response formats
        if (responseData is Map<String, dynamic>) {
          errorMessage = responseData['message'] ??
              responseData['error'] ??
              'Invalid credentials';
        } else if (responseData is String) {
          errorMessage = responseData;
        }
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = 'Connection timeout. Please check your internet.';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Server not responding. Please try again.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage = 'No internet connection';
      }

      throw Exception(errorMessage);
    } catch (e) {
      debugPrint('❌ Unexpected Login Error: $e');
      throw Exception('Login failed: ${e.toString()}');
    }
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
    return (response.data as List)
        .map((item) => ChatModel.fromJson(item))
        .toList();
  }

  // Users & Chat APIs
  Future<List<dynamic>> getChatList() async {
    debugPrint('API Call: GET $baseUrl/api/users/chat-list');
    final response = await _dio.get('/api/users/chat-list');
    debugPrint(
        'API Response: GET $baseUrl/api/users/chat-list - ${response.data}');
    return response.data as List<dynamic>;
  }

  Future<List<User>> searchUsers(String query,{int page = 1}) async {
    debugPrint('API Call: GET $baseUrl/api/users/search?page=$page&query=$query');
    final response =
        await _dio.get('/api/users/search', queryParameters: {'query': query,'page': page});
    debugPrint(
        'API Response: GET $baseUrl/api/users/search?page=$page - ${response.data}');
    
    // Handle response structure: {data: [...]} or [...]
    final List<dynamic> userList;
    if (response.data is Map && response.data['data'] != null) {
      userList = response.data['data'] as List;
    } else if (response.data is List) {
      userList = response.data as List;
    } else {
      return [];
    }
    
    return userList.map((item) {
      debugPrint("Ankush catch ${User.fromJson(item)}");
      return User.fromJson(item);
    }).toList();
  }

  Future<List<User>> getTeachers() async {
    debugPrint('API Call: GET $baseUrl/api/users/teachers');
    final response = await _dio.get('/api/users/teachers');
    debugPrint(
        'API Response: GET $baseUrl/api/users/teachers - ${response.data}');
    return (response.data as List).map((item) => User.fromJson(item)).toList();
  }

  Future<List<User>> getParents() async {
    debugPrint('API Call: GET $baseUrl/api/users/parents');
    final response = await _dio.get('/api/users/parents');
    debugPrint(
        'API Response: GET $baseUrl/api/users/parents - ${response.data}');
    return (response.data as List).map((item) => User.fromJson(item)).toList();
  }

  Future<List<User>> getChatPermissions() async {
    debugPrint('API Call: GET $baseUrl/api/users/chat-permissions');
    final response = await _dio.get('/api/users/chat-permissions');
    debugPrint(
        'API Response: GET $baseUrl/api/users/chat-permissions - ${response.data}');
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
    if (replyToMessageId != null)
      request['reply_to_message_id'] = int.parse(replyToMessageId);
    if (old_firebase_message_id != null)
      request['old_firebase_message_id'] = old_firebase_message_id;

    debugPrint('API Call: POST $baseUrl/api/message/save - Request: $request');
    final response = await _dio.post('/api/message/save', data: request);
    debugPrint(
        'API Response: POST $baseUrl/api/message/save - ${response.data}');
    return Message.fromJson(response.data);
  }

  Future<FileUploadResponse> uploadFile(File file, String messageType) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path),
      'message_type': messageType,
    });

    debugPrint(
        'API Call: POST $baseUrl/api/message/upload - File: ${file.path}, Type: $messageType');
    final response = await _dio.post(
      '/api/message/upload',
      data: formData,
      options: Options(
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          // Content-Type will be set automatically by Dio for FormData (multipart/form-data)
        },
      ),
    );
    debugPrint(
        'API Response: POST $baseUrl/api/message/upload - ${response.data}');
    return FileUploadResponse.fromJson(response.data);
  }

  Future<PaginatedResponse<Message>> getConversation(
      int userId, int page, int limit) async {
    debugPrint(
        'API Call: GET $baseUrl/api/messages/conversation/$userId?page=$page&limit=$limit');
    final response = await _dio.get(
      '/api/messages/conversation/$userId?page=$page&limit=$limit',
      queryParameters: {'page': page, 'limit': limit},
    );
    debugPrint(
        'API Response: GET $baseUrl/api/messages/conversation/$userId - ${response.data}');
    final data = response.data as Map<String, dynamic>;
    final messages = _messagesFromResponse(data['messages']);
    debugPrint(" API sync error: ${data['user']}");
    final user = _metadataFromResponse(
      data,
      id: userId,
      type: 'user',
      fallbackName: 'Chat',
    );

    return PaginatedResponse(
      data: messages,
      user: user,
      total: data['total'] ?? 0,
      page: data['current_page'] ?? 1,
      limit: data['per_page'] ?? 50,
    );
  }

  Future<PaginatedResponse<Message>> getGroupMessages(
      int groupId, int page, int limit) async {
    debugPrint(
        'API Call: GET Group $baseUrl/api/messages/group/$groupId?page=$page&limit=$limit');
    final StorageService _storage = StorageService();
    final token = await _storage.getToken();
    // debugPrint("API Request Headers: $token");
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
    final response = await _dio.get(
      '/api/messages/group/$groupId',
      queryParameters: {'page': page, 'limit': limit},
      options: Options(
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization':'Bearer $token'
          // Content-Type will be set automatically by Dio for FormData (multipart/form-data)
        },
      )
    );
    debugPrint(
        'API Response: GET $baseUrl/api/messages/group/$groupId?page=$page&limit=$limit - ${response.data}');

    final data = response.data as Map<String, dynamic>;
    final messages = _messagesFromResponse(data['messages']);
    final user = _metadataFromResponse(
      data,
      id: groupId,
      type: 'group',
      fallbackName: 'Group',
    );

    debugPrint("Ankush Banawade Messahes $user");
    return PaginatedResponse(
      data: messages,
      user: user,
      total: data['total'] ?? 0,
      page: data['current_page'] ?? 1,
      limit: data['per_page'] ?? 25,
    );
  }

  Future<void> markMessageAsDelivered(int messageId) async {
    debugPrint('API Call: PATCH $baseUrl/api/message/$messageId/delivered');
    await _dio.patch('/api/message/$messageId/delivered');
    debugPrint(
        'API Response: PATCH $baseUrl/api/message/$messageId/delivered - Success');
  }

  Future<void> markMessageAsRead(int messageId) async {
    debugPrint('API Call: PATCH $baseUrl/api/message/$messageId/read');
    debugPrint('_markMessageAsRead $baseUrl/api/message/$messageId/read');
    var data = await _dio.patch('/api/message/$messageId/read');
    debugPrint(
        'API Response: PATCH $baseUrl/api/message/$messageId/read - $data Success');
    debugPrint(
        '_markMessageAsRead $baseUrl/api/message/$messageId/read - $data Success');
  }

  Future<Map<String, dynamic>> jumpToMessage(
      int messageId, String userId) async {
    debugPrint(
        'API Call: GET $baseUrl/api/message/$messageId/jump?user_id=$userId');
    final response = await _dio.get('/api/message/$messageId/jump',
        queryParameters: {'user_id': userId});
    debugPrint(
        'API Response: GET $baseUrl/api/message/$messageId/jump - ${response.data}');
    return response.data;
  }

  // User Status APIs
  Future<void> setOnlineStatus() async {
    debugPrint('API Call: POST /api/user/status/online');
    final response = await _dio.post('/api/user/status/online');
    debugPrint(
        'API Response: POST /api/user/status/online - Success${response.data}${response.statusCode}');
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
  Future<ProfilePictureResponse> uploadProfilePicture(
      File profilePicture) async {
    debugPrint(
        'API Call: POST /api/profile/upload-picture - File: ${profilePicture.path}');
    final formData = FormData.fromMap({
      'profile_picture': await MultipartFile.fromFile(profilePicture.path),
    });

    final response = await _dio.post(
      '/api/profile/upload-picture',
      data: formData,
      options: Options(
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          // Content-Type will be set automatically by Dio for FormData (multipart/form-data)
        },
      ),
    );
    debugPrint(
        'API Response: POST /api/profile/upload-picture - ${response.data}');
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
    debugPrint(
        'API Call: POST $baseUrl/api/attendance/mark - Request: $request');
    try {
      final response = await _dio.post('/api/attendance/mark', data: request);
      debugPrint(
          'API Response: POST $baseUrl/api/attendance/mark - $response Success');
    } on DioException catch (e) {
      _logApiError(e, 'Mark Attendance');
      final message =
          e.response?.data['message'] ?? 'Failed to mark attendance';
      throw Exception('$message');
    }
  }

  Future<Map<String, dynamic>> getTodayAttendanceStatus(int groupId) async {
    debugPrint(
        'API Call: GET $baseUrl/api/attendance/today-status?group_id=$groupId');
    final response = await _dio.get(
      '/api/attendance/today-status',
      queryParameters: {'group_id': groupId},
    );
    debugPrint(
        'API Response: GET $baseUrl/api/attendance/today-status - ${response.data}');
    return response.data;
  }

  // ============================================================================
  // CRITICAL OFFLINE MODE APIs
  // ============================================================================

  /// API 1: Batch Message Send - Send multiple queued messages in one request
  /// Group Messages with Replies Request Format:
  /// {
  ///   "messages": [
  ///     {
  ///       "temp_id": "msg_reply_001",
  ///       "chat_id": 1,
  ///       "chat_type": "group",
  ///       "type": "text",
  ///       "message": "Original message",
  ///       "firebase_key": "key_reply_001"
  ///     },
  ///     {
  ///       "temp_id": "msg_reply_002",
  ///       "chat_id": 1,
  ///       "chat_type": "group",
  ///       "type": "text",
  ///       "message": "Reply to message",
  ///       "reply_to_message_id": 50,
  ///       "firebase_key": "key_reply_002"
  ///     }
  ///   ]
  /// }
  /// Response: {"success": true, "data": {"sent": [...], "failed": [...], "total_sent": 2, "total_failed": 0}}
  Future<Map<String, dynamic>> batchSendMessages(
      List<Map<String, dynamic>> messages) async {
    debugPrint(
        '🚀 API Call: POST $baseUrl/api/messages/batch-send - Count: ${messages.length}');

    // Format messages to match exact API spec
    final formattedMessages = messages.map((msg) {
      // Base required fields
      final formatted = <String, dynamic>{
        'temp_id': msg['temp_id']?.toString() ??
            'temp_${DateTime.now().millisecondsSinceEpoch}',
        'chat_id': int.tryParse(msg['chat_id']?.toString() ?? '0') ?? 0,
        'chat_type': msg['chat_type']?.toString() ?? 'group',
        'type': msg['type']?.toString() ?? 'text',
        'message': msg['message']?.toString() ?? '',
        'firebase_key': msg['firebase_key']?.toString() ?? '',
      };

      // reply_to_message_id - IMPORTANT: must be integer if present
      if (msg.containsKey('reply_to_message_id') &&
          msg['reply_to_message_id'] != null) {
        final replyId = msg['reply_to_message_id'];
        if (replyId is int) {
          formatted['reply_to_message_id'] = replyId;
        } else if (replyId is String && replyId.isNotEmpty) {
          formatted['reply_to_message_id'] = int.tryParse(replyId) ?? 0;
        }
      }

      // Other optional fields
      if (msg.containsKey('client_timestamp') &&
          msg['client_timestamp'] != null) {
        formatted['client_timestamp'] = msg['client_timestamp'];
      }
      if (msg.containsKey('file_path') && msg['file_path'] != null) {
        formatted['file_path'] = msg['file_path'];
      }
      if (msg.containsKey('file_name') && msg['file_name'] != null) {
        formatted['file_name'] = msg['file_name'];
      }
      if (msg.containsKey('file_size') && msg['file_size'] != null) {
        formatted['file_size'] = msg['file_size'];
      }
      if (msg.containsKey('is_forwarded') && msg['is_forwarded'] != null) {
        formatted['is_forwarded'] = msg['is_forwarded'];
      }

      return formatted;
    }).toList();

    // Log sample with reply info
    if (formattedMessages.isNotEmpty) {
      final sample = formattedMessages.first;
      final hasReply = sample.containsKey('reply_to_message_id');
      debugPrint(
          '📤 Sample: ${sample['temp_id']} ${hasReply ? '↩️ (reply to: ${sample['reply_to_message_id']})' : ''}');
    }

    try {
      final response = await _dio.post(
        '/api/messages/batch-send',
        data: {'messages': formattedMessages},
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

      debugPrint('📥 Response status: ${response.statusCode}');

      final data = response.data;
      if (data['success'] == true) {
        final sent = data['data']['sent'] as List? ?? [];
        final failed = data['data']['failed'] as List? ?? [];
        final totalSent = data['data']['total_sent'] ?? sent.length;
        final totalFailed = data['data']['total_failed'] ?? failed.length;

        debugPrint('✅ Batch Send Success:');
        debugPrint('   → Sent: $totalSent messages');
        debugPrint('   → Failed: $totalFailed messages');

        // Log sent messages with reply info
        if (sent.isNotEmpty) {
          for (final m in sent.take(5)) {
            final tempId = m['temp_id'];
            final serverId = m['id'] ?? m['msgId'];
            final originalMsg = formattedMessages.firstWhere(
              (msg) => msg['temp_id'] == tempId,
              orElse: () => {},
            );
            final hasReply = originalMsg.containsKey('reply_to_message_id');
            debugPrint('   ✓ $tempId → id:$serverId ${hasReply ? '↩️' : ''}');
          }
          if (sent.length > 5) {
            debugPrint('   ... and ${sent.length - 5} more');
          }
        }

        // Log failed messages
        if (failed.isNotEmpty) {
          for (final f in failed.take(3)) {
            debugPrint(
                '   ⚠️ Failed: ${f['temp_id']} - ${f['error_code']}: ${f['error']}');
          }
        }

        return data;
      } else {
        final errorMsg = data['message'] ?? 'Unknown error';
        debugPrint('❌ Batch send failed: $errorMsg');
        throw Exception('Batch send failed: $errorMsg');
      }
    } catch (e) {
      if (e is DioException) {
        debugPrint('❌ Batch Send DioError:');
        debugPrint('   → Status: ${e.response?.statusCode}');
        debugPrint('   → Message: ${e.message}');
        debugPrint('   → Response: ${e.response?.data}');
      } else {
        debugPrint('❌ Batch Send Error: $e');
      }
      rethrow;
    }
  }

  /// API 2: Incremental Message Sync - Fetch only new/updated messages since last sync
  /// Query: chat_id=1&chat_type=group&since=2026-06-05T00:00:00Z&limit=100
  /// Note: chat_id as integer in query string
  /// Response Fields:
  /// - messages: Array with id, msgId, chat_id, sender_id, sender_name, profile_picture_url, content, type,
  ///   file_path, file_name, file_size, reply_to_message_id, reply_to_message{id, content, sender{id, name}},
  ///   is_forwarded, firebase_id, created_at, updated_at, read_at
  /// - deleted_message_ids: Array of string IDs
  /// - updated_messages: Array with id, msgId, content, updated_at
  /// - has_more: boolean, next_page_token: string|null, synced_at: ISO timestamp
  Future<Map<String, dynamic>> syncMessages({
    required String chatId,
    required String chatType,
    required DateTime since,
    int limit = 100,
  }) async {
    final params = {
      'chat_id': int.tryParse(chatId) ?? chatId,
      'chat_type': chatType,
      'since': since.toIso8601String(),
      'limit': limit,
    };
    debugPrint('🔄 API Call: GET $baseUrl/api/messages/sync');
    debugPrint(
        '📊 Params: chat_id=${params['chat_id']}, type=$chatType, since=${since.toIso8601String()}');

    try {
      final response = await _dio.get(
        '/api/messages/sync',
        queryParameters: params,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data;
      if (data['success'] == true) {
        final messages = data['data']['messages'] as List? ?? [];
        final deletedIds = data['data']['deleted_message_ids'] as List? ?? [];
        final updatedMsgs = data['data']['updated_messages'] as List? ?? [];
        final hasMore = data['data']['has_more'] ?? false;
        final syncedAt = data['data']['synced_at'];
        final nextPageToken = data['data']['next_page_token'];

        debugPrint(
            '✅ Sync Success: ${messages.length} new, ${updatedMsgs.length} updated, ${deletedIds.length} deleted');
        debugPrint(
            '   has_more=$hasMore, next_token=${nextPageToken != null ? "yes" : "null"}, synced_at=$syncedAt');

        // Log sample with reply & profile info
        if (messages.isNotEmpty) {
          final sample = messages.first;
          final hasReply = sample['reply_to_message_id'] != null;
          final hasProfile = sample['profile_picture_url'] != null;
          final isForwarded = sample['is_forwarded'] == true;
          debugPrint(
              '   📝 Sample: "${sample['content']}" by ${sample['sender_name']}${hasProfile ? " 📷" : ""}${hasReply ? " ↩️ reply:${sample['reply_to_message_id']}" : ""}${isForwarded ? " ⤴️" : ""}');

          if (hasReply && sample['reply_to_message'] != null) {
            final replyMsg = sample['reply_to_message'];
            final replySender = replyMsg['sender'];
            debugPrint(
                '      ↪️ Replying to: "${replyMsg['content']}" by ${replySender['name']} (id:${replySender['id']})');
          }
        }

        // Log updated messages
        if (updatedMsgs.isNotEmpty) {
          for (final upd in updatedMsgs.take(3)) {
            debugPrint(
                '   ✏️ Updated: id=${upd['msgId']}, new_content="${upd['content']}", at=${upd['updated_at']}');
          }
        }

        return data;
      } else {
        throw Exception('Message sync failed: ${data['message']}');
      }
    } catch (e) {
      debugPrint('❌ Message Sync Error: $e');
      rethrow;
    }
  }

  /// API 3: Incremental Chat List Sync - Fetch only changed chats since last sync
  /// Query: since=2026-06-05T00:00:00Z&limit=50
  /// Response Fields:
  /// - new_chats: Array with id, type (group/user), name, profile_picture, last_message,
  ///   last_message_time, last_read_at, unread_count, is_pinned, attendance_group (groups only),
  ///   member_count (groups only), actual_role (users only), created_at, updated_at
  /// - updated_chats: Same structure as new_chats
  /// - deleted_chat_ids: Array of string IDs
  /// - synced_at: ISO timestamp
  Future<Map<String, dynamic>> syncChats(
      {DateTime? since, int limit = 50}) async {
    final params = {
      if (since != null) 'since': since.toIso8601String(),
      'limit': limit,
    };
    debugPrint('🔄 API Call: GET $baseUrl/api/chats/sync');
    debugPrint(
        '📊 Params: limit=$limit${since != null ? ", since=${since.toIso8601String()}" : " (full sync)"}');

    try {
      final response = await _dio.get(
        '/api/chats/sync',
        queryParameters: params,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json'
          },
        ),
      );

      final data = response.data;
      if (data['success'] == true) {
        final newChats = data['data']['new_chats'] as List? ?? [];
        final updatedChats = data['data']['updated_chats'] as List? ?? [];
        final deletedIds = data['data']['deleted_chat_ids'] as List? ?? [];
        final syncedAt = data['data']['synced_at'];

        debugPrint(
            '✅ Chat Sync Success: ${newChats.length} new, ${updatedChats.length} updated, ${deletedIds.length} deleted');
        debugPrint('   synced_at=$syncedAt');

        // Log sample new chat with details
        if (newChats.isNotEmpty) {
          final sample = newChats.first;
          final isGroup = sample['type'] == 'group';
          final hasProfile = sample['profile_picture'] != null;
          final isPinned = sample['is_pinned'] == true;
          final unread = sample['unread_count'] ?? 0;
          debugPrint(
              '   🆕 New: ${isGroup ? "👥" : "👤"} ${sample['name']}${hasProfile ? " 📷" : ""}${isPinned ? " 📌" : ""} - $unread unread');
          if (isGroup) {
            debugPrint(
                '      members=${sample['member_count']}, attendance=${sample['attendance_group']}');
          } else {
            debugPrint('      role=${sample['actual_role']}');
          }
        }

        // Log sample updated chat
        if (updatedChats.isNotEmpty) {
          final sample = updatedChats.first;
          final isGroup = sample['type'] == 'group';
          final unread = sample['unread_count'] ?? 0;
          debugPrint(
              '   🔄 Updated: ${isGroup ? "👥" : "👤"} ${sample['name']} - $unread unread, last: "${sample['last_message']}"');
        }

        // Log deleted chats
        if (deletedIds.isNotEmpty) {
          debugPrint(
              '   🗑️ Deleted: ${deletedIds.take(5).join(", ")}${deletedIds.length > 5 ? "..." : ""}');
        }

        return data;
      } else {
        throw Exception('Chat sync failed: ${data['message']}');
      }
    } catch (e) {
      debugPrint('❌ Chat Sync Error: $e');
      rethrow;
    }
  }

  /// API 4: Batch Mark as Read - Mark multiple messages as read in single call
  /// Request (Group): {"message_ids": [501, 502, 503, 504, 505], "chat_id": 1, "chat_type": "group"}
  /// Request (User): {"message_ids": [510, 511, 512], "chat_id": 5, "chat_type": "user"}
  /// Note: message_ids as integer array, chat_id as integer (not string)
  /// Response: {"success": true, "data": {"marked_count": 5, "failed_ids": [], "marked_at": "2026-06-06T11:45:00+00:00"}}
  Future<Map<String, dynamic>> batchMarkAsRead({
    required List<int> messageIds,
    required String chatId,
    required String chatType,
  }) async {
    final chatIdInt = int.tryParse(chatId) ?? 0;
    final request = {
      'message_ids': messageIds,
      'chat_id': chatIdInt,
      'chat_type': chatType,
    };

    debugPrint('📖 API Call: POST $baseUrl/api/messages/batch-read');
    debugPrint(
        '📤 Request: ${chatType == "group" ? "👥" : "👤"} chat_id=$chatIdInt, type=$chatType, count=${messageIds.length}');
    debugPrint(
        '   message_ids: ${messageIds.take(10).join(", ")}${messageIds.length > 10 ? "... +${messageIds.length - 10} more" : ""}');

    try {
      final response = await _dio.post(
        '/api/messages/batch-read',
        data: request,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data;
      if (data['success'] == true) {
        final markedCount = data['data']['marked_count'] ?? 0;
        final failedIds = data['data']['failed_ids'] as List? ?? [];
        final markedAt = data['data']['marked_at'];

        debugPrint('✅ Batch Read Success:');
        debugPrint('   ✓ Marked: $markedCount messages');
        if (failedIds.isNotEmpty) {
          debugPrint(
              '   ⚠️ Failed: ${failedIds.length} messages - ids: ${failedIds.take(5).join(", ")}');
        }
        debugPrint('   🕓 Marked at: $markedAt');

        return data;
      } else {
        final errorMsg = data['message'] ?? 'Unknown error';
        debugPrint('❌ Batch read failed: $errorMsg');
        throw Exception('Batch mark as read failed: $errorMsg');
      }
    } catch (e) {
      if (e is DioException) {
        debugPrint('❌ Batch Read DioError:');
        debugPrint('   → Status: ${e.response?.statusCode}');
        debugPrint('   → Message: ${e.message}');
        debugPrint('   → Response: ${e.response?.data}');
      } else {
        debugPrint('❌ Batch Read Error: $e');
      }
      rethrow;
    }
  }

  /// API 5: Queue Status - Check pending/failed message counts for authenticated user
  /// No query parameters required (uses authenticated user's session)
  /// Response: {
  ///   "success": true,
  ///   "data": {
  ///     "pending_messages": 12,
  ///     "pending_uploads": 3,
  ///     "failed_messages": 0,
  ///     "oldest_pending_timestamp": "2026-06-06T10:30:00+00:00",
  ///     "queue_size_mb": 0,
  ///     "is_queue_full": false,
  ///     "max_queue_size": 1000
  ///   }
  /// }
  Future<Map<String, dynamic>> getQueueStatus() async {
    debugPrint('📊 API Call: GET $baseUrl/api/sync/queue-status');

    try {
      final response = await _dio.get(
        '/api/sync/queue-status',
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data;
      if (data['success'] == true) {
        final pending = data['data']['pending_messages'] ?? 0;
        final uploads = data['data']['pending_uploads'] ?? 0;
        final failed = data['data']['failed_messages'] ?? 0;
        final oldestTimestamp = data['data']['oldest_pending_timestamp'];
        final queueSizeMb = data['data']['queue_size_mb'] ?? 0;
        final isFull = data['data']['is_queue_full'] ?? false;
        final maxSize = data['data']['max_queue_size'] ?? 1000;

        debugPrint('✅ Queue Status:');
        debugPrint('   📨 Pending messages: $pending');
        debugPrint('   📤 Pending uploads: $uploads');
        debugPrint('   ❌ Failed messages: $failed');
        if (oldestTimestamp != null) {
          debugPrint('   🕐 Oldest pending: $oldestTimestamp');
        }
        debugPrint('   💾 Queue size: ${queueSizeMb}MB');
        debugPrint(
            '   📏 Capacity: $pending/$maxSize ${isFull ? "(FULL ⚠️)" : ""}');

        return data;
      } else {
        final errorMsg = data['message'] ?? 'Unknown error';
        debugPrint('❌ Queue status failed: $errorMsg');
        throw Exception('Queue status failed: $errorMsg');
      }
    } catch (e) {
      if (e is DioException) {
        debugPrint('❌ Queue Status DioError:');
        debugPrint('   → Status: ${e.response?.statusCode}');
        debugPrint('   → Message: ${e.message}');
      } else {
        debugPrint('❌ Queue Status Error: $e');
      }
      rethrow;
    }
  }

  /// API 6: App Version Check - Check for updates
  /// Query: current_version=1.0.23 (required)
  /// Public API - NO authentication required
  ///
  /// Response (No Update):
  /// {
  ///   "success": true,
  ///   "data": {
  ///     "update_available": false,
  ///     "current_version": "1.0.23",
  ///     "latest_version": "1.0.23",
  ///     "message": "You have the latest version"
  ///   }
  /// }
  ///
  /// Response (Optional Update):
  /// {
  ///   "success": true,
  ///   "data": {
  ///     "update_available": true,
  ///     "current_version": "1.0.23",
  ///     "latest_version": "1.0.25",
  ///     "update_type": "optional",
  ///     "can_skip": true,
  ///     "release_notes": "Bug fixes and improvements",
  ///     "download_url": "https://play.google.com/store/apps/details?id=...",
  ///     "direct_apk_url": "https://gatewayreports.in/downloads/app-v1.0.25.apk",
  ///     "apk_size_mb": 25.5,
  ///     "release_date": "2026-06-06",
  ///     "min_supported_version": "1.0.20"
  ///   }
  /// }
  ///
  /// Response (Force Update):
  /// {
  ///   "success": true,
  ///   "data": {
  ///     "update_available": true,
  ///     "current_version": "1.0.18",
  ///     "latest_version": "1.0.25",
  ///     "update_type": "force",
  ///     "can_skip": false,
  ///     "force_update_message": "Critical security update required",
  ///     "download_url": "https://play.google.com/store/apps/details?id=...",
  ///     "direct_apk_url": "https://gatewayreports.in/downloads/app-v1.0.25.apk"
  ///   }
  /// }
  Future<Map<String, dynamic>> checkAppVersion({
    required String currentVersion,
  }) async {
    final params = {
      'current_version': currentVersion,
    };
    debugPrint('🔍 API Call: GET $baseUrl/api/app/version-check?current_version=$currentVersion');
    debugPrint('   Current version: v$currentVersion');

    try {
      final response = await _dio.get(
        '/api/app/version-check?current_version=$currentVersion',
        queryParameters: params,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );
      debugPrint('✅ Version Check: Up to date${response.data}');
      final data = response.data;
      if (data['success'] == true) {
        final updateAvailable = data['data']['update_available'] ?? false;
        final latestVersion = data['data']['latest_version'] ?? currentVersion;
        final currentVer = data['data']['current_version'] ?? currentVersion;
        final message = data['data']['message'];

        if (!updateAvailable) {
          debugPrint('✅ Version Check: Up to date');
          debugPrint('   ✓ Current: v$currentVer = Latest: v$latestVersion');
          debugPrint('   💬 $message');
        } else {
          final updateType = data['data']['update_type'] ?? 'optional';
          final canSkip = data['data']['can_skip'] ?? true;
          final releaseNotes = data['data']['release_notes'];
          final apkSizeMb = data['data']['apk_size_mb'];
          final forceMessage = data['data']['force_update_message'];

          debugPrint('🔔 Version Check: Update Available');
          debugPrint('   Current: v$currentVer → Latest: v$latestVersion');
          debugPrint(
              '   Type: ${updateType.toUpperCase()} ${canSkip ? "(can skip)" : "(REQUIRED ⚠️)"}');

          if (updateType == 'force' && forceMessage != null) {
            debugPrint('   ⚠️ $forceMessage');
          }

          if (releaseNotes != null) {
            debugPrint('   📝 Release notes: $releaseNotes');
          }

          if (apkSizeMb != null) {
            debugPrint('   💾 APK size: ${apkSizeMb}MB');
          }

          if (data['data']['download_url'] != null) {
            debugPrint('   🔗 Play Store: ${data['data']['download_url']}');
          }

          if (data['data']['direct_apk_url'] != null) {
            debugPrint('   📦 Direct APK: ${data['data']['direct_apk_url']}');
          }
        }

        return data;
      } else {
        final errorMsg = data['message'] ?? 'Unknown error';
        debugPrint('❌ Version check failed: $errorMsg');
        throw Exception('Version check failed: $errorMsg');
      }
    } catch (e) {
      if (e is DioException) {
        debugPrint('❌ Version Check DioError:');
        debugPrint('   → Status: ${e.response?.statusCode}');
        debugPrint('   → Message: ${e.message}');
      } else {
        debugPrint('❌ Version Check Error: $e');
      }
      rethrow;
    }
  }
}
