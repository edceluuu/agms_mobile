import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import '../../storage/hive_storage.dart';
import '../../utils/constants.dart';
import '../../utils/week_utils.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;
  bool _torchOn = false;
  String? _errorMessage;

  final int _currentWeek = WeekUtils.getCurrentWeekNumber();
  final int _currentYear = WeekUtils.getCurrentYear();

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final scannedCode = barcode!.rawValue!;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    await _controller.stop();

    final plant = HiveStorage.getPlantByQR(scannedCode);

    if (plant == null) {
      setState(() {
        _errorMessage =
            'QR code "$scannedCode" is not registered in the system.';
        _isProcessing = false;
      });
      return;
    }

    if (!plant.isActive) {
      setState(() {
        _errorMessage = 'This plant is inactive and cannot be scanned.';
        _isProcessing = false;
      });
      return;
    }

    if (HiveStorage.isAlreadyScannedThisWeek(
      scannedCode,
      _currentWeek,
      _currentYear,
    )) {
      setState(() {
        _errorMessage =
            'Plant "$scannedCode" has already been scanned this week (Week $_currentWeek).';
        _isProcessing = false;
      });
      return;
    }

    if (!mounted) return;
    context.push('/data-entry', extra: plant);
  }

  void _resetScanner() {
    setState(() {
      _errorMessage = null;
      _isProcessing = false;
    });
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scan Plant QR Code',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            Text(
              'Week $_currentWeek · $_currentYear',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: _torchOn ? AppColors.pinYellow : Colors.white54,
            ),
            onPressed: () {
              _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera view
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                // Scan overlay
                _buildScanOverlay(),
                // Processing indicator
                if (_isProcessing && _errorMessage == null)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppColors.primary),
                          SizedBox(height: 16),
                          Text(
                            'Validating QR code...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Bottom panel
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: AppColors.background,
              child: _errorMessage != null
                  ? _buildErrorPanel()
                  : _buildInstructionPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    return Center(
      child: Container(
        width: 250,
        height: 250,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            _corner(Alignment.topLeft),
            _corner(Alignment.topRight),
            _corner(Alignment.bottomLeft),
            _corner(Alignment.bottomRight),
          ],
        ),
      ),
    );
  }

  Widget _corner(Alignment alignment) {
    final isTop =
        alignment == Alignment.topLeft || alignment == Alignment.topRight;
    final isLeft =
        alignment == Alignment.topLeft || alignment == Alignment.bottomLeft;
    return Align(
      alignment: alignment,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          border: Border(
            top: isTop
                ? const BorderSide(color: AppColors.primary, width: 4)
                : BorderSide.none,
            bottom: !isTop
                ? const BorderSide(color: AppColors.primary, width: 4)
                : BorderSide.none,
            left: isLeft
                ? const BorderSide(color: AppColors.primary, width: 4)
                : BorderSide.none,
            right: !isLeft
                ? const BorderSide(color: AppColors.primary, width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionPanel() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.qr_code_scanner, color: AppColors.primary, size: 32),
        const SizedBox(height: 8),
        const Text(
          'Point camera at plant QR code',
          style: TextStyle(color: Colors.white, fontSize: 15),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Hold steady inside the frame',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildErrorPanel() {
    final isDuplicate = _errorMessage!.contains('already been scanned');
    final isInactive = _errorMessage!.contains('inactive');

    Color iconColor;
    IconData icon;

    if (isDuplicate) {
      iconColor = AppColors.pinYellow;
      icon = Icons.event_busy;
    } else if (isInactive) {
      iconColor = AppColors.pinGray;
      icon = Icons.block;
    } else {
      iconColor = AppColors.pinRed;
      icon = Icons.qr_code_2;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(color: iconColor, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _resetScanner,
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: const Text('Scan Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
