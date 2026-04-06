//frontend/lib/screens/data_entry_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../utils/constants.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_service.dart';

class DataEntryScreen extends StatefulWidget {
  final String qrCode;

  const DataEntryScreen({super.key, required this.qrCode});

  @override
  State<DataEntryScreen> createState() => _DataEntryScreenState();
}

class _DataEntryScreenState extends State<DataEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _heightController = TextEditingController();
  final _girthController = TextEditingController();

  // true = CM, false = M
  bool _heightInCm = true;
  bool _isSubmitting = false;
  double? _latitude;
  double? _longitude;
  String _timestamp = '';
  String? _plantId;
  bool _isLoadingPlant = true;
  @override
  void initState() {
    super.initState();
    _loadLocationAndTime();
    _fetchPlant();
  }

  Future<void> _fetchPlant() async {
    debugPrint('🌿 Fetching plant for QR: ${widget.qrCode}');
    try {
      final response = await ApiService.get('/plants/${widget.qrCode}');
      debugPrint('🌿 Plant found: ${response.data}');
      if (mounted) {
        setState(() {
          _plantId = response.data['id'];
          _isLoadingPlant = false;
        });
      }
    } catch (e) {
      debugPrint('🌿 Error fetching plant: $e');
      if (mounted) {
        setState(() {
          _isLoadingPlant = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _heightController.dispose();
    _girthController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLocationAndTime() async {
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    setState(() => _timestamp = timestamp);

    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _latitude = position!.latitude;
          _longitude = position.longitude;
        });
      }
    } catch (e) {
      debugPrint('❌ Location error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  double get _heightInMeters {
    final val = double.tryParse(_heightController.text) ?? 0;
    return _heightInCm ? val / 100 : val;
  }

  double get _girthInMeters => double.tryParse(_girthController.text) ?? 0;

  String get _heightUnit => _heightInCm ? 'CM' : 'M';

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_plantId == null) {
      if (_latitude == null || _longitude == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still fetching your location. Please wait.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      try {
        final createRes = await ApiService.post(
          '/plants',
          data: {
            'qrCode': widget.qrCode,
            'latitude': _latitude,
            'longitude': _longitude,
          },
        );
        _plantId = createRes.data['id'];
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create plant: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      await ApiService.post(
        '/plants/readings',
        data: {
          'plantId': _plantId,
          'height': _heightInMeters,
          'girth': _girthInMeters,
        },
      );

      if (_latitude != null && _longitude != null) {
        await ApiService.patch(
          '/plants/$_plantId/location',
          data: {'latitude': _latitude, 'longitude': _longitude},
        );
      }

      setState(() => _isSubmitting = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.pinGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Reading saved!',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${widget.qrCode} · H: ${_heightInMeters.toStringAsFixed(2)}m · G: ${_girthInMeters.toStringAsFixed(2)}m',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );

      if (mounted)
        context.pop({
          'plantId': _plantId,
          'qrCode': widget.qrCode,
          'latitude': _latitude,
          'longitude': _longitude,
        });
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Data Entry',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 2. QR BADGE ────────────────────────────────────────────
                _QrBadge(
                  qrCode: widget.qrCode,
                  latitude: _latitude,
                  longitude: _longitude,
                  timestamp: _timestamp.isEmpty ? 'Loading...' : _timestamp,
                ),

                const SizedBox(height: 28),

                // ── 3. HEIGHT ──────────────────────────────────────────────
                _SectionLabel(label: 'Height', unit: _heightUnit),
                const SizedBox(height: 8),
                _HeightField(
                  controller: _heightController,
                  inCm: _heightInCm,
                  onUnitToggle: (val) => setState(() => _heightInCm = val),
                ),

                const SizedBox(height: 24),

                // ── 4. GIRTH ───────────────────────────────────────────────
                const _SectionLabel(label: 'Girth', unit: 'M'),
                const SizedBox(height: 8),
                _GirthField(controller: _girthController),

                const SizedBox(height: 40),

                // ── 5. ADD BUTTON ──────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_circle_outline, size: 20),
                    label: Text(
                      _isSubmitting ? 'Saving...' : 'Add',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.primary.withOpacity(
                        0.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── 6. CANCEL ──────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _QrBadge extends StatelessWidget {
  final String qrCode;
  final double? latitude;
  final double? longitude;
  final String timestamp;

  const _QrBadge({
    required this.qrCode,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.qr_code_2,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Plant ID',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  qrCode.length > 6 ? qrCode.substring(0, 6) : qrCode,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lat: ${latitude != null ? latitude!.toStringAsFixed(6) : 'Fetching...'}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Lng: ${longitude != null ? longitude!.toStringAsFixed(6) : 'Fetching...'}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Time: $timestamp',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final String unit;
  const _SectionLabel({required this.label, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            unit,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeightField extends StatelessWidget {
  final TextEditingController controller;
  final bool inCm;
  final ValueChanged<bool> onUnitToggle;

  const _HeightField({
    required this.controller,
    required this.inCm,
    required this.onUnitToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _inputDecoration(
              hint: inCm ? 'e.g. 150' : 'e.g. 1.50',
              suffix: inCm ? 'cm' : 'm',
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Required';
              final n = double.tryParse(val);
              if (n == null || n <= 0) return 'Enter a valid number';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              _UnitButton(
                label: 'CM',
                selected: inCm,
                onTap: () => onUnitToggle(true),
              ),
              _UnitButton(
                label: 'M',
                selected: !inCm,
                onTap: () => onUnitToggle(false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GirthField extends StatelessWidget {
  final TextEditingController controller;
  const _GirthField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: _inputDecoration(hint: 'e.g. 0.25', suffix: 'm'),
      validator: (val) {
        if (val == null || val.trim().isEmpty) return 'Required';
        final n = double.tryParse(val);
        if (n == null || n <= 0) return 'Enter a valid number';
        return null;
      },
    );
  }
}

class _UnitButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _UnitButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration({required String hint, String? suffix}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textSecondary),
    suffixText: suffix,
    suffixStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.primary.withOpacity(0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.primary.withOpacity(0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.red),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.red, width: 1.5),
    ),
  );
}
