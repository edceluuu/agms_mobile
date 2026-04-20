import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static const String baseUrl = 'http://10.244.98.53:3000/api';
  //static String get baseUrl =>
  //dotenv.env['BASE_URL'] ?? 'http://10.0.2.2:3000/api';
  //static const String baseUrl = 'http://localhost:3000/api';
  static String get mapboxAccessToken => dotenv.env['MAPBOX_TOKEN'] ?? '';
}

class AppColors {
  static const Color background = Color(0xFFFFFFFF); // white
  static const Color surface = Color(0xFFF5F5F5); // light grey surface
  static const Color primary = Color(0xFF4CAF50); // green (kept)
  static const Color accent = Color(0xFF81C784); // light green (kept)
  static const Color textPrimary = Color(
    0xFF1A1A1A,
  ); // was light green, now near-black
  static const Color textSecondary = Color(
    0xFF757575,
  ); // slightly darker for readability

  static const Color pinRed = Color(0xFFE53E3E);
  static const Color pinGreen = Color(0xFF38A169);
  static const Color pinBlue = Color(0xFF3182CE);
  static const Color pinYellow = Color(0xFFD69E2E);
  static const Color pinGray = Color(0xFFA0AEC0);
}
