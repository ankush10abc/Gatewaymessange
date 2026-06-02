import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

class SingleDeviceAuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  static const String baseUrl = 'https://your-api-url.com';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final Dio _dio = Dio();
  static GlobalKey<NavigatorState>? navigatorKey;

  static Future<bool> isTokenValid() async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final response = await _dio.get(
        '$baseUrl/api/me',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<void> handleApiResponse(Response response) async {
    if (response.statusCode == 401) {
      await logout();

      if (navigatorKey?.currentState != null) {
        navigatorKey!.currentState!.pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );

        ScaffoldMessenger.of(navigatorKey!.currentContext!).showSnackBar(
          const SnackBar(
            content: Text('You have been logged out from another device'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  static Future<Map<String, dynamic>?> login(String mobile, String password) async {
    try {
      final response = await _dio.post(
        '$baseUrl/api/login',
        data: {
          'mobile': mobile,
          'password': password,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        await saveToken(data['token']);
        await saveUser(data['user']);
        return data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<void> logout() async {
    try {
      final token = await getToken();
      if (token != null) {
        await _dio.post(
          '$baseUrl/api/logout',
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          ),
        );
      }
    } catch (e) {
      // Continue with local logout even if API fails
    }

    // Clear local storage
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }

  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    await _storage.write(key: _userKey, value: jsonEncode(user));
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final userStr = await _storage.read(key: _userKey);
    if (userStr != null) {
      return jsonDecode(userStr);
    }
    return null;
  }

  static Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}

class ApiInterceptor {
  static Future<Response> secureRequest(
    Future<Response> Function() request,
  ) async {
    final response = await request();
    await SingleDeviceAuthService.handleApiResponse(response);
    return response;
  }

  static Future<Response> get(String url) async {
    final token = await SingleDeviceAuthService.getToken();
    return secureRequest(() => Dio().get(
      url,
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ),
    ));
  }

  static Future<Response> post(String url, Map<String, dynamic> body) async {
    final token = await SingleDeviceAuthService.getToken();
    return secureRequest(() => Dio().post(
      url,
      data: body,
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    ));
  }
}
