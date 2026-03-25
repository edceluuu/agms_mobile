import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../storage/hive_storage.dart';
import '../utils/constants.dart';
import 'api_service.dart';

class AuthService {
  static Future<UserModel?> login(String username, String password) async {
    try {
      debugPrint('🔵 BASE_URL: ${AppConstants.baseUrl}');
      debugPrint('🔵 Calling: /auth/login');
      debugPrint('🔵 Username: $username');

      final res = await ApiService.post(
        '/auth/login',
        data: {'username': username, 'password': password},
      );

      debugPrint('🟢 Status: ${res.statusCode}');
      debugPrint('🟢 Response: ${res.data}');

      final user = UserModel.fromJson(res.data['user']);
      debugPrint('🟢 User parsed: ${user.username}');

      await HiveStorage.saveUser(user);
      await HiveStorage.saveTokens(
        res.data['accessToken'],
        res.data['refreshToken'],
      );

      debugPrint('🟢 Login complete');
      return user;
    } catch (e) {
      debugPrint('🔴 Login failed: $e');
      rethrow;
    }
  }

  static Future<void> logout() async {
    try {
      final refresh = HiveStorage.getRefreshToken();
      await ApiService.post('/auth/logout', data: {'refreshToken': refresh});
    } catch (_) {}
    await HiveStorage.clearUser();
    await HiveStorage.clearTokens();
  }

  static UserModel? getCurrentUser() => HiveStorage.getUser();
  static bool isLoggedIn() => HiveStorage.getAccessToken() != null;
}
