import '../core/api_client.dart';
import 'api_exception.dart';

/// One GPS fix as sent to the server (POST api/tracking/location).
class LocationFix {
  LocationFix({
    required this.lat,
    required this.lng,
    required this.recordedAt,
    this.accuracy,
    this.speed,
    this.heading,
    this.isMocked = false,
  });

  final double lat;
  final double lng;
  final DateTime recordedAt;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final bool isMocked;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'recordedAt': recordedAt.toUtc().toIso8601String(),
        if (accuracy != null && accuracy! >= 0) 'accuracy': accuracy,
        // geolocator reports -1 / 0 when unknown; the server ignores out-of-range values anyway.
        if (speed != null && speed! >= 0) 'speed': speed,
        if (heading != null && heading! >= 0) 'heading': heading,
        'isMocked': isMocked,
      };
}

class BranchGeofence {
  BranchGeofence({required this.branchId, required this.name, required this.lat, required this.lng, required this.radius});
  final String branchId;
  final String name;
  final double lat;
  final double lng;
  final int radius;

  factory BranchGeofence.fromJson(Map<String, dynamic> j) => BranchGeofence(
        branchId: j['branchId'].toString(),
        name: (j['name'] ?? '').toString(),
        lat: (j['latitude'] as num).toDouble(),
        lng: (j['longitude'] as num).toDouble(),
        radius: (j['radiusMeters'] as num).toInt(),
      );
}

/// GET api/tracking/config — the branch geofences to monitor + the server's send policy.
class TrackingConfig {
  TrackingConfig({required this.geofences, required this.sendDistanceMeters, required this.sendIntervalSeconds, required this.heartbeatSeconds});
  final List<BranchGeofence> geofences;
  final int sendDistanceMeters;
  final int sendIntervalSeconds;
  final int heartbeatSeconds;

  factory TrackingConfig.fromJson(Map<String, dynamic> j) => TrackingConfig(
        geofences: ((j['geofences'] as List?) ?? const [])
            .map((e) => BranchGeofence.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        sendDistanceMeters: (j['sendDistanceMeters'] as num?)?.toInt() ?? 25,
        sendIntervalSeconds: (j['sendIntervalSeconds'] as num?)?.toInt() ?? 15,
        heartbeatSeconds: (j['heartbeatSeconds'] as num?)?.toInt() ?? 60,
      );
}

class TrackingSendResult {
  TrackingSendResult({required this.ok, this.notADriver = false, this.arrived = const [], this.insideBranchId});
  final bool ok;
  /// 403: this account isn't an active driver — stop tracking.
  final bool notADriver;
  final List<String> arrived;
  final String? insideBranchId;
}

/// Live-tracking API (api/tracking/*). The driver is the signed-in user — requests never carry a driver id.
class TrackingService {
  TrackingService(this._api);
  final ApiClient _api;

  /// Null when the account isn't a driver (403) — tracking must not start.
  Future<TrackingConfig?> config() async {
    final res = await _api.dio.get('/api/tracking/config');
    if (res.statusCode == 403) return null;
    if (!isOk(res) || res.data is! Map) throw ApiException.from(res);
    return TrackingConfig.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// Throws on network failure (the caller keeps the fixes buffered and retries).
  Future<TrackingSendResult> send(List<LocationFix> fixes) async {
    final res = await _api.dio.post('/api/tracking/location', data: {'fixes': fixes.map((f) => f.toJson()).toList()});
    if (res.statusCode == 403) return TrackingSendResult(ok: false, notADriver: true);
    // 400 = every fix in the batch was invalid (e.g. a bad device clock): drop the batch, don't retry forever.
    if (res.statusCode == 400) return TrackingSendResult(ok: false);
    if (!isOk(res)) throw ApiException.from(res);
    final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    return TrackingSendResult(
      ok: true,
      arrived: ((data['arrived'] as List?) ?? const []).map((e) => e.toString()).toList(),
      insideBranchId: data['insideBranchId']?.toString(),
    );
  }

  /// Best-effort: tells the server the driver stopped sharing (sign-out), so the map shows them offline at once.
  Future<void> stop() async {
    try {
      await _api.dio.post('/api/tracking/stop');
    } catch (_) {}
  }
}
