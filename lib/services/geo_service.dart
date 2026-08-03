import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

/// A geocoding hit (place name + coordinates).
class GeoResult {
  GeoResult({required this.label, required this.point});
  final String label;
  final LatLng point;
}

/// Forward + reverse geocoding via OpenStreetMap Nominatim.
///
/// Uses its OWN Dio (never the tenant/auth ApiClient) since this talks to a
/// public external host. Nominatim asks for a descriptive User-Agent. All calls
/// fail soft (return empty / null) so the map UX degrades gracefully offline.
class GeoService {
  GeoService()
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://nominatim.openstreetmap.org',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 12),
          headers: {'User-Agent': 'SmartWashCustomerApp/1.0 (KSA laundry)'},
          validateStatus: (s) => s != null && s < 500,
        ));

  final Dio _dio;

  /// Search an address / place. [countryCode] biases results (ISO alpha-2).
  Future<List<GeoResult>> search(String query, {String? countryCode}) async {
    if (query.trim().isEmpty) return const [];
    try {
      final res = await _dio.get('/search', queryParameters: {
        'q': query.trim(),
        'format': 'jsonv2',
        'addressdetails': 0,
        'limit': 6,
        if (countryCode != null && countryCode.isNotEmpty) 'countrycodes': countryCode.toLowerCase(),
      });
      if (res.data is! List) return const [];
      return (res.data as List)
          .map((e) {
            final m = e as Map<String, dynamic>;
            final lat = double.tryParse('${m['lat']}');
            final lon = double.tryParse('${m['lon']}');
            if (lat == null || lon == null) return null;
            return GeoResult(label: (m['display_name'] as String?) ?? '', point: LatLng(lat, lon));
          })
          .whereType<GeoResult>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Reverse-geocode a pin into a human address (best-effort, may be null).
  Future<String?> reverse(LatLng point) async {
    try {
      final res = await _dio.get('/reverse', queryParameters: {
        'lat': point.latitude,
        'lon': point.longitude,
        'format': 'jsonv2',
        'zoom': 18,
      });
      if (res.data is! Map) return null;
      return (res.data as Map)['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }
}
