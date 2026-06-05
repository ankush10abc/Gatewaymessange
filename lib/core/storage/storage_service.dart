import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import '../constants/app_constants.dart';
import '../models/user_model.dart';

class StorageService {
  SharedPreferences? _prefs;
  bool _initialized = false;
  
  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await Hive.initFlutter();
    await Hive.openBox(AppConstants.boxServices);
    await Hive.openBox(AppConstants.boxBookings);
    await Hive.openBox(AppConstants.boxCache);
    _initialized = true;
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }

  // Token Management
  Future<void> saveToken(String token) async {
    await _ensureInitialized();
    await _prefs!.setString(AppConstants.keyToken, token);
  }

  Future<String?> getToken() async {
    await _ensureInitialized();
    return _prefs!.getString(AppConstants.keyToken);
  }

  Future<void> clearToken() async {
    await _ensureInitialized();
    await _prefs!.remove(AppConstants.keyToken);
  }

  // User Data
  Future<void> saveUserId(String userId) async {
    await _ensureInitialized();
    await _prefs!.setString(AppConstants.keyUserId, userId);
  }

  Future<String?> getUserId() async {
    await _ensureInitialized();
    return _prefs!.getString(AppConstants.keyUserId);
  }

  Future<void> saveUserType(String userType) async {
    await _ensureInitialized();
    await _prefs!.setString(AppConstants.keyUserType, userType);
  }

  Future<String?> getUserType() async {
    await _ensureInitialized();
    return _prefs!.getString(AppConstants.keyUserType);
  }

  Future<void> saveUser(User user) async {
    await _ensureInitialized();
    await _prefs!.setString('user_data', jsonEncode(user.toJson()));
  }

  Future<User?> getUser() async {
    await _ensureInitialized();
    final userData = _prefs!.getString('user_data');
    if (userData != null) {
      return User.fromJson(jsonDecode(userData));
    }
    return null;
  }

  Future<void> clearAll() async {
    await _ensureInitialized();
    await _prefs!.clear();
    await Hive.box(AppConstants.boxServices).clear();
    await Hive.box(AppConstants.boxBookings).clear();
    await Hive.box(AppConstants.boxCache).clear();
  }

  // Hive Cache
  Box getServicesBox() => Hive.box(AppConstants.boxServices);
  Box getBookingsBox() => Hive.box(AppConstants.boxBookings);
  Box getCacheBox() => Hive.box(AppConstants.boxCache);
}
