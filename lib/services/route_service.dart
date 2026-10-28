import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

/// A driving route between two points (road geometry + totals).
class RouteResult {
  RouteResult({required this.points, required this.meters, required this.seconds});
  final List<LatLng> points;
  final double meters;
  final double seconds;
}

/// Road routing via the public OSRM demo server (OpenStreetMap data, no API key).
///
/// Uses its OWN Dio (never the tenant/auth ApiClient) since this talks to a public external
/// host. It returns the route line, distance and travel time only — no turn-by-turn
/// instructions are requested or shown. The public server is rate-limited and has no SLA, so
/// every call fails soft (null) and the map falls back to a straight line to the destination.
/// For production volumes point [baseUrl] at a self-hosted OSRM or a commercial router.
class RouteService {
  RouteService({String baseUrl = 'https://router.project-osrm.org'})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 12),
          headers: {'User-Agent': 'SmartWashDriverApp/1.0'},
          validateStatus: (s) => s != null && s < 500,
        ));

  final Dio _dio;

  Future<RouteResult?> drive(LatLng from, LatLng to) async {
    try {
      final res = await _dio.get(
        '/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
        queryParameters: {'overview': 'full', 'geometries': 'geojson', 'steps': 'false'},
      );
      if (res.data is! Map) return null;
      final routes = (res.data as Map)['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final r = routes.first as Map;
      final coords = ((r['geometry'] as Map?)?['coordinates'] as List?) ?? const [];
      final points = coords
          .whereType<List>()
          .where((c) => c.length >= 2)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      if (points.length < 2) return null;
      return RouteResult(
        points: points,
        meters: (r['distance'] as num?)?.toDouble() ?? 0,
        seconds: (r['duration'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
