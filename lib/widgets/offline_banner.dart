import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../utils/constants.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectivityService.onlineStatus,
      builder: (context, snap) {
        final isOnline = snap.data ?? true;
        if (isOnline) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: Colors.redAccent, // Or Colors.red
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: const Text(
            '⚠ No internet connection — offline mode',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black87, fontSize: 13),
          ),
        );
      },
    );
  }
}
