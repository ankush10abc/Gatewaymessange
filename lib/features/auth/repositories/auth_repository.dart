import '../../../core/storage/storage_service.dart';
import '../../../core/services/api_service_simple.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';

class AuthRepository {
  final AuthService _authService;
  final StorageService _storageService;

  AuthRepository(this._authService, this._storageService);

  Future<UserModel> login(LoginRequest request) async {
    final response = await _authService.login(request);
    await _storageService.saveToken(response['token']);
    await _storageService.saveUserId(response['user']['id']);
    return UserModel.fromJson(response['user']);
  }

  Future<UserModel> register(RegisterRequest request) async {
    final response = await _authService.register(request);
    await _storageService.saveToken(response['token']);
    await _storageService.saveUserId(response['user']['id']);
    return UserModel.fromJson(response['user']);
  }

  Future<void> logout() async {
    await _authService.logout();
    await _storageService.clearAll();
  }

  Future<UserModel> getProfile() async {
    return await _authService.getProfile();
  }

  Future<bool> isLoggedIn() async {
    final token = await _storageService.getToken();
    return token != null;
  }
}
