import 'package:flutter/material.dart';
import 'week_utils.dart';

class PinColorUtils {
  static const gray = Color(0xFFA0AEC0);
  static const red = Color(0xFFE53E3E);
  static const green = Color(0xFF38A169);
  static const blue = Color(0xFF3182CE);
  static const yellow = Color(0xFFD69E2E);

  static Color pinColor(
    Map<String, dynamic> plant, {
    bool hasPendingReading = false,
  }) {
    // ⚫ Gray — inactive / decommissioned
    final isActive = plant['isActive'] as bool? ?? true;
    if (!isActive) return gray;

    final readings = plant['readings'] as List?;
    final hasServerReadingThisWeek = _hasReadingThisWeek(readings);

    // 🟢 Green — scanned this week (data submitted, pending sync to server)
    if (hasPendingReading) return green;

    // 🔴 Red — not yet scanned this week
    if (!hasServerReadingThisWeek) return red;

    // Reading exists on server this week — check if any of them are flagged
    final isFlagged = readings!.any((r) {
      final map = Map<String, dynamic>.from(r as Map);
      final recordedAt = DateTime.tryParse(map['recordedAt'] as String? ?? '');
      if (recordedAt == null) return false;
      final isThisWeek =
          WeekUtils.isoWeekNumber(recordedAt) == WeekUtils.currentWeek &&
          recordedAt.year == WeekUtils.currentYear;
      return isThisWeek && (map['isFlagged'] as bool? ?? false);
    });

    // 🟡 Yellow — scanned but data has issues / flagged
    if (isFlagged) return yellow;

    // 🔵 Blue — synced to server this week, no issues
    return blue;
  }

  static bool _hasReadingThisWeek(List? readings) {
    if (readings == null || readings.isEmpty) return false;
    // Check all readings — don't assume sort order from the server
    return readings.any((r) {
      final map = Map<String, dynamic>.from(r as Map);
      final recordedAt = DateTime.tryParse(map['recordedAt'] as String? ?? '');
      if (recordedAt == null) return false;
      return WeekUtils.isoWeekNumber(recordedAt) == WeekUtils.currentWeek &&
          recordedAt.year == WeekUtils.currentYear;
    });
  }
}
