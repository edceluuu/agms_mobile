/// Geofence utility that reuses the same polygon drawn on GridMapScreen.
/// Uses the Ray Casting algorithm for point-in-polygon detection.
class GeofenceUtils {
  /// The allowed area — same coordinates as _gridGeoJson in grid_map_screen.dart.
  static const List<List<double>> _polygonCoords = [
    [125.83254553754443, 7.381025986055903],
    [125.83254553754443, 7.373267996942374],
    [125.84379392505303, 7.373267996942374],
    [125.84379392505303, 7.381025986055903],
    [125.83254553754443, 7.381025986055903], // closed
  ];

  /// Returns true if [lng], [lat] is inside the allowed polygon.
  static bool isInsideArea(double lat, double lng) {
    return _isPointInPolygon(lat, lng, _polygonCoords);
  }

  /// Ray Casting algorithm — counts how many times a ray from the point
  /// crosses the polygon edges. Odd = inside, Even = outside.
  static bool _isPointInPolygon(
    double lat,
    double lng,
    List<List<double>> polygon,
  ) {
    int intersectCount = 0;
    final int vertexCount = polygon.length;

    for (int i = 0, j = vertexCount - 1; i < vertexCount; j = i++) {
      final double xi = polygon[i][0]; // lng
      final double yi = polygon[i][1]; // lat
      final double xj = polygon[j][0];
      final double yj = polygon[j][1];

      final bool intersect =
          ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);

      if (intersect) intersectCount++;
    }

    return intersectCount % 2 == 1;
  }
}
