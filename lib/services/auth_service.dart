import '../models/user_model.dart';
import '../storage/hive_storage.dart';
import 'api_service.dart';

class AuthService {
  static Future<UserModel?> login(String username, String password) async {
    final res = await ApiService.post(
      '/auth/login',
      data: {'username': username, 'password': password},
    );
    final user = UserModel.fromJson(res.data['user']);
    await HiveStorage.saveUser(user);
    await HiveStorage.saveTokens(
      res.data['accessToken'],
      res.data['refreshToken'],
    );
    return user;
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
