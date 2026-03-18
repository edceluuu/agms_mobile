import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_model.dart';
import '../models/plant_model.dart';

class HiveStorage {
  static const _authBox = 'auth';
  static const _tokenBox = 'tokens';
  static const _plantBox = 'plants';
  static const _scannedBox = 'scanned_this_week';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(UserModelAdapter());
    Hive.registerAdapter(PlantModelAdapter());
    await Hive.openBox<UserModel>(_authBox);
    await Hive.openBox<String>(_tokenBox);
    await Hive.openBox<PlantModel>(_plantBox);
    await Hive.openBox<String>(_scannedBox);
  }

  // User
  static Future<void> saveUser(UserModel user) async {
    final box = Hive.box<UserModel>(_authBox);
    await box.put('currentUser', user);
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

  // Plants
  static Future<void> savePlants(List<PlantModel> plants) async {
    final box = Hive.box<PlantModel>(_plantBox);
    await box.clear();
    final map = {for (var p in plants) p.qrCode: p};
    await box.putAll(map);
  }

  static PlantModel? getPlantByQR(String qrCode) {
    return Hive.box<PlantModel>(_plantBox).get(qrCode);
  }

  static List<PlantModel> getAllPlants() {
    return Hive.box<PlantModel>(_plantBox).values.toList();
  }

  static bool hasPlants() => Hive.box<PlantModel>(_plantBox).isNotEmpty;

  // Scanned this week
  static bool isAlreadyScannedThisWeek(String qrCode, int week, int year) {
    final key = '${qrCode}_${week}_$year';
    return Hive.box<String>(_scannedBox).containsKey(key);
  }

  static Future<void> markAsScannedThisWeek(
    String qrCode,
    int week,
    int year,
  ) async {
    final key = '${qrCode}_${week}_$year';
    await Hive.box<String>(
      _scannedBox,
    ).put(key, DateTime.now().toIso8601String());
  }
}
