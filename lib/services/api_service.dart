//frontend/lib/services/api_service.dart
import 'package:dio/dio.dart';
import 'package:agms_mobile/utils/constants.dart';
import '../storage/hive_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

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

  static Future<void> syncPendingReadings() async {
    await _syncPendingPlants();
    await _syncReadingsOnly();
  }

  static Future<void> _syncPendingPlants() async {
    final plantsBox = Hive.box('pending_plants');
    final readingsBox = Hive.box('pending_readings');

    final List pendingPlants = List.from(
      plantsBox.get('plants', defaultValue: <dynamic>[]) as List,
    );
    if (pendingPlants.isEmpty) return;

    final List failedPlants = [];

    for (final plant in pendingPlants) {
      try {
        final res = await ApiService.post(
          '/plants',
          data: {
            'qrCode': plant['qrCode'],
            'latitude': plant['latitude'],
            'longitude': plant['longitude'],
            'gridName': plant['gridName'],
            'areaName': plant['areaName'],
          },
        );

        final serverId = res.data['id'] as String;
        final qrCode = plant['qrCode'] as String;

        // Patch any pending readings that were waiting for this plantId
        final List allReadings = List.from(
          readingsBox.get('readings', defaultValue: <dynamic>[]) as List,
        );
        for (final reading in allReadings) {
          if (reading['qrCode'] == qrCode && reading['plantId'] == null) {
            reading['plantId'] = serverId;
          }
        }
        await readingsBox.put('readings', allReadings);

        debugPrint('✅ Synced pending plant: $qrCode → $serverId');
      } catch (_) {
        failedPlants.add(plant);
      }
    }

    await plantsBox.put('plants', failedPlants);
  }

  static Future<void> _syncReadingsOnly() async {
    final pendingBox = Hive.box('pending_readings');
    final List pending = List.from(
      pendingBox.get('readings', defaultValue: <dynamic>[]) as List,
    );
    if (pending.isEmpty) return;

    final List failed = [];
    for (final reading in pending) {
      if (reading['plantId'] == null) {
        failed.add(reading); // plant still pending, skip for now
        continue;
      }
      try {
        await ApiService.post(
          '/plants/readings',
          data: {
            'plantId': reading['plantId'],
            'height': reading['height'],
            'girth': reading['girth'],
          },
        );
        debugPrint('✅ Synced reading for plantId: ${reading['plantId']}');
      } catch (_) {
        failed.add(reading);
      }
    }

    await pendingBox.put('readings', failed);
    debugPrint(
      '✅ Readings sync: ${pending.length - failed.length} uploaded, ${failed.length} still pending',
    );
  }

  static Future<Response> get(String path) => _dio.get(path);
  static Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);
  static Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);
  static Future<Response> patch(String path, {dynamic data}) =>
      _dio.patch(path, data: data);
  static Future<Response> delete(String path) async {
    return await _dio.delete(path);
  }
}
