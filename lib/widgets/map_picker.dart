import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/l10n.dart';
import '../models/map_settings.dart';
import '../services/geo_service.dart';
import '../theme/app_theme.dart';
import 'map_layers.dart';
import 'ui.dart';

/// Result of the pin picker.
typedef PickedLocation = ({LatLng point, String address});

/// Full-screen interactive map to drop/adjust a pickup pin, search an address,
/// or use the current GPS location. Mirrors the web Leaflet pin picker.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, required this.settings, this.initial, this.initialAddress});
  final MapSettings settings;
  final LatLng? initial;
  final String? initialAddress;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _map = MapController();
  final _geo = GeoService();
  final _searchCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  late LatLng _center;
  Timer? _debounce;
  bool _resolving = false;
  bool _locating = false;
  MapStyle _style = MapStyle.map;
  List<GeoResult> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _center = widget.initial ?? LatLng(widget.settings.defaultLat, widget.settings.defaultLng);
    if (widget.initialAddress != null) _addressCtrl.text = widget.initialAddress!;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _onCameraChanged(LatLng c) {
    _center = c;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _reverseGeocode);
  }

  Future<void> _reverseGeocode() async {
    if (!mounted) return;
    setState(() => _resolving = true);
    final label = await _geo.reverse(_center);
    if (!mounted) return;
    setState(() {
      _resolving = false;
      if (label != null && label.isNotEmpty) _addressCtrl.text = label;
    });
  }

  Future<void> _search(String q) async {
    final results = await _geo.search(q, countryCode: widget.settings.countryCode);
    if (!mounted) return;
    setState(() => _suggestions = results);
  }

  void _selectSuggestion(GeoResult r) {
    FocusScope.of(context).unfocus();
    setState(() {
      _suggestions = const [];
      _searchCtrl.clear();
      _addressCtrl.text = r.label;
    });
    _center = r.point;
    _map.move(r.point, 16);
  }

  Future<void> _useMyLocation() async {
    // Capture localized strings before any await (avoid using context across gaps).
    final tServicesOff = context.t('Turn on location services to use this.');
    final tPermRequired = context.t('Location permission is required.');
    final tCantGet = context.t('Could not get your location.');
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _fail(tServicesOff);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _fail(tPermRequired);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final here = LatLng(pos.latitude, pos.longitude);
      _center = here;
      _map.move(here, 16);
      await _reverseGeocode();
    } catch (_) {
      _fail(tCantGet);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _fail(String msg) {
    if (mounted) showToast(context, msg, error: true);
  }

  Future<void> _confirm() async {
    // Guarantee the address auto-populates: if reverse-geocoding hasn't resolved yet
    // (e.g. the user pinned and confirmed quickly), do one final lookup before returning.
    _debounce?.cancel();
    var addr = _addressCtrl.text.trim();
    if (addr.isEmpty) {
      setState(() => _resolving = true);
      final label = await _geo.reverse(_center);
      if (!mounted) return;
      if (label != null && label.isNotEmpty) addr = label;
      setState(() => _resolving = false);
    }
    if (mounted) Navigator.of(context).pop<PickedLocation>((point: _center, address: addr));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              minZoom: 3,
              maxZoom: 19,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) _onCameraChanged(camera.center);
              },
              onTap: (_, _) => FocusScope.of(context).unfocus(),
            ),
            children: [
              ...mapTiles(_style, pkg: 'com.smartwash.customer'),
            ],
          ),

          // Map / Satellite toggle (hidden while the search suggestions are open).
          if (_suggestions.isEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 74,
              right: 14,
              child: MapStyleToggle(style: _style, onChanged: (s) => setState(() => _style = s)),
            ),

          // Fixed centre pin.
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: _CenterPin(active: !_resolving),
              ),
            ),
          ),

          // Top: back + search.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(
                children: [
                  Row(children: [
                    _CircleBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Material(
                        elevation: 3,
                        shadowColor: AppColors.ink.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        child: TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          onChanged: (v) {
                            _debounce?.cancel();
                            if (v.trim().length < 3) {
                              setState(() => _suggestions = const []);
                              return;
                            }
                            _debounce = Timer(const Duration(milliseconds: 450), () => _search(v));
                          },
                          decoration: InputDecoration(
                            hintText: context.t('Search address or place'),
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searchCtrl.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 20),
                                    onPressed: () => setState(() {
                                      _searchCtrl.clear();
                                      _suggestions = const [];
                                    }),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  if (_suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        boxShadow: AppShadows.card,
                      ),
                      child: Column(
                        children: [
                          for (final s in _suggestions)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_rounded, color: AppColors.primary, size: 20),
                              title: Text(s.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                              onTap: () => _selectSuggestion(s),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom sheet: address + confirm.
          Align(
            alignment: Alignment.bottomCenter,
            child: _BottomPanel(
              addressCtrl: _addressCtrl,
              resolving: _resolving,
              locating: _locating,
              onUseMyLocation: _useMyLocation,
              onConfirm: _confirm,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterPin extends StatelessWidget {
  const _CenterPin({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, boxShadow: AppShadows.glow(AppColors.primary)),
        child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 24),
      ),
      Container(width: 3, height: 16, color: AppColors.primary),
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.25), shape: BoxShape.circle),
      ),
    ]);
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: AppColors.ink.withValues(alpha: 0.2),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(11), child: Icon(icon, color: AppColors.ink, size: 22)),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.addressCtrl,
    required this.resolving,
    required this.locating,
    required this.onUseMyLocation,
    required this.onConfirm,
  });
  final TextEditingController addressCtrl;
  final bool resolving;
  final bool locating;
  final VoidCallback onUseMyLocation;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -8))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)),
          ),
        ),
        Row(children: [
          const Icon(Icons.push_pin_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(context.t('Pickup location'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const Spacer(),
          if (resolving)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: addressCtrl,
          minLines: 1,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: context.t('Building, street, district'),
            counterText: '',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: locating ? null : onUseMyLocation,
              icon: locating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: Text(context.t('My location')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check_rounded, size: 20),
              label: Text(context.t('Confirm location')),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ),
        ]),
      ]),
    );
  }
}
