import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../services/delivery_service.dart';

/// Posts the driver's GPS to the server every 25s while they have an in-transit task,
/// so the server can auto-advance a task to "Arrived" on geofence entry — same behaviour
/// as the web driver portal. Foreground-only, fail-silent on permission/GPS errors.
class GeofenceHeartbeat {
  GeofenceHeartbeat(this._svc);
  final DeliveryService _svc;

  Timer? _timer;
  bool _running = false;

  /// Call after each task reload. Starts the heartbeat when an in-transit task appears,
  /// stops it when none remain. [onArrived] fires with the order numbers that auto-arrived.
  void sync({required bool hasInTransit, required void Function(List<String> arrived) onArrived}) {
    if (hasInTransit && !_running) {
      _running = true;
      _beat(onArrived); // immediate first ping
      _timer = Timer.periodic(const Duration(seconds: 25), (_) => _beat(onArrived));
    } else if (!hasInTransit && _running) {
      stop();
    }
  }

  Future<void> _beat(void Function(List<String>) onArrived) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      final arrived = await _svc.location(pos.latitude, pos.longitude);
      if (arrived.isNotEmpty) onArrived(arrived);
    } catch (_) {/* best-effort */}
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  void dispose() => stop();
}
