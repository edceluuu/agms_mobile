import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../utils/week_utils.dart';

class PlantHistoryScreen extends StatefulWidget {
  const PlantHistoryScreen({super.key});

  @override
  State<PlantHistoryScreen> createState() => _PlantHistoryScreenState();
}

class _PlantHistoryScreenState extends State<PlantHistoryScreen> {
  List<Map<String, dynamic>> _plants = [];
  bool _loading = true;
  String? _error;

  // Week filter state
  // null means "All Weeks"
  int? _selectedWeek;
  int? _selectedYear;
  List<Map<String, dynamic>> _availableWeeks = []; // [{week, year, label}]

  @override
  void initState() {
    super.initState();
    _buildAvailableWeeks();
    _fetchPlants();
  }

  void _buildAvailableWeeks() {
    final now = DateTime.now();
    final currentWeek = WeekUtils.currentWeek;
    final currentYear = WeekUtils.currentYear;

    // Go back up to 52 weeks from now
    final weeks = <Map<String, dynamic>>[];
    for (int i = 0; i < 52; i++) {
      final date = now.subtract(Duration(days: i * 7));
      final w = WeekUtils.isoWeekNumber(date);
      final y = date.year;
      // Avoid duplicates (edge case near year boundary)
      if (weeks.any((e) => e['week'] == w && e['year'] == y)) continue;
      final isCurrent = w == currentWeek && y == currentYear;
      weeks.add({
        'week': w,
        'year': y,
        'label': isCurrent ? 'Week $w, $y (Current)' : 'Week $w, $y',
      });
    }

    setState(() {
      _availableWeeks = weeks;
    });
  }

  void _saveToCache(List<Map<String, dynamic>> plants) {
    final box = Hive.box('plant_history');
    box.put('plants', plants);
  }

  List<Map<String, dynamic>> _loadFromCache() {
    final box = Hive.box('plant_history');
    final raw = box.get('plants');
    if (raw == null) return [];
    return (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _fetchPlants() async {
    try {
      // Build query string if a specific week is selected
      String endpoint = '/plants';
      if (_selectedWeek != null && _selectedYear != null) {
        endpoint = '/plants?week=$_selectedWeek&year=$_selectedYear';
      }
      final response = await ApiService.get(endpoint);
      final List data = response.data;
      final plants = data.map((e) => Map<String, dynamic>.from(e)).toList();
      _saveToCache(plants);
      setState(() {
        _plants = plants;
        _loading = false;
      });
    } catch (e) {
      final cached = _loadFromCache();

      // Apply week filter locally when offline
      List<Map<String, dynamic>> filtered = cached;
      if (_selectedWeek != null && _selectedYear != null) {
        filtered = cached.where((plant) {
          final readings = (plant['readings'] as List?) ?? [];
          return readings.any((r) {
            final recordedAt = DateTime.tryParse(
              r['recordedAt'] as String? ?? '',
            );
            if (recordedAt == null) return false;
            return WeekUtils.isoWeekNumber(recordedAt) == _selectedWeek &&
                recordedAt.year == _selectedYear;
          });
        }).toList();

        // Also trim each plant's readings to only that week
        filtered = filtered.map((plant) {
          final readings = (plant['readings'] as List?) ?? [];
          final weekReadings = readings.where((r) {
            final recordedAt = DateTime.tryParse(
              r['recordedAt'] as String? ?? '',
            );
            if (recordedAt == null) return false;
            return WeekUtils.isoWeekNumber(recordedAt) == _selectedWeek &&
                recordedAt.year == _selectedYear;
          }).toList();
          return {...plant, 'readings': weekReadings};
        }).toList();
      }

      setState(() {
        _plants = filtered;
        _loading = false;
        _error = cached.isEmpty ? 'Failed to load history.' : null;
      });
    }
  }

  Future<void> _deactivatePlant(String plantId) async {
    // Get plant details before updating state
    final plant = _plants.firstWhere(
      (p) => p['id'] == plantId,
      orElse: () => {},
    );
    final gridName = plant['gridName'] as String?;
    final qrCode = plant['qrCode'] as String?;

    // Optimistic UI update
    setState(() {
      final idx = _plants.indexWhere((p) => p['id'] == plantId);
      if (idx != -1) _plants[idx]['isActive'] = false;
    });
    _saveToCache(_plants);

    // Also update plant_pins cache so the map shows gray immediately
    if (gridName != null && qrCode != null) {
      final pinsBox = Hive.box('plant_pins');
      final cacheKey = 'pins_$gridName';
      final rawPins = pinsBox.get(cacheKey, defaultValue: <dynamic>[]) as List;
      final updatedPins = rawPins.map((e) {
        final pin = Map<String, dynamic>.from(e as Map);
        if (pin['qrCode'] == qrCode) {
          return {...pin, 'isActive': false};
        }
        return pin;
      }).toList();
      await pinsBox.put(cacheKey, updatedPins);
    }

    try {
      await ApiService.patch('/plants/$plantId/deactivate', data: {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
            content: const Row(
              children: [
                Icon(Icons.block, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text(
                  'Plant deactivated.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      final box = Hive.box('pending_deactivations');
      final List pending = List.from(
        box.get('plants', defaultValue: <dynamic>[]) as List,
      );
      if (!pending.contains(plantId)) {
        pending.add(plantId);
        await box.put('plants', pending);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
            content: const Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Deactivated offline — will sync when back online.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _deletePlant(String plantId) async {
    // Grab qrCode and gridName before removing from _plants
    final plant = _plants.firstWhere(
      (p) => p['id'] == plantId,
      orElse: () => {},
    );
    final qrCode = plant['qrCode'] as String?;
    final gridName = plant['gridName'] as String?;

    // Optimistically remove from UI and update cache immediately
    setState(() {
      _plants.removeWhere((p) => p['id'] == plantId);
    });
    _saveToCache(_plants);

    // Clear all Hive traces of this plant immediately
    // so re-scanning the same QR code works cleanly
    if (qrCode != null) {
      // Remove from plant_pins cache
      final pinsBox = Hive.box('plant_pins');
      final cacheKey = 'pins_${gridName}';
      final rawPins = pinsBox.get(cacheKey, defaultValue: <dynamic>[]) as List;
      final updatedPins = rawPins
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((p) => p['qrCode'] != qrCode)
          .toList();
      await pinsBox.put(cacheKey, updatedPins);

      // Remove from pending_plants
      final pendingPlantsBox = Hive.box('pending_plants');
      final List pendingPlants = List.from(
        pendingPlantsBox.get('plants', defaultValue: <dynamic>[]) as List,
      );
      pendingPlants.removeWhere((p) => p['qrCode'] == qrCode);
      await pendingPlantsBox.put('plants', pendingPlants);

      // Remove from pending_readings
      final pendingReadingsBox = Hive.box('pending_readings');
      final List pendingReadings = List.from(
        pendingReadingsBox.get('readings', defaultValue: <dynamic>[]) as List,
      );
      pendingReadings.removeWhere((r) => r['qrCode'] == qrCode);
      await pendingReadingsBox.put('readings', pendingReadings);
    }

    try {
      await ApiService.delete('/plants/$plantId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.pinRed,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text(
                  'Plant deleted.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      // Offline — queue for later sync
      final box = Hive.box('pending_deletions');
      final List pending = List.from(
        box.get('plants', defaultValue: <dynamic>[]) as List,
      );
      if (!pending.contains(plantId)) {
        pending.add(plantId);
        await box.put('plants', pending);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
            content: const Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Deleted offline — will sync when back online.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _formatDate(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Plant History',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_availableWeeks.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.4)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isDense: true,
                  dropdownColor: AppColors.surface,
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  value: _selectedWeek == null
                      ? 'all'
                      : '${_selectedWeek}_${_selectedYear}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  items: [
                    // "All Weeks" option
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Weeks'),
                    ),
                    // One item per week
                    ..._availableWeeks.map((w) {
                      final key = '${w['week']}_${w['year']}';
                      return DropdownMenuItem(
                        value: key,
                        child: Text(w['label'] as String),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    if (val == 'all') {
                      setState(() {
                        _selectedWeek = null;
                        _selectedYear = null;
                        _loading = true;
                      });
                    } else {
                      final parts = val!.split('_');
                      setState(() {
                        _selectedWeek = int.parse(parts[0]);
                        _selectedYear = int.parse(parts[1]);
                        _loading = true;
                      });
                    }
                    _fetchPlants();
                  },
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          : _plants.isEmpty
          ? const Center(
              child: Text(
                'No plants recorded yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _plants.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final plant = _plants[index];
                final readings = (plant['readings'] as List?) ?? [];
                return _PlantCard(
                  plant: plant,
                  readings: readings
                      .map((r) => Map<String, dynamic>.from(r))
                      .toList(),
                  formatDate: _formatDate,
                  onDelete: () => _deletePlant(plant['id']),
                  onDeactivate: () => _deactivatePlant(plant['id']),
                );
              },
            ),
    );
  }
}

class _PlantCard extends StatefulWidget {
  final Map<String, dynamic> plant;
  final List<Map<String, dynamic>> readings;
  final String Function(String) formatDate;
  final VoidCallback onDelete;
  final VoidCallback onDeactivate;

  const _PlantCard({
    required this.plant,
    required this.readings,
    required this.formatDate,
    required this.onDelete,
    required this.onDeactivate,
  });

  @override
  State<_PlantCard> createState() => _PlantCardState();
}

class _PlantCardState extends State<_PlantCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final plant = widget.plant;
    final readings = widget.readings;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          // Plant header
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.qr_code_2,
                      color: AppColors.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      plant['qrCode'] ?? 'No QR Code',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.pinGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.pinGreen.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        '${readings.length} reading${readings.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.pinGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Deactivate Plant'),
                            content: const Text(
                              'Mark this plant as decommissioned? It will appear gray on the map.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  'Deactivate',
                                  style: TextStyle(color: Colors.orange),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) widget.onDeactivate();
                      },
                      child: const Icon(
                        Icons.block,
                        color: Colors.orange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Plant'),
                            content: const Text(
                              'Are you sure you want to delete this plant?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) widget.onDelete();
                      },
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.grid_on,
                      color: AppColors.textSecondary,
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${plant['gridName']}  ·  ${plant['areaName']}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.my_location,
                      color: AppColors.textSecondary,
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${(plant['latitude'] as num).toStringAsFixed(6)}, ${(plant['longitude'] as num).toStringAsFixed(6)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (readings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        Text(
                          _expanded ? 'Hide readings' : 'Show readings',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: AppColors.primary,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Readings list (expandable)
          if (_expanded && readings.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.primary.withOpacity(0.1)),
                ),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: readings.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final reading = readings[i];
                  final recordedBy = reading['user']?['name'] ?? 'Unknown';
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.08),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              widget.formatDate(reading['recordedAt']),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            // Show which week this reading belongs to
                            Builder(
                              builder: (_) {
                                final recordedAt = DateTime.tryParse(
                                  reading['recordedAt'] as String? ?? '',
                                );
                                if (recordedAt == null)
                                  return const SizedBox.shrink();
                                final week = WeekUtils.isoWeekNumber(
                                  recordedAt,
                                );
                                final year = recordedAt.year;
                                final isCurrent =
                                    week == WeekUtils.currentWeek &&
                                    year == WeekUtils.currentYear;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? AppColors.pinGreen.withOpacity(0.15)
                                        : AppColors.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isCurrent
                                          ? AppColors.pinGreen.withOpacity(0.4)
                                          : AppColors.primary.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Text(
                                    isCurrent
                                        ? 'Week $week · Current'
                                        : 'Week $week',
                                    style: TextStyle(
                                      color: isCurrent
                                          ? AppColors.pinGreen
                                          : AppColors.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _miniStat(
                                'Height',
                                () {
                                  final h = (reading['height'] as num)
                                      .toDouble();
                                  if (h < 1.0) {
                                    return '${(h * 100).toStringAsFixed(1)} cm';
                                  } else {
                                    return '${h.toStringAsFixed(2)} m';
                                  }
                                }(),
                                Icons.height,
                                AppColors.pinBlue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _miniStat(
                                'Girth',
                                '${(reading['girth'] as num).toStringAsFixed(2)} m',
                                Icons.circle_outlined,
                                AppColors.pinGreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.person_outline,
                              size: 12,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Recorded by $recordedBy',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
