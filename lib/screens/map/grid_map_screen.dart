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
      _plants = data.map((e) => Map<String, dynamic>.from(e)).toList();

      _plantAnnotationManager ??= await mapboxMap.annotations
          .createPointAnnotationManager();

      for (final plant in _plants) {
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

    // Red dot = not scanned this week
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

    await _plantAnnotationManager!.create(
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(plant['longitude'], plant['latitude']),
        ),
        image: bitmap,
        iconSize: 1.0,
      ),
    );
  }

  void _showAddPlantSheet(Position tapped) {
    final gridController = TextEditingController(text: widget.gridName);
    final areaController = TextEditingController(text: widget.areaName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Plant',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lat: ${tapped.lat.toStringAsFixed(6)}  Lng: ${tapped.lng.toStringAsFixed(6)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // QR scan row
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan Plant QR Code'),
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        final code = await context.push<String>('/scan');
                        if (code == null ||
                            code.isEmpty ||
                            !code.startsWith('RSNN')) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Invalid or cancelled QR scan'),
                            ),
                          );
                          return;
                        }
                        if (!mounted) return;
                        _showAddPlantSheetWithQr(
                          tapped,
                          code,
                          gridController.text,
                          areaController.text,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddPlantSheetWithQr(
    Position tapped,
    String qrCode,
    String initialGrid,
    String initialArea,
  ) {
    final gridController = TextEditingController(text: initialGrid);
    final areaController = TextEditingController(text: initialArea);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Plant',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lat: ${tapped.lat.toStringAsFixed(6)}  Lng: ${tapped.lng.toStringAsFixed(6)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.pinGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.pinGreen.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.qr_code_2,
                          color: AppColors.pinGreen,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          qrCode,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: gridController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Grid Name',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: areaController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Area Name',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              setSheetState(() => isSaving = true);
                              try {
                                final response = await ApiService.post(
                                  '/plants',
                                  data: {
                                    'qrCode': qrCode,
                                    'gridName': gridController.text.trim(),
                                    'areaName': areaController.text.trim(),
                                    'latitude': tapped.lat,
                                    'longitude': tapped.lng,
                                  },
                                );
                                final newPlant = Map<String, dynamic>.from(
                                  response.data,
                                );
                                if (!mounted) return;
                                Navigator.pop(sheetContext);
                                setState(() => _plants.add(newPlant));
                                await _addPlantPin(newPlant);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Plant added!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e) {
                                setSheetState(() => isSaving = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: ${e.toString()}'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Save Plant',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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

          if (_permissionChecked)
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
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not get your location'),
                            ),
                          );
                          return;
                        }

                        final inside = GeofenceUtils.isInsideArea(
                          _userPosition!.lat.toDouble(),
                          _userPosition!.lng.toDouble(),
                        );

                        if (!inside) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('You are outside the area.'),
                            ),
                          );
                          return;
                        }

                        final code = await context.push<String>('/scan');

                        if (code == null || code.isEmpty) return;

                        if (!code.startsWith('RSNN')) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invalid QR code')),
                          );
                          return;
                        }

                        if (!mounted) return;
                        context.push('/data-entry', extra: {'qrCode': code});
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
      onTapListener: (MapContentGestureContext context) {
        final tapped = context.point.coordinates;
        _showAddPlantSheet(tapped);
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
