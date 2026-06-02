import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/api_service_simple.dart';
import '../models/user_model.dart';

class AuthService {
  final ApiClient _apiClient;

  AuthService(this._apiClient);

  Future<Map<String, dynamic>> login(LoginRequest request) async {
    return await _apiClient.post(AppConstants.epLogin, data: request.toJson());
  }

  Future<Map<String, dynamic>> register(RegisterRequest request) async {
    return await _apiClient.post(AppConstants.epRegister, data: request.toJson());
  }

  Future<void> logout() async {
    await _apiClient.post(AppConstants.epLogout);
  }

  Future<UserModel> getProfile() async {
    final response = await _apiClient.get(AppConstants.epProfile);
    return UserModel.fromJson(response['data']);
  }
}
