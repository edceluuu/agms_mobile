import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../utils/constants.dart';

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

  static const double _defaultLat = 7.0731;
  static const double _defaultLng = 125.6128;
  static const double _defaultZoom = 15.0;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      MapboxOptions.setAccessToken(AppConstants.mapboxAccessToken);
    }
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // Add GeoJSON source
    await mapboxMap.style.addSource(
      GeoJsonSource(id: 'grid-source', data: jsonEncode(_gridGeoJson)),
    );

    // Add fill layer
    await mapboxMap.style.addLayer(
      FillLayer(
        id: 'grid-fill',
        sourceId: 'grid-source',
        fillColor: Colors.green.withOpacity(0.3).value,
        fillOutlineColor: Colors.green.value,
      ),
    );
  }

  Future<void> _recenter() async {
    if (kIsWeb) return;
    await _mapboxMap?.flyTo(
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
          // Mapbox Map or web fallback
          kIsWeb
              ? Container(
                  color: AppColors.background,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.map_outlined,
                          color: Colors.white24,
                          size: 64,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Map is only available on mobile.',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.plantCount} plant(s) in ${widget.gridName}',
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : MapWidget(
                  key: const ValueKey('grid_map'),
                  styleUri: MapboxStyles.SATELLITE_STREETS,
                  cameraOptions: CameraOptions(
                    center: Point(
                      coordinates: Position(_defaultLng, _defaultLat),
                    ),
                    zoom: _defaultZoom,
                  ),
                  onMapCreated: _onMapCreated,
                ),

          // Recenter button
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

          // Grid info bar at bottom
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
              child: Row(
                children: [
                  _infoChip(Icons.grid_on, widget.gridName, AppColors.pinBlue),
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
            ),
          ),
        ],
      ),
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
