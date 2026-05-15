import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import '../widgets/offline_banner.dart';
import '../services/sync_service.dart';
import '../utils/week_utils.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Static grid data — scannedCount is computed dynamically from plant_pins cache
const _staticGrids = [
  {'name': 'Grid A', 'area': 'Area 1', 'plantCount': 12},
];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.getCurrentUser();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Row(
          children: const [
            Icon(Icons.eco, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text(
              'AGMS',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.textSecondary),
            onPressed: () async {
              await AuthService.logout();
              context.go('/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _greetingCard(user),
                  const SizedBox(height: 20),
                  _roleBasedContent(user),
                  const SizedBox(height: 24),
                  _gridListSection(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _getScannedCount(String gridName) {
    final box = Hive.box('plant_pins');
    final raw = box.get('pins_$gridName');
    if (raw == null) return 0;
    final plants = (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final currentWeek = WeekUtils.currentWeek;
    final currentYear = WeekUtils.currentYear;
    return plants.where((plant) {
      final readings = (plant['readings'] as List?) ?? [];
      return readings.any((r) {
        final map = Map<String, dynamic>.from(r as Map);
        final weekNumber = map['weekNumber'] as int?;
        final year = map['year'] as int?;
        if (weekNumber != null && year != null) {
          return weekNumber == currentWeek && year == currentYear;
        }
        final recordedAt = DateTime.tryParse(
          map['recordedAt'] as String? ?? '',
        );
        if (recordedAt == null) return false;
        return WeekUtils.isoWeekNumber(recordedAt) == currentWeek &&
            recordedAt.year == currentYear;
      });
    }).length;
  }

  Widget _greetingCard(UserModel? user) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, ${user?.name ?? 'User'} 👋',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roleBasedContent(UserModel? user) {
    final role = user?.role ?? '';

    final items = <String, List<Widget>>{
      'SUPERVISOR': [
        _statCard('Grids Assigned', '4', Icons.grid_on, AppColors.pinBlue),
        _statCard(
          'Scanned This Week',
          '140',
          Icons.qr_code_scanner,
          AppColors.pinGreen,
        ),
        _statCard(
          'Pending Scans',
          '32',
          Icons.pending,
          const Color(0xFFD69E2E),
        ),
        _statCard('Flagged', '2', Icons.flag, Colors.red),
      ],
      'FIELD_USER': [],
    };

    final cards = items[role] ?? items['FIELD_USER']!;

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards,
    );
  }

  Widget _gridListSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            const Icon(Icons.grid_on, color: AppColors.pinBlue, size: 18),
            const SizedBox(width: 8),
            const Text(
              'My Grids',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.pinBlue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_staticGrids.length} grids',
                style: const TextStyle(
                  color: AppColors.pinBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Grid items
        Column(
          children: _staticGrids
              .map((grid) => _gridItem(grid, context))
              .toList(),
        ),
      ],
    );
  }

  Widget _gridItem(Map<String, dynamic> grid, BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await context.push(
          '/grid-map',
          extra: {
            'gridName': grid['name'] as String,
            'areaName': grid['area'] as String,
            'plantCount': grid['plantCount'] as int,
          },
        );
        if (mounted) setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.pinBlue.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            // Grid icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.pinBlue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.grid_on,
                color: AppColors.pinBlue,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),

            // Grid info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    grid['name'] as String,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: AppColors.textSecondary,
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        grid['area'] as String,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // ── Plant count + dynamic reading badge ──
                  Builder(
                    builder: (context) {
                      final total = grid['plantCount'] as int;
                      final scanned = _getScannedCount(grid['name'] as String);
                      final missing = total - scanned;
                      final isComplete = missing == 0;

                      return Row(
                        children: [
                          Text(
                            '$scanned/$total',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isComplete) ...[
                            const Text(
                              'Complete Reading',
                              style: TextStyle(
                                color: AppColors.pinGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: AppColors.pinGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 12,
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.pinRed.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.pinRed.withOpacity(0.4),
                                ),
                              ),
                              child: Text(
                                '$missing sample${missing > 1 ? 's' : ''} no reading',
                                style: const TextStyle(
                                  color: AppColors.pinRed,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // Arrow indicator
            const Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
