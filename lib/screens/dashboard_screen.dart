import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import '../widgets/offline_banner.dart';
import 'map/map_screen.dart';
import 'scanner/qr_scanner_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    _screens = const [_DashboardBody(), QRScannerScreen(), MapScreen()];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(
          children: const [
            Icon(Icons.eco, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text(
              'AGMS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white54),
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
          Expanded(child: _screens[_currentIndex]),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner_outlined),
            activeIcon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Map',
          ),
        ],
      ),
    );
  }
}

// ── Dashboard Body ────────────────────────────────────────────────────────────

class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context) {
    final user = AuthService.getCurrentUser();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _greetingCard(user, context),
          const SizedBox(height: 20),
          _roleBasedContent(user),
        ],
      ),
    );
  }

  Widget _greetingCard(UserModel? user, BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome, ${user?.name ?? 'User'}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          _roleBadge(user?.role ?? ''),
          if (user?.role == 'ADMIN') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.go('/register-user'),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Register New User'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _roleBadge(String role) {
    final colors = {
      'ADMIN': AppColors.pinBlue,
      'SUPERVISOR': AppColors.pinYellow,
      'FIELD_MONITOR': AppColors.pinGreen,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (colors[role] ?? AppColors.pinGray).withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors[role] ?? AppColors.pinGray),
      ),
      child: Text(
        role.replaceAll('_', ' '),
        style: TextStyle(
          color: colors[role] ?? AppColors.pinGray,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _roleBasedContent(UserModel? user) {
    final role = user?.role ?? '';

    final items = {
      'ADMIN': [
        _statCard('Total Plants', '248', Icons.forest, AppColors.pinGreen),
        _statCard('Active Users', '12', Icons.people, AppColors.pinBlue),
        _statCard('Flagged Readings', '3', Icons.flag, AppColors.pinRed),
        _statCard(
          'Weekly Compliance',
          '87%',
          Icons.check_circle,
          AppColors.primary,
        ),
      ],
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
      'FIELD_MONITOR': [
        _statCard('My Plants Today', '24', Icons.eco, AppColors.pinGreen),
        _statCard('Scanned', '18', Icons.check, AppColors.primary),
        _statCard('Pending', '6', Icons.schedule, AppColors.pinYellow),
        _statCard('Flagged', '1', Icons.warning, AppColors.pinRed),
      ],
    };

    final cards = items[role] ?? items['FIELD_MONITOR']!;

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards,
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
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
