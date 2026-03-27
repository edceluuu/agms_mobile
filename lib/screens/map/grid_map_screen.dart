import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
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
  PointAnnotationManager? _annotationManager;
  PointAnnotation? _userAnnotation;
  bool _locationPermissionGranted = false;
  bool _permissionChecked = false;
  Position? _userPosition;
  double _userHeading = 0.0;
  StreamSubscription<Object>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;

  // When true, camera follows the user automatically.
  bool _cameraFollowing = true;

  static const double _defaultLat = 7.377146991499139;
  static const double _defaultLng = 125.83816973129873;
  static const double _defaultZoom = 14.0;
  static const double _followZoom = 17.0;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      MapboxOptions.setAccessToken(AppConstants.mapboxAccessToken);
      _requestLocationPermission();
      // Compass stream starts independently of location permission
      _startCompassStream();
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _compassStream?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Compass — drives arrow rotation regardless of movement
  // ---------------------------------------------------------------------------

  void _startCompassStream() {
    _compassStream = FlutterCompass.events?.listen(
      (CompassEvent event) async {
        final heading = event.heading;
        if (heading == null) return;

        // 1-degree threshold to avoid excessive redraws
        if ((heading - _userHeading).abs() < 1.0) return;
        _userHeading = heading;

        if (_annotationManager != null && _userAnnotation != null) {
          await _updateArrowMarker();
        }
      },
      onError: (e) {
        debugPrint('⚠️ Compass not available: $e');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Location permission + position stream
  // ---------------------------------------------------------------------------

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

    if (granted) {
      await _fetchUserLocation();
      _startPositionStream();
    }

    setState(() {
      _locationPermissionGranted = granted;
      _permissionChecked = true;
    });
  }

  Future<void> _fetchUserLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _userPosition = Position(position.longitude, position.latitude);
      debugPrint('📍 Position: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('Could not get location: $e');
    }
  }

  void _startPositionStream() {
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 1,
          ),
        ).listen((position) async {
          // Only update lat/lng — heading comes from compass, not GPS
          _userPosition = Position(position.longitude, position.latitude);
          debugPrint(
            '📍 Position updated: ${position.latitude}, ${position.longitude}',
          );

          if (_annotationManager != null && _userAnnotation != null) {
            await _updateArrowMarker();
          }

          // Move camera to follow user if following mode is on
          if (_cameraFollowing && _mapboxMap != null) {
            await _moveCameraToUser(animated: true);
          }
        });
  }

  // ---------------------------------------------------------------------------
  // Map lifecycle
  // ---------------------------------------------------------------------------

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    debugPrint('🗺️ Map created');
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData data) async {
    debugPrint('🗺️ Style loaded!');

    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    // Compass to top-left
    await mapboxMap.compass.updateSettings(
      (CompassSettings()
        ..position = OrnamentPosition.TOP_LEFT
        ..enabled = true),
    );

    await _addGridPolygon(mapboxMap);
    await _addPolygonCenterMarker(mapboxMap);

    await mapboxMap.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(_defaultLng, _defaultLat)),
        zoom: _defaultZoom,
      ),
      MapAnimationOptions(duration: 800),
    );

    await _addArrowMarker(mapboxMap);

    // Fly to user if we already have a position
    if (_userPosition != null && _cameraFollowing) {
      await _moveCameraToUser(animated: true);
    }
  }

  Future<void> _moveCameraToUser({bool animated = true}) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || _userPosition == null) return;

    if (animated) {
      await mapboxMap.easeTo(
        CameraOptions(
          center: Point(coordinates: _userPosition!),
          zoom: _followZoom,
        ),
        MapAnimationOptions(duration: 300),
      );
    } else {
      await mapboxMap.setCamera(
        CameraOptions(
          center: Point(coordinates: _userPosition!),
          zoom: _followZoom,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Polygon
  // ---------------------------------------------------------------------------

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

      debugPrint('✅ Polygon + outline added');
    } catch (e) {
      debugPrint('❌ Error adding polygon: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Markers
  // ---------------------------------------------------------------------------

  Future<void> _addPolygonCenterMarker(MapboxMap mapboxMap) async {
    try {
      final manager = await mapboxMap.annotations
          .createPointAnnotationManager();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const size = 60.0;

      final paint = Paint()..color = Colors.green;

      canvas.drawCircle(const Offset(size / 2, size / 2 - 8), 18, paint);

      final path = Path()
        ..moveTo(size / 2 - 8, size / 2 + 6)
        ..lineTo(size / 2 + 8, size / 2 + 6)
        ..lineTo(size / 2, size / 2 + 24)
        ..close();
      canvas.drawPath(path, paint);

      canvas.drawCircle(
        const Offset(size / 2, size / 2 - 8),
        8,
        Paint()..color = Colors.white,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final bitmap = byteData!.buffer.asUint8List();

      await manager.create(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(_defaultLng, _defaultLat)),
          image: bitmap,
          iconSize: 1.0,
        ),
      );

      debugPrint('✅ Polygon center marker added');
    } catch (e) {
      debugPrint('❌ Error adding center marker: $e');
    }
  }

  /// Draws a blue triangle arrow rotated by [heading] degrees (0 = north).
  /// Heading comes exclusively from the compass, not GPS bearing.
  Future<Uint8List> _createArrowBitmap(double heading) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 80.0;
    const center = Offset(size / 2, size / 2);

    canvas.translate(center.dx, center.dy);
    canvas.rotate(heading * (pi / 180.0));
    canvas.translate(-center.dx, -center.dy);

    final arrowPaint = Paint()
      ..color = const Color(0xFF2196F3)
      ..style = PaintingStyle.fill;

    final arrowPath = Path()
      ..moveTo(size / 2, 4)
      ..lineTo(size / 2 + 18, size / 2 + 20)
      ..lineTo(size / 2, size / 2 + 8)
      ..lineTo(size / 2 - 18, size / 2 + 20)
      ..close();

    canvas.drawPath(arrowPath, arrowPaint);

    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    canvas.drawCircle(
      Offset(size / 2, size / 2 + 4),
      4,
      Paint()..color = Colors.white,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _addArrowMarker(MapboxMap mapboxMap) async {
    try {
      _annotationManager = await mapboxMap.annotations
          .createPointAnnotationManager();

      final bitmap = await _createArrowBitmap(_userHeading);
      final location = _userPosition ?? Position(_defaultLng, _defaultLat);

      _userAnnotation = await _annotationManager!.create(
        PointAnnotationOptions(
          geometry: Point(coordinates: location),
          image: bitmap,
          iconSize: 1.0,
        ),
      );

      debugPrint('✅ Arrow marker added');
    } catch (e) {
      debugPrint('❌ Error adding arrow marker: $e');
    }
  }

  Future<void> _updateArrowMarker() async {
    try {
      final bitmap = await _createArrowBitmap(_userHeading);
      final location = _userPosition ?? Position(_defaultLng, _defaultLat);

      _userAnnotation!.image = bitmap;
      _userAnnotation!.geometry = Point(coordinates: location);
      await _annotationManager!.update(_userAnnotation!);
      debugPrint('🔄 Arrow updated — heading: $_userHeading°, pos: $location');
    } catch (e) {
      debugPrint('❌ Error updating arrow: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Recenter button
  // ---------------------------------------------------------------------------

  Future<void> _recenter() async {
    if (kIsWeb || _mapboxMap == null) return;

    setState(() => _cameraFollowing = true);

    final target = _userPosition ?? Position(_defaultLng, _defaultLat);
    final zoom = _userPosition != null ? _followZoom : _defaultZoom;

    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: target),
        zoom: zoom,
      ),
      MapAnimationOptions(duration: 600),
    );
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
              top: 100,
              right: 16,
              child: FloatingActionButton.small(
                heroTag: 'grid_recenter',
                backgroundColor: _cameraFollowing
                    ? AppColors.primary
                    : AppColors.surface,
                onPressed: _recenter,
                child: Icon(
                  Icons.my_location,
                  color: _cameraFollowing ? Colors.white : AppColors.primary,
                ),
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
