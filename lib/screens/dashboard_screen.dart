import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import '../widgets/offline_banner.dart';
import '../services/sync_service.dart';

// Static grid data
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
    SyncService.syncAll(); // fire-and-forget
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
        _statCard('Pending Scans', '32', Icons.pending, AppColors.pinYellow),
        _statCard('Flagged', '2', Icons.flag, AppColors.pinRed),
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
      onTap: () => context.push(
        '/grid-map',
        extra: {
          'gridName': grid['name'] as String,
          'areaName': grid['area'] as String,
          'plantCount': grid['plantCount'] as int,
        },
      ),
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

                  // ── NEW: Plant count + Complete Reading badge ──
                  Row(
                    children: [
                      Text(
                        '${grid['plantCount']}/${grid['plantCount']}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Complete Reading',
                        style: const TextStyle(
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
                    ],
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
