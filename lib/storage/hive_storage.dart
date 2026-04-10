import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_model.dart';

class HiveStorage {
  static const _authBox = 'auth';
  static const _tokenBox = 'tokens';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(UserModelAdapter());
    await Hive.openBox<UserModel>(_authBox);
    await Hive.openBox<String>(_tokenBox);
    await Hive.openBox('plant_history');
    await Hive.openBox('plant_pins');
    await Hive.openBox('pending_readings');
    await Hive.openBox('pending_plants');
    await Hive.openBox('pending_deletions');
  }

  // User
  static Future<void> saveUser(UserModel user) async {
    await Hive.box<UserModel>(_authBox).put('currentUser', user);
  }

  static UserModel? getUser() {
    return Hive.box<UserModel>(_authBox).get('currentUser');
  }

  static Future<void> clearUser() async {
    await Hive.box<UserModel>(_authBox).delete('currentUser');
  }

  // Tokens
  static Future<void> saveTokens(String access, String refresh) async {
    final box = Hive.box<String>(_tokenBox);
    await box.put('accessToken', access);
    await box.put('refreshToken', refresh);
  }

  static String? getAccessToken() =>
      Hive.box<String>(_tokenBox).get('accessToken');

  static String? getRefreshToken() =>
      Hive.box<String>(_tokenBox).get('refreshToken');

  static Future<void> clearTokens() async {
    final box = Hive.box<String>(_tokenBox);
    await box.delete('accessToken');
    await box.delete('refreshToken');
  }
}
