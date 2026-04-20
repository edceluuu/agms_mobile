import 'package:hive_flutter/hive_flutter.dart';
import 'api_service.dart';

class SyncService {
  static Future<void> syncAll() async {
    await _syncPendingDeletions();
    await _syncPendingPlants();
    await _syncPendingReadings();
  }

  static Future<void> _syncPendingDeactivations() async {
    final box = Hive.box('pending_deactivations');
    final List pending = List.from(
      box.get('plants', defaultValue: <dynamic>[]) as List,
    );
    if (pending.isEmpty) return;

    final List failed = [];
    for (final plantId in pending) {
      try {
        await ApiService.patch('/plants/$plantId/deactivate', data: {});
      } catch (_) {
        failed.add(plantId);
      }
    }
    await box.put('plants', failed);
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
        failed.add(plantId);
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
        final response = await ApiService.post(
          '/plants',
          data: {
            'qrCode': plant['qrCode'],
            'latitude': plant['latitude'],
            'longitude': plant['longitude'],
            'gridName': plant['gridName'],
            'areaName': plant['areaName'],
          },
        );

        // Patch any pending readings that were saved with plantId: null
        // because the plant didn't exist on the server yet when recorded offline
        final realPlantId = response.data['id'] as String?;
        final qrCode = plant['qrCode'] as String?;
        if (realPlantId != null && qrCode != null) {
          await _patchReadingPlantId(qrCode, realPlantId);
        }
      } catch (_) {
        failed.add(plant);
      }
    }
    await box.put('plants', failed);
  }

  /// After a pending plant is successfully synced, update any pending readings
  /// that share the same qrCode and have a null plantId with the real server ID.
  static Future<void> _patchReadingPlantId(
    String qrCode,
    String realPlantId,
  ) async {
    final box = Hive.box('pending_readings');
    final List readings = List.from(
      box.get('readings', defaultValue: <dynamic>[]) as List,
    );

    bool changed = false;
    final patched = readings.map((r) {
      final map = Map<String, dynamic>.from(r as Map);
      if (map['qrCode'] == qrCode && map['plantId'] == null) {
        changed = true;
        return {...map, 'plantId': realPlantId};
      }
      return map;
    }).toList();

    if (changed) {
      await box.put('readings', patched);
    }
  }

  static Future<void> _syncPendingReadings() async {
    final box = Hive.box('pending_readings');
    final List pending = List.from(
      box.get('readings', defaultValue: <dynamic>[]) as List,
    );
    if (pending.isEmpty) return;

    final List failed = [];
    for (final reading in pending) {
      final plantId = reading['plantId'];

      // Skip readings that still have no plantId — their parent plant
      // failed to sync this cycle and will be retried next time
      if (plantId == null) {
        failed.add(reading);
        continue;
      }

      try {
        await ApiService.post(
          '/plants/readings',
          data: {
            'plantId': plantId,
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
