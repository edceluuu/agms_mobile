import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/plant_model.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../storage/hive_storage.dart';
import '../../utils/constants.dart';
import '../../utils/week_utils.dart';
import '../../services/api_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<PlantModel> _plants = [];
  bool _loading = true;
  bool _fabExpanded = false;

  static const _defaultCenter = LatLng(7.0731, 125.6128);
  static const _defaultZoom = 15.0;

  final int _currentWeek = WeekUtils.getCurrentWeekNumber();
  final int _currentYear = WeekUtils.getCurrentYear();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final position = await LocationService.getCurrentLocation();
    final plants = HiveStorage.getAllPlants();

    setState(() {
      _plants = plants;
      _loading = false;
    });

    // Wait for the map widget to render before moving
    if (position != null) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          _defaultZoom,
        );
      }
    }
  }

  Future<void> _showAddGridDialog() async {
    final nameCtrl = TextEditingController();
    bool loading = false;
    bool fetchingGrids = true;
    String? error;
    List<dynamic> existingGrids = [];

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Fetch grids when dialog opens
          if (fetchingGrids) {
            fetchingGrids = false;
            ApiService.get('/grids')
                .then((res) {
                  if (ctx.mounted) {
                    setDialogState(() => existingGrids = res.data);
                  }
                })
                .catchError((_) {});
          }

          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Row(
              children: [
                Icon(Icons.grid_on, color: AppColors.pinBlue, size: 22),
                SizedBox(width: 8),
                Text('Manage Grids', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Existing grids list
                  if (existingGrids.isNotEmpty) ...[
                    const Text(
                      'Existing Grids',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: existingGrids.length,
                        itemBuilder: (_, i) {
                          final grid = existingGrids[i];
                          final plantCount =
                              (grid['plants'] as List?)?.length ?? 0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.grid_on,
                                  color: AppColors.pinBlue,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    grid['name'],
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                Text(
                                  '$plantCount plants',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 12),
                  ],

                  // Add new grid
                  const Text(
                    'Add New Grid',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. Grid A',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(
                        color: AppColors.pinRed,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Close',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton(
                onPressed: loading
                    ? null
                    : () async {
                        if (nameCtrl.text.trim().isEmpty) {
                          setDialogState(() => error = 'Grid name is required');
                          return;
                        }
                        setDialogState(() {
                          loading = true;
                          error = null;
                        });
                        try {
                          final res = await ApiService.post(
                            '/grids',
                            data: {'name': nameCtrl.text.trim()},
                          );
                          final newGrid = res.data;
                          setDialogState(() {
                            existingGrids.add(newGrid);
                            loading = false;
                            nameCtrl.clear();
                          });
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.pinGreen,
                                content: Text(
                                  'Grid "${newGrid['name']}" created!',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            error = 'Failed to create grid. Try again.';
                            loading = false;
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.pinBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _getPinColor(PlantModel plant) {
    if (!plant.isActive) return AppColors.pinGray;
    if (HiveStorage.isAlreadyScannedThisWeek(
      plant.qrCode,
      _currentWeek,
      _currentYear,
    )) {
      return AppColors.pinBlue;
    }
    return AppColors.pinRed;
  }

  void _showPlantInfo(BuildContext context, PlantModel plant) {
    final color = _getPinColor(plant);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.eco, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  plant.qrCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow('Species', plant.species),
            if (plant.gridName != null) _infoRow('Grid', plant.gridName!),
            _infoRow('Status', plant.isActive ? 'Active' : 'Inactive'),
            _infoRow(
              'This Week',
              HiveStorage.isAlreadyScannedThisWeek(
                    plant.qrCode,
                    _currentWeek,
                    _currentYear,
                  )
                  ? 'Scanned ✓'
                  : 'Not yet scanned',
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final user = AuthService.getCurrentUser();
    final isAdmin = user?.role == 'ADMIN';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : Stack(
              children: [
                // Map
                FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: _defaultCenter,
                    initialZoom: _defaultZoom,
                  ),
                  children: [
                    // Tile layer
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.agms.mobile',
                    ),
                    // Plant markers
                    MarkerLayer(
                      markers: _plants
                          .where(
                            (p) => p.latitude != null && p.longitude != null,
                          )
                          .map((plant) {
                            final color = _getPinColor(plant);
                            return Marker(
                              point: LatLng(plant.latitude!, plant.longitude!),
                              width: 36,
                              height: 36,
                              child: GestureDetector(
                                onTap: () => _showPlantInfo(context, plant),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withOpacity(0.5),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.eco,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ],
                ),

                // Pin Legend
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _legendItem(AppColors.pinRed, 'Not scanned'),
                        _legendItem(AppColors.pinBlue, 'Scanned & synced'),
                        _legendItem(AppColors.pinGreen, 'Scanned locally'),
                        _legendItem(AppColors.pinYellow, 'Flagged'),
                        _legendItem(AppColors.pinGray, 'Inactive'),
                      ],
                    ),
                  ),
                ),

                // Week indicator
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Week $_currentWeek · $_currentYear',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),

                // Recenter button
                Positioned(
                  top: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'recenter',
                    backgroundColor: AppColors.surface,
                    onPressed: _init,
                    child: const Icon(
                      Icons.my_location,
                      color: AppColors.primary,
                    ),
                  ),
                ),

                // ADMIN FAB — Add Grid / Add Plant
                if (isAdmin)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (_fabExpanded) ...[
                          _fabOption(
                            label: 'Add Grid',
                            icon: Icons.grid_on,
                            color: AppColors.pinBlue,
                            onTap: () async {
                              setState(() => _fabExpanded = false);
                              await Future.delayed(
                                const Duration(milliseconds: 200),
                              );
                              if (mounted) _showAddGridDialog();
                            },
                          ),
                          const SizedBox(height: 8),
                          _fabOption(
                            label: 'Add Grid',
                            icon: Icons.grid_on,
                            color: AppColors.pinBlue,
                            onTap: () {
                              setState(() => _fabExpanded = false);
                              _showAddGridDialog();
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                        FloatingActionButton(
                          heroTag: 'main_fab',
                          backgroundColor: AppColors.primary,
                          onPressed: () =>
                              setState(() => _fabExpanded = !_fabExpanded),
                          child: Icon(
                            _fabExpanded ? Icons.close : Icons.add,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _legendItem(Color color, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _fabOption({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}
