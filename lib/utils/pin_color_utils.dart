import 'package:flutter/material.dart';
import 'week_utils.dart';

class PinColorUtils {
  static const gray = Color(0xFFA0AEC0);
  static const green = Color(0xFF38A169);
  static const blue = Color(0xFF3182CE);

  static Color pinColor(
    Map<String, dynamic> plant, {
    bool hasPendingReading = false,
  }) {
    if (hasPendingReading) return blue;

    final readings = plant['readings'] as List?;
    if (_hasReadingThisWeek(readings)) return green;

    return gray;
  }

  static bool _hasReadingThisWeek(List? readings) {
    if (readings == null || readings.isEmpty) return false;
    return readings.any((r) {
      final map = Map<String, dynamic>.from(r as Map);
      final recordedAt = DateTime.tryParse(map['recordedAt'] as String? ?? '');
      if (recordedAt == null) return false;
      return WeekUtils.isoWeekNumber(recordedAt) == WeekUtils.currentWeek &&
          recordedAt.year == WeekUtils.currentYear;
    });
  }
}
