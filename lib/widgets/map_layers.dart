import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Base map style — mirrors the web Map/Satellite toggle. Free tiles, no API key
/// (OpenStreetMap for the street map; Esri World Imagery + reference labels for satellite/hybrid).
enum MapStyle { map, satellite }

const _kOsm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _kEsriSat = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
const _kEsriRef = 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';

/// Tile layers for the chosen style. Satellite stacks an Esri labels overlay (hybrid, with place names).
List<Widget> mapTiles(MapStyle style, {String pkg = 'com.smartwash.app'}) {
  if (style == MapStyle.satellite) {
    return [
      TileLayer(urlTemplate: _kEsriSat, userAgentPackageName: pkg, maxZoom: 19),
      TileLayer(urlTemplate: _kEsriRef, userAgentPackageName: pkg, maxZoom: 19),
    ];
  }
  return [TileLayer(urlTemplate: _kOsm, userAgentPackageName: pkg, maxZoom: 19)];
}

/// Compact "Map | Satellite" toggle to overlay on any FlutterMap.
class MapStyleToggle extends StatelessWidget {
  const MapStyleToggle({super.key, required this.style, required this.onChanged});
  final MapStyle style;
  final ValueChanged<MapStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, IconData ic, MapStyle s) {
      final on = style == s;
      return InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => onChanged(s),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: on ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(9)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ic, size: 15, color: on ? Colors.white : AppColors.ink),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.ink)),
          ]),
        ),
      );
    }

    return Material(
      color: AppColors.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(11),
      shadowColor: AppColors.ink.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          seg(context.t('Map'), Icons.map_rounded, MapStyle.map),
          seg(context.t('Satellite'), Icons.satellite_alt_rounded, MapStyle.satellite),
        ]),
      ),
    );
  }
}

/// Small round map control button (fullscreen, close, …).
class MapRoundBtn extends StatelessWidget {
  const MapRoundBtn({super.key, required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: AppColors.ink.withValues(alpha: 0.2),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(9), child: Icon(icon, color: AppColors.ink, size: 20)),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// A full-screen interactive map with a Map/Satellite toggle — opened from the inline viewer's
/// fullscreen button. Pan, zoom and switch styles.
class FullScreenMap extends StatefulWidget {
  const FullScreenMap({super.key, required this.markers, required this.center, this.zoom = 14});
  final List<Marker> markers;
  final LatLng center;
  final double zoom;

  static Future<void> open(BuildContext context, {required List<Marker> markers, required LatLng center, double zoom = 14}) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => FullScreenMap(markers: markers, center: center, zoom: zoom)));
  }

  @override
  State<FullScreenMap> createState() => _FullScreenMapState();
}

class _FullScreenMapState extends State<FullScreenMap> {
  MapStyle _style = MapStyle.map;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          options: MapOptions(initialCenter: widget.center, initialZoom: widget.zoom, minZoom: 3, maxZoom: 19),
          children: [
            ...mapTiles(_style),
            MarkerLayer(markers: widget.markers),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              MapRoundBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop()),
              const Spacer(),
              MapStyleToggle(style: _style, onChanged: (s) => setState(() => _style = s)),
            ]),
          ),
        ),
      ]),
    );
  }
}
