import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';
import 'storage/hive_storage.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/map/grid_map_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/scanner/qr_scanner_screen.dart';
import 'screens/data_entry_screen.dart';
import 'screens/map/plant_history_screen.dart';

// Global notifier — flips whenever a sync completes so the map can redraw
final syncCompleteNotifier = ValueNotifier<bool>(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await HiveStorage.init();
  ApiService.init();
  debugPrint('🔵 BASE_URL: ${dotenv.env['BASE_URL']}');

  // Sync any pending offline data whenever connectivity is restored
  bool wasOffline = false;
  Connectivity().onConnectivityChanged.listen((result) {
    final isOnline = result != ConnectivityResult.none;
    if (isOnline && wasOffline) {
      SyncService.syncAll().then((_) {
        // Notify the map to redraw pins after sync completes
        syncCompleteNotifier.value = !syncCompleteNotifier.value;
      });
    }
    wasOffline = !isOnline;
  });

  runApp(const AGMSApp());
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/grid-map',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return GridMapScreen(
          gridName: extra['gridName'] as String,
          areaName: extra['areaName'] as String,
          plantCount: extra['plantCount'] as int,
        );
      },
    ),
    GoRoute(
      path: '/scan',
      builder: (context, state) => const QRScannerScreen(),
    ),
    GoRoute(
      path: '/data-entry',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return DataEntryScreen(
          qrCode: extra['qrCode'] as String,
          isOffline: (extra['isOffline'] as bool?) ?? false,
          plantId: extra['plantId'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/plant-history',
      builder: (context, state) => const PlantHistoryScreen(),
    ),
  ],
);

class AGMSApp extends StatelessWidget {
  const AGMSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AGMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A2A1A),
      ),
      routerConfig: _router,
    );
  }
}
