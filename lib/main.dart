import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'services/api_service.dart';
import 'storage/hive_storage.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/map/grid_map_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/scanner/qr_scanner_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await HiveStorage.init();
  ApiService.init();
  debugPrint('🔵 BASE_URL: ${dotenv.env['BASE_URL']}');
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
    // ✅ ADD THIS
    GoRoute(
      path: '/scan',
      builder: (context, state) => const QRScannerScreen(),
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
