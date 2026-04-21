import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'api_service.dart';

class SyncService {
  static Future<void> syncAll() async {
    final pendingReadings =
        Hive.box('pending_readings').get('readings', defaultValue: <dynamic>[])
            as List;
    final pendingPlants =
        Hive.box('pending_plants').get('plants', defaultValue: <dynamic>[])
            as List;
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
      var plantId = reading['plantId'];
      final qrCode = reading['qrCode'];

      // If plantId is null, try to resolve it from qrCode
      if (plantId == null && qrCode != null) {
        try {
          final response = await ApiService.get('/plants/$qrCode');
          plantId = response.data['id'];
        } catch (e) {
          failed.add(reading);
          continue;
        }
      }

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
        // Do NOT add to failed — reading posted successfully, remove from Hive
      } catch (e) {
        final errStr = e.toString();
        // If server says already recorded or conflict, treat as success
        // so we don't retry it forever
        if (errStr.contains('400') ||
            errStr.contains('409') ||
            errStr.contains('already')) {
          // already synced — removing from pending
        } else {
          // Genuine failure (network, 500, etc.) — retry next time
          failed.add(reading);
        }
      }
    }
    await box.put('readings', failed);
  }
}
