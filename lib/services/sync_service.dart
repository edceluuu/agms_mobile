import 'package:hive_flutter/hive_flutter.dart';
import 'api_service.dart';

class SyncService {
  static Future<void> syncAll() async {
    await _syncPendingDeletions();
    await _syncPendingPlants();
    await _syncPendingReadings();
  }

  static Future<void> _syncPendingDeletions() async {
    final box = Hive.box('pending_deletions');
    final List pending = List.from(
      box.get('plants', defaultValue: <dynamic>[]) as List,
    );
    if (pending.isEmpty) return;

    final List failed = [];
    for (final plantId in pending) {
      try {
        await ApiService.delete('/plants/$plantId');
      } catch (_) {
        failed.add(plantId); // keep for next attempt
      }
    }
    await box.put('plants', failed);
  }

  static Future<void> _syncPendingPlants() async {
    final box = Hive.box('pending_plants');
    final List pending = List.from(
      box.get('plants', defaultValue: <dynamic>[]) as List,
    );
    if (pending.isEmpty) return;

    final List failed = [];
    for (final plant in pending) {
      try {
        await ApiService.post(
          '/plants',
          data: {
            'qrCode': plant['qrCode'],
            'latitude': plant['latitude'],
            'longitude': plant['longitude'],
            'gridName': plant['gridName'],
            'areaName': plant['areaName'],
          },
        );
      } catch (_) {
        failed.add(plant);
      }
    }
    await box.put('plants', failed);
  }

  static Future<void> _syncPendingReadings() async {
    final box = Hive.box('pending_readings');
    final List pending = List.from(
      box.get('readings', defaultValue: <dynamic>[]) as List,
    );
    if (pending.isEmpty) return;

    final List failed = [];
    for (final reading in pending) {
      try {
        await ApiService.post(
          '/plants/readings',
          data: {
            'plantId': reading['plantId'],
            'height': reading['height'],
            'girth': reading['girth'],
          },
        );
      } catch (_) {
        failed.add(reading);
      }
    }
    await box.put('readings', failed);
  }
}
