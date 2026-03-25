import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    hide LocationSettings;
import 'package:geolocator/geolocator.dart' hide Position;
import '../../utils/constants.dart';
import 'package:go_router/go_router.dart';

class GridMapScreen extends StatefulWidget {
  final String gridName;
  final String areaName;
  final int plantCount;

  const GridMapScreen({
    super.key,
    required this.gridName,
    required this.areaName,
    required this.plantCount,
  });

  @override
  State<GridMapScreen> createState() => _GridMapScreenState();
}

final _gridGeoJson = {
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {},
      "geometry": {
        "coordinates": [
          [
            [125.83254553754443, 7.381025986055903],
            [125.83254553754443, 7.373267996942374],
            [125.84379392505303, 7.373267996942374],
            [125.84379392505303, 7.381025986055903],
            [125.83254553754443, 7.381025986055903],
          ],
        ],
        "type": "Polygon",
      },
    },
  ],
};

class _GridMapScreenState extends State<GridMapScreen> {
  MapboxMap? _mapboxMap;
  bool _locationPermissionGranted = false;
  bool _permissionChecked = false;

  static const double _defaultLat = 7.377146991499139;
  static const double _defaultLng = 125.83816973129873;
  static const double _defaultZoom = 14.0;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      MapboxOptions.setAccessToken(AppConstants.mapboxAccessToken);
      _requestLocationPermission();
    }
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationPermissionGranted = false;
        _permissionChecked = true;
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final granted =
        permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;

    setState(() {
      _locationPermissionGranted = granted;
      _permissionChecked = true;
    });
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    debugPrint('🗺️ Map created');
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData data) async {
    debugPrint('🗺️ Style loaded fired!');

    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) {
      debugPrint('❌ _mapboxMap is null in _onStyleLoaded');
      return;
    }

    await _addGridPolygon(mapboxMap);

    await mapboxMap.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(_defaultLng, _defaultLat)),
        zoom: _defaultZoom,
      ),
      MapAnimationOptions(duration: 800),
    );
  }

  Future<void> _addGridPolygon(MapboxMap mapboxMap) async {
    try {
      try {
        await mapboxMap.style.removeStyleLayer('grid-outline');
        await mapboxMap.style.removeStyleLayer('grid-fill');
        await mapboxMap.style.removeStyleSource('grid-source');
      } catch (_) {}

      await mapboxMap.style.addSource(
        GeoJsonSource(id: 'grid-source', data: jsonEncode(_gridGeoJson)),
      );

      debugPrint('🟩 Source added, now adding layers...');

      await mapboxMap.style.addLayerAt(
        FillLayer(
          id: 'grid-fill',
          sourceId: 'grid-source',
          fillColor: Colors.green.value,
          fillOpacity: 0.3,
        ),
        LayerPosition(at: 0),
      );

      await mapboxMap.style.addLayerAt(
        LineLayer(
          id: 'grid-outline',
          sourceId: 'grid-source',
          lineColor: Colors.green.value,
          lineWidth: 3.0,
        ),
        LayerPosition(at: 0),
      );

      debugPrint('✅ Polygon + outline added successfully');
    } catch (e) {
      debugPrint('❌ Error adding polygon: $e');
    }
  }

  Future<void> _recenter() async {
    if (kIsWeb || _mapboxMap == null) return;

    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(_defaultLng, _defaultLat)),
        zoom: _defaultZoom,
      ),
      MapAnimationOptions(duration: 600),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.gridName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.areaName,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.pinGreen.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.pinGreen.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.eco, color: AppColors.pinGreen, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${widget.plantCount} plants',
                  style: const TextStyle(
                    color: AppColors.pinGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (kIsWeb)
            _buildWebFallback()
          else if (!_permissionChecked)
            const Center(child: CircularProgressIndicator())
          else if (!_locationPermissionGranted)
            _buildPermissionDeniedBanner()
          else
            _buildMap(),

          if (_permissionChecked)
            Positioned(
              top: 16,
              right: 16,
              child: FloatingActionButton.small(
                heroTag: 'grid_recenter',
                backgroundColor: AppColors.surface,
                onPressed: _recenter,
                child: const Icon(Icons.my_location, color: AppColors.primary),
              ),
            ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.95),
                border: Border(
                  top: BorderSide(color: AppColors.primary.withOpacity(0.2)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _infoChip(
                        Icons.grid_on,
                        widget.gridName,
                        AppColors.pinBlue,
                      ),
                      const SizedBox(width: 10),
                      _infoChip(
                        Icons.location_on,
                        widget.areaName,
                        AppColors.pinYellow,
                      ),
                      const SizedBox(width: 10),
                      _infoChip(
                        Icons.eco,
                        '${widget.plantCount} plants',
                        AppColors.pinGreen,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/scan'),
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      label: const Text(
                        'Scan QR Code',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return MapWidget(
      key: const ValueKey('grid_map'),
      styleUri: 'mapbox://styles/edceluuu/cmn5m39m8001v01s39gfy8brp',
      cameraOptions: CameraOptions(
        center: Point(coordinates: Position(_defaultLng, _defaultLat)),
        zoom: _defaultZoom,
      ),
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: _onStyleLoaded,
    );
  }

  Widget _buildWebFallback() {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, color: Colors.white24, size: 64),
            const SizedBox(height: 12),
            const Text(
              'Map is only available on mobile.',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.plantCount} plant(s) in ${widget.gridName}',
              style: const TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedBanner() {
    return Stack(
      children: [
        _buildMap(),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.orange.withOpacity(0.9),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.location_off, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Location permission denied. Your position won\'t be shown.',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => Geolocator.openAppSettings(),
                  child: const Text(
                    'Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
