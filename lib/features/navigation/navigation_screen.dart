import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../services/route_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map_layers.dart';
import '../../widgets/ui.dart';

/// In-app navigation map: the destination, the device's live location and the driving
/// route between them (road geometry from OSRM), with the remaining distance and an
/// estimated travel time. It follows the device while the screen is open and re-plans
/// the route as the driver moves.
///
/// Scope (deliberately): this is route guidance on a map, NOT voice turn-by-turn
/// navigation — no manoeuvre instructions are generated. If routing is unavailable the
/// map draws a straight line and shows the straight-line distance instead.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.destination,
    required this.title,
    this.subtitle,
    this.address,
    this.phone,
    this.color,
  });

  final LatLng destination;
  final String title;
  final String? subtitle;
  final String? address;
  final String? phone;
  final Color? color;

  static Future<void> open(
    BuildContext context, {
    required LatLng destination,
    required String title,
    String? subtitle,
    String? address,
    String? phone,
    Color? color,
  }) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NavigationScreen(
        destination: destination,
        title: title,
        subtitle: subtitle,
        address: address,
        phone: phone,
        color: color,
      ),
    ));
  }

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

enum _GpsState { locating, live, off, denied }

class _NavigationScreenState extends State<NavigationScreen> {
  static const _arrivedMeters = 60.0;
  static const _rerouteMeters = 120.0;
  static const _rerouteEvery = Duration(seconds: 30);

  final _map = MapController();
  final _routes = RouteService();
  final _distance = const Distance();

  StreamSubscription<Position>? _sub;
  MapStyle _style = MapStyle.map;
  _GpsState _gps = _GpsState.locating;
  LatLng? _me;
  RouteResult? _route;
  LatLng? _routedFrom;
  DateTime? _routedAt;
  bool _routing = false;
  bool _follow = true;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _startGps();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _gps = _GpsState.off);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gps = _GpsState.denied);
        return;
      }
      // First fix quickly (last known), then the live stream.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _onPosition(last);
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 8),
      ).listen(_onPosition, onError: (_) {
        if (mounted && _me == null) setState(() => _gps = _GpsState.off);
      });
    } catch (_) {
      if (mounted) setState(() => _gps = _GpsState.off);
    }
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    final me = LatLng(p.latitude, p.longitude);
    final first = _me == null;
    setState(() {
      _me = me;
      _gps = _GpsState.live;
    });
    if (first) {
      _fitAll();
    } else if (_follow && _mapReady) {
      _map.move(me, _map.camera.zoom);
    }
    _maybeReroute(me);
  }

  Future<void> _maybeReroute(LatLng me) async {
    if (_routing) return;
    // Plan once on the first fix; re-plan when the driver has moved well away from where the
    // route was planned (at most every 10 s), or retry a failed lookup every 30 s.
    final since = _routedAt == null ? null : DateTime.now().difference(_routedAt!);
    final moved = _routedFrom != null && _distance(_routedFrom!, me) > _rerouteMeters;
    final retry = _route == null && since != null && since > _rerouteEvery;
    if (since != null && !((moved && since > const Duration(seconds: 10)) || retry)) return;
    _routing = true;
    final r = await _routes.drive(me, widget.destination);
    _routing = false;
    _routedFrom = me;
    _routedAt = DateTime.now();
    if (!mounted) return;
    setState(() => _route = r);
  }

  void _fitAll() {
    if (!_mapReady) return;
    final pts = <LatLng>[widget.destination, ?_me, ...?_route?.points];
    if (pts.length < 2) {
      _map.move(widget.destination, 15);
      return;
    }
    _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.fromLTRB(48, 120, 48, 260)));
  }

  void _recenter() {
    setState(() => _follow = true);
    if (_me != null && _mapReady) _map.move(_me!, 16.5);
  }

  String _km(double meters) => meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';

  String _eta(double seconds) {
    final m = (seconds / 60).round();
    if (m < 60) return '$m min';
    return '${m ~/ 60} h ${m % 60} min';
  }

  Future<void> _call() async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: widget.phone));
    } catch (_) {
      if (mounted) showToast(context, context.t('Could not open this on your device.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? AppColors.primary;
    final me = _me;
    final straight = me == null ? null : _distance(me, widget.destination);
    final arrived = straight != null && straight <= _arrivedMeters;
    final line = _route?.points ?? (me == null ? null : [me, widget.destination]);

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: widget.destination,
            initialZoom: 15,
            minZoom: 3,
            maxZoom: 19,
            onMapReady: () {
              _mapReady = true;
              _fitAll();
            },
            // Panning by hand stops "follow me" until the driver taps recenter.
            onPositionChanged: (_, hasGesture) {
              if (hasGesture && _follow) setState(() => _follow = false);
            },
          ),
          children: [
            ...mapTiles(_style),
            if (line != null)
              PolylineLayer(polylines: [
                Polyline(
                  points: line,
                  strokeWidth: 5.5,
                  color: accent.withValues(alpha: _route == null ? 0.55 : 0.9),
                  borderStrokeWidth: 1.5,
                  borderColor: Colors.white,
                  pattern: _route == null ? StrokePattern.dashed(segments: const [12, 8]) : const StrokePattern.solid(),
                ),
              ]),
            MarkerLayer(markers: [
              Marker(
                point: widget.destination,
                width: 46,
                height: 46,
                alignment: Alignment.topCenter,
                child: Icon(Icons.location_on, color: accent, size: 44, shadows: const [Shadow(color: Colors.black26, blurRadius: 4)]),
              ),
              if (me != null)
                Marker(
                  point: me,
                  width: 26,
                  height: 26,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3.5),
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 10, spreadRadius: 4)],
                    ),
                  ),
                ),
            ]),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              MapRoundBtn(icon: Icons.arrow_back_rounded, tooltip: context.t('Back'), onTap: () => Navigator.of(context).pop()),
              const Spacer(),
              MapStyleToggle(style: _style, onChanged: (s) => setState(() => _style = s)),
            ]),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 250,
          child: Column(children: [
            MapRoundBtn(icon: Icons.zoom_out_map_rounded, tooltip: context.t('Show whole route'), onTap: () {
              setState(() => _follow = false);
              _fitAll();
            }),
            const SizedBox(height: 10),
            MapRoundBtn(icon: _follow ? Icons.my_location_rounded : Icons.location_searching_rounded, tooltip: context.t('My location'), onTap: _recenter),
          ]),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _panel(context, accent, straight, arrived),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _panel(BuildContext context, Color accent, double? straight, bool arrived) {
    final r = _route;
    String headline;
    String detail;
    if (arrived) {
      headline = context.t('You have arrived');
      detail = context.t('You are at the destination.');
    } else if (r != null) {
      headline = '${_km(r.meters)} · ${_eta(r.seconds)}';
      detail = context.t('Driving route by road (OpenStreetMap). Follow road signs and traffic rules.');
    } else if (straight != null) {
      headline = _km(straight);
      detail = _routing ? context.t('Finding the route…') : context.t('Straight-line distance: the road route is unavailable right now.');
    } else {
      headline = context.t('Destination');
      detail = switch (_gps) {
        _GpsState.denied => context.t('Location permission is off. Allow it to see your position and the route.'),
        _GpsState.off => context.t('Turn on location (GPS) to see your position and the route.'),
        _ => context.t('Finding your location…'),
      };
    }

    return Material(
      color: AppColors.surface,
      elevation: 6,
      shadowColor: AppColors.ink.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(arrived ? Icons.where_to_vote_rounded : Icons.navigation_rounded, color: accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppColors.ink)),
                if ((widget.subtitle ?? '').isNotEmpty)
                  Text(widget.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ]),
            ),
          ]),
          if ((widget.address ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.location_on_rounded, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(child: Text(widget.address!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.inkSoft, fontSize: 13))),
            ]),
          ],
          const SizedBox(height: 12),
          Text(headline, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: arrived ? AppColors.success : AppColors.ink)),
          const SizedBox(height: 2),
          Text(detail, style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3)),
          if ((widget.phone ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _call,
              icon: const Icon(Icons.call_rounded, size: 18),
              label: Text(context.t('Call')),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: BorderSide(color: AppColors.line), minimumSize: const Size.fromHeight(44)),
            ),
          ],
        ]),
      ),
    );
  }
}
