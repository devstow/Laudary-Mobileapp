import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../../l10n/l10n.dart';
import '../../services/tracking_service.dart';

/// What the driver's location sharing is doing right now — shown on the driver dashboard, never guessed.
enum TrackingState {
  /// Not a driver session, or signed out.
  off,
  starting,
  /// Position stream running and fixes reaching the server.
  active,
  /// Running, but the last sends failed (no network) — fixes are buffered and resent.
  offline,
  /// Device location (GPS) is switched off.
  serviceDisabled,
  /// The driver declined location access (can be asked again).
  permissionDenied,
  /// Declined permanently — only the system settings can change it.
  permissionDeniedForever,
  /// The server says this account isn't an active driver.
  notADriver,
  error,
}

/// Automatic driver location sharing for the whole signed-in driver session (owned by AppState, started after
/// login — no screen has to be open).
///
/// Android: a geolocator position stream run inside a FOREGROUND SERVICE (type "location", ongoing notification),
/// so updates continue while the app is in the background or the screen is locked. Started while the app is
/// visible with "while in use" permission — background ("all the time") location is NOT requested; Android 14
/// allows a location foreground service started from the foreground on that basis. If the OS kills the app,
/// tracking stops until the driver opens it again (the web map then shows "signal lost" → "offline", never fake
/// movement).
///
/// Sending policy (from the server's config): a fix when the driver has moved [sendDistance] metres, or every
/// [sendInterval] while moving; a fresh-fix keep-alive every [heartbeat] while parked. Failed sends are buffered
/// (bounded) and flushed in one batch when the network returns. The server derives the driver from the token.
class LocationTracker extends ChangeNotifier with WidgetsBindingObserver {
  LocationTracker(this._api, {required this.lang});

  final TrackingService _api;
  /// Current UI language code ('en' / 'ar') for the foreground notification text.
  final String Function() lang;

  static const int _maxBuffer = 300;
  static const int _batch = 100;

  TrackingState state = TrackingState.off;
  DateTime? lastSentAt;
  DateTime? lastFixAt;
  int buffered = 0;
  List<BranchGeofence> geofences = const [];
  /// Branch geofence the driver is inside (the server's answer to the last send).
  String? insideBranchId;

  /// Order numbers the server auto-advanced to "Arrived" (existing customer-arrival rule).
  final _arrivals = StreamController<List<String>>.broadcast();
  Stream<List<String>> get arrivals => _arrivals.stream;

  StreamSubscription<Position>? _sub;
  Timer? _heartbeat;
  final List<LocationFix> _queue = [];
  bool _sending = false;
  bool _running = false;
  LocationFix? _lastSent;
  int _sendDistance = 25;
  Duration _sendInterval = const Duration(seconds: 15);
  Duration _heartbeatEvery = const Duration(seconds: 60);
  bool _observing = false;

  String? get insideBranchName {
    final id = insideBranchId;
    if (id == null) return null;
    for (final g in geofences) {
      if (g.branchId == id) return g.name;
    }
    return null;
  }

  bool get isSharing => state == TrackingState.active || state == TrackingState.offline;

  /// Start (or retry) sharing. Safe to call repeatedly; asks for permission only when [askPermission].
  Future<void> start({bool askPermission = true}) async {
    if (_running) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _set(TrackingState.starting);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _set(TrackingState.serviceDisabled);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && askPermission) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        _set(TrackingState.permissionDeniedForever);
        return;
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) {
        _set(TrackingState.permissionDenied);
        return;
      }

      final config = await _api.config();
      if (config == null) {
        _set(TrackingState.notADriver);
        return;
      }
      geofences = config.geofences;
      _sendDistance = config.sendDistanceMeters;
      _sendInterval = Duration(seconds: config.sendIntervalSeconds);
      _heartbeatEvery = Duration(seconds: config.heartbeatSeconds);

      _running = true;
      _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
        _onPosition,
        onError: (Object e) {
          // Location turned off / permission revoked while running.
          _stopStream();
          _set(e is LocationServiceDisabledException ? TrackingState.serviceDisabled : TrackingState.permissionDenied);
        },
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) => _keepAlive());
      _set(TrackingState.active);
      // First position immediately (the stream may wait for movement).
      unawaited(_freshFix());
    } catch (_) {
      _stopStream();
      _set(TrackingState.error);
    }
  }

  /// Stop sharing. [notifyServer] (sign-out with a valid session): the map shows the driver offline at once.
  Future<void> stop({bool notifyServer = false}) async {
    final wasRunning = _running;
    _stopStream();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _queue.clear();
    buffered = 0;
    lastSentAt = null;
    lastFixAt = null;
    insideBranchId = null;
    _lastSent = null;
    _set(TrackingState.off);
    if (notifyServer && wasRunning) await _api.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from settings / the permission dialog: try again without nagging.
    if (state == AppLifecycleState.resumed && !_running && this.state != TrackingState.off && this.state != TrackingState.notADriver) {
      unawaited(start(askPermission: false));
    }
  }

  LocationSettings _settings() {
    final ar = lang() == 'ar';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: AppStrings.get('Smart Wash — on duty', ar ? 'ar' : 'en'),
          notificationText: AppStrings.get('Sharing your location with dispatch while you are signed in.', ar ? 'ar' : 'en'),
          notificationIcon: const AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
  }

  void _onPosition(Position p) {
    final fix = _toFix(p);
    lastFixAt = DateTime.now();
    final last = _lastSent;
    final due = last == null ||
        _distance(last, fix) >= _sendDistance ||
        fix.recordedAt.difference(last.recordedAt) >= _sendInterval;
    if (due) _enqueue(fix);
    notifyListeners();
  }

  /// Parked drivers produce no stream events (distance filter) — fetch a FRESH fix so they stay "online".
  /// Never re-sends an old position with a new timestamp.
  Future<void> _keepAlive() async {
    if (!_running) return;
    if (_queue.isNotEmpty) unawaited(_flush()); // retry buffered sends
    final last = lastSentAt;
    if (last != null && DateTime.now().difference(last) < _heartbeatEvery) return;
    await _freshFix();
  }

  Future<void> _freshFix() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (!_running) return;
      lastFixAt = DateTime.now();
      _enqueue(_toFix(p));
    } catch (_) {/* no fix right now: the map will honestly show the driver going stale */}
  }

  LocationFix _toFix(Position p) => LocationFix(
        lat: p.latitude,
        lng: p.longitude,
        recordedAt: p.timestamp.toUtc(),
        accuracy: p.accuracy,
        speed: p.speed,
        // Heading is only meaningful while moving.
        heading: p.speed > 0.5 ? p.heading : null,
        isMocked: p.isMocked,
      );

  void _enqueue(LocationFix fix) {
    _queue.add(fix);
    if (_queue.length > _maxBuffer) _queue.removeRange(0, _queue.length - _maxBuffer);
    _lastSent = fix;
    buffered = _queue.length;
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_sending || _queue.isEmpty) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty && _running) {
        final batch = _queue.take(_batch).toList();
        final r = await _api.send(batch);
        _queue.removeRange(0, batch.length);
        buffered = _queue.length;
        if (r.notADriver) {
          _stopStream();
          _set(TrackingState.notADriver);
          return;
        }
        if (r.ok) {
          lastSentAt = DateTime.now();
          insideBranchId = r.insideBranchId;
          if (r.arrived.isNotEmpty) _arrivals.add(r.arrived);
        }
        _set(TrackingState.active);
      }
    } catch (_) {
      // Network down: keep the buffer; the keep-alive timer retries.
      if (_running) _set(TrackingState.offline);
    } finally {
      _sending = false;
    }
  }

  void _stopStream() {
    _running = false;
    _sub?.cancel();
    _sub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _set(TrackingState s) {
    state = s;
    notifyListeners();
  }

  static double _distance(LocationFix a, LocationFix b) {
    const r = 6371000.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.lat * math.pi / 180) * math.cos(b.lat * math.pi / 180) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  @override
  void dispose() {
    _stopStream();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _arrivals.close();
    super.dispose();
  }
}
