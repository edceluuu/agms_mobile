import 'package:dio/dio.dart';
import 'package:agms_mobile/utils/constants.dart';
import '../storage/hive_storage.dart';

class ApiService {
  static Dio? _dioInstance;

  static Dio get _dio {
    _dioInstance ??= Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
      ),
    );
    return _dioInstance!;
  }

  static void init() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = HiveStorage.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            final refreshed = await _tryRefresh();
            if (refreshed) {
              final token = HiveStorage.getAccessToken();
              error.requestOptions.headers['Authorization'] = 'Bearer $token';
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  static Future<bool> _tryRefresh() async {
    try {
      final refresh = HiveStorage.getRefreshToken();
      if (refresh == null) return false;
      final res = await Dio().post(
        '${AppConstants.baseUrl}/auth/refresh',
        data: {'refreshToken': refresh},
      );
      await HiveStorage.saveTokens(
        res.data['accessToken'],
        res.data['refreshToken'],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Response> get(String path) => _dio.get(path);
  static Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);
  static Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);
}
