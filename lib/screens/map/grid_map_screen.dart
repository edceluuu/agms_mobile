//frontend/lib/screens/map/grid_map_screen.dart
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    hide LocationSettings;
import 'package:geolocator/geolocator.dart' hide Position;
import '../../utils/constants.dart';
import '../../utils/geofence_utils.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

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

  bool _cameraFollowing = true;

  List<Map<String, dynamic>> _plants = [];
  PointAnnotationManager? _plantAnnotationManager;

  // maps annotation id → plant data for tap detection
  final Map<String, Map<String, dynamic>> _annotationPlantMap = {};
  // maps plant id → annotation object for position updates
  final Map<String, PointAnnotation> _plantAnnotationObjects = {};

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
      _startCompassStream();
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _compassStream?.cancel();
    super.dispose();
  }

  void _startCompassStream() {
    if (FlutterCompass.events == null) {
      debugPrint('⚠️ FlutterCompass.events is null — compass not supported');
      return;
    }
    _compassStream = FlutterCompass.events!.listen(
      (CompassEvent event) async {
        final heading = event.heading;
        if (heading == null) return;
        if ((heading - _userHeading).abs() < 1.0) return;
        _userHeading = heading;
        if (_annotationManager != null && _userAnnotation != null) {
          await _updateArrowMarker(positionChanged: false);
        }
      },
      onError: (e) {
        debugPrint('⚠️ Compass not available: $e');
      },
    );
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint('📍 Location service enabled: $serviceEnabled');

    if (!serviceEnabled) {
      setState(() {
        _locationPermissionGranted = false;
        _permissionChecked = true;
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    debugPrint('📍 Permission status: $permission');

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      debugPrint('📍 Permission after request: $permission');
    }

    final granted =
        permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;

    debugPrint('📍 Granted: $granted');

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
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _userPosition = Position(last.longitude, last.latitude);
      }
    } catch (e) {
      debugPrint('📍 Could not get last known position: $e');
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
          _userPosition = Position(position.longitude, position.latitude);
          if (_annotationManager != null && _userAnnotation != null) {
            await _updateArrowMarker(positionChanged: true);
          }
          if (_cameraFollowing && _mapboxMap != null) {
            await _moveCameraToUser(animated: true);
          }
        });
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData data) async {
    debugPrint('🗺️ Style loaded!');
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    await mapboxMap.compass.updateSettings(
      (CompassSettings()
        ..position = OrnamentPosition.TOP_RIGHT
        ..marginTop = 85
        ..marginRight = 4
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

    if (_userPosition != null && _cameraFollowing) {
      await _moveCameraToUser(animated: true);
    }

    await _loadAndPinPlants(mapboxMap);
  }

  Future<void> _loadAndPinPlants(MapboxMap mapboxMap) async {
    try {
      final response = await ApiService.get('/plants/grid/${widget.gridName}');
      final List data = response.data;
      debugPrint('🌿 Plants fetched: ${data.length}');
      _plants = data.map((e) => Map<String, dynamic>.from(e)).toList();

      _plantAnnotationManager = await mapboxMap.annotations
          .createPointAnnotationManager();

      // listen for pin taps
      _plantAnnotationManager!.addOnPointAnnotationClickListener(
        _PlantPinClickListener(_annotationPlantMap, _showPlantInfoSheet),
      );

      for (final plant in _plants) {
        debugPrint(
          '📍 Pinning: ${plant['qrCode']} at ${plant['latitude']}, ${plant['longitude']}',
        );
        await _addPlantPin(plant);
      }
    } catch (e) {
      debugPrint('❌ Error loading plants: $e');
    }
  }

  Future<void> _addPlantPin(Map<String, dynamic> plant) async {
    if (_plantAnnotationManager == null) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 48.0;

    final paint = Paint()..color = Colors.red;
    canvas.drawCircle(const Offset(size / 2, size / 2), 16, paint);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      8,
      Paint()..color = Colors.white,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final bitmap = byteData!.buffer.asUint8List();

    final annotation = await _plantAnnotationManager!.create(
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(plant['longitude'], plant['latitude']),
        ),
        image: bitmap,
        iconSize: 1.0,
      ),
    );

    // store annotation id → plant mapping for tap detection
    _annotationPlantMap[annotation.id] = plant;
    // store plant id → annotation object for position updates
    if (plant['id'] != null) {
      _plantAnnotationObjects[plant['id']] = annotation;
    }
  }

  void _showPlantInfoSheet(Map<String, dynamic> plant) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Plant Info',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (plant['qrCode'] != null)
                      _infoRow(Icons.qr_code_2, 'QR Code', plant['qrCode']),
                    _infoRow(Icons.grid_on, 'Grid', plant['gridName']),
                    _infoRow(Icons.location_on, 'Area', plant['areaName']),
                    _infoRow(
                      Icons.my_location,
                      'Latitude',
                      plant['latitude'].toStringAsFixed(6),
                    ),
                    _infoRow(
                      Icons.my_location,
                      'Longitude',
                      plant['longitude'].toStringAsFixed(6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInvalidQrSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.pinRed.withOpacity(0.4)),
        ),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(Icons.qr_code, color: AppColors.pinRed, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Invalid QR code.',
                style: TextStyle(
                  color: AppColors.pinRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _addPlantWithQr() async {
    if (_userPosition == null) {
      _showErrorSnackbar('Still fetching your location. Please wait.');
      return;
    }

    final isInside = GeofenceUtils.isInsideArea(
      _userPosition!.lat.toDouble(),
      _userPosition!.lng.toDouble(),
    );

    if (!isInside) {
      _showOutsideSnackbar();
      return;
    }

    final code = await context.push<String>('/scan');
    if (code == null || code.isEmpty) return;
    if (!mounted) return;

    if (!code.startsWith('RSNN')) {
      _showInvalidQrSnackbar();
      return;
    }

    // check if QR code already exists
    try {
      await ApiService.get('/plants/$code');
      // if we reach here, plant already exists
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: AppColors.pinRed.withOpacity(0.4)),
          ),
          margin: const EdgeInsets.all(16),
          content: Row(
            children: [
              Icon(Icons.qr_code, color: AppColors.pinRed, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'QR code already exists.',
                  style: TextStyle(
                    color: AppColors.pinRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // plant not found = QR code is new, safe to create
      try {
        final createRes = await ApiService.post(
          '/plants',
          data: {
            'qrCode': code,
            'latitude': _userPosition!.lat.toDouble(),
            'longitude': _userPosition!.lng.toDouble(),
            'gridName': widget.gridName,
            'areaName': widget.areaName,
          },
        );
        if (!mounted) return;
        final newPlant = {
          'id': createRes.data['id'],
          'qrCode': code,
          'latitude': _userPosition!.lat.toDouble(),
          'longitude': _userPosition!.lng.toDouble(),
          'gridName': widget.gridName,
          'areaName': widget.areaName,
        };
        await _addPlantPin(newPlant);
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
                  child: Text(
                    'Plant $code added successfully.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (createError) {
        if (!mounted) return;
        _showErrorSnackbar('Failed to add plant. Please try again.');
      }
    }
  }

  void _showOutsideSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.pinRed.withOpacity(0.4)),
        ),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(Icons.location_off, color: AppColors.pinRed, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You are outside the area.',
                style: TextStyle(
                  color: AppColors.pinRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.pinRed.withOpacity(0.4)),
        ),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.pinRed, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: AppColors.pinRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
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
    } catch (e) {
      debugPrint('❌ Error adding polygon: $e');
    }
  }

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
    } catch (e) {
      debugPrint('❌ Error adding center marker: $e');
    }
  }

  Future<Uint8List> _createArrowBitmap() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 80.0;

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

      final bitmap = await _createArrowBitmap();
      final location = _userPosition ?? Position(_defaultLng, _defaultLat);

      _userAnnotation = await _annotationManager!.create(
        PointAnnotationOptions(
          geometry: Point(coordinates: location),
          image: bitmap,
          iconSize: 1.0,
          iconRotate: _userHeading,
        ),
      );

      await _mapboxMap!.style.setStyleLayerProperty(
        _annotationManager!.id,
        'icon-rotation-alignment',
        'map',
      );
    } catch (e) {
      debugPrint('❌ Error adding arrow marker: $e');
    }
  }

  Future<void> _updateArrowMarker({bool positionChanged = false}) async {
    try {
      _userAnnotation!.iconRotate = _userHeading;
      if (positionChanged && _userPosition != null) {
        _userAnnotation!.geometry = Point(coordinates: _userPosition!);
      }
      await _annotationManager!.update(_userAnnotation!);
    } catch (e) {
      debugPrint('❌ Error updating arrow: $e');
    }
  }

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

          if (_permissionChecked) ...[
            Positioned(
              bottom: 260,
              right: 16,
              child: FloatingActionButton.small(
                heroTag: 'grid_add_plant',
                backgroundColor: AppColors.primary,
                onPressed: _addPlantWithQr,
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
            Positioned(
              bottom: 320,
              right: 16,
              child: FloatingActionButton.small(
                heroTag: 'grid_history',
                backgroundColor: AppColors.surface,
                onPressed: () => context.push('/plant-history'),
                child: const Icon(Icons.history, color: AppColors.primary),
              ),
            ),
            Positioned(
              bottom: 200,
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
          ],

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
                      onPressed: () async {
                        if (_userPosition == null) {
                          _showErrorSnackbar(
                            'Still fetching your location. Please wait.',
                          );
                          return;
                        }

                        final isInside = GeofenceUtils.isInsideArea(
                          _userPosition!.lat.toDouble(),
                          _userPosition!.lng.toDouble(),
                        );

                        if (!isInside) {
                          _showOutsideSnackbar();
                          return;
                        }

                        final code = await context.push<String>('/scan');
                        if (code == null || code.isEmpty) return;
                        if (!mounted) return;
                        if (!code.startsWith('RSNN')) {
                          _showInvalidQrSnackbar();
                          return;
                        }

                        // check if plant exists before going to data entry
                        try {
                          await ApiService.get('/plants/$code');
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: AppColors.pinRed.withOpacity(0.4),
                                ),
                              ),
                              margin: const EdgeInsets.all(16),
                              content: Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: AppColors.pinRed,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Plant not found. Add the plant first using the + button.',
                                      style: TextStyle(
                                        color: AppColors.pinRed,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                          return;
                        }

                        if (!mounted) return;
                        final result = await context.push<Map<String, dynamic>>(
                          '/data-entry',
                          extra: {'qrCode': code},
                        );

                        if (result != null && mounted) {
                          final plantId = result['plantId'] as String?;
                          final lat = result['latitude'] as double?;
                          final lng = result['longitude'] as double?;

                          if (plantId != null && lat != null && lng != null) {
                            // find the annotation for this plant and update its position
                            final entry = _annotationPlantMap.entries
                                .firstWhere(
                                  (e) => e.value['id'] == plantId,
                                  orElse: () => MapEntry('', {}),
                                );

                            if (entry.key.isNotEmpty &&
                                _plantAnnotationManager != null) {
                              // update local plant data
                              entry.value['latitude'] = lat;
                              entry.value['longitude'] = lng;

                              // directly look up and update the annotation
                              final annotation =
                                  _plantAnnotationObjects[plantId];
                              if (annotation != null) {
                                annotation.geometry = Point(
                                  coordinates: Position(lng, lat),
                                );
                                await _plantAnnotationManager!.update(
                                  annotation,
                                );
                              }
                            }
                          }
                        }
                      },
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
      onScrollListener: (_) {
        if (_cameraFollowing) {
          setState(() => _cameraFollowing = false);
        }
      },
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

// handles plant pin tap events
class _PlantPinClickListener extends OnPointAnnotationClickListener {
  final Map<String, Map<String, dynamic>> annotationPlantMap;
  final void Function(Map<String, dynamic>) onPlantTapped;

  _PlantPinClickListener(this.annotationPlantMap, this.onPlantTapped);

  @override
  void onPointAnnotationClick(PointAnnotation annotation) {
    final plant = annotationPlantMap[annotation.id];
    if (plant != null) {
      onPlantTapped(plant);
    }
  }
}
