import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static Stream<bool> get onlineStatus => Connectivity().onConnectivityChanged
      .map((result) => result != ConnectivityResult.none);

  static Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }
}
