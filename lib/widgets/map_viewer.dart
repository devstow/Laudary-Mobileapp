import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import 'map_layers.dart';

/// A small map preview with pickup/delivery markers, a Map/Satellite toggle and a
/// fullscreen button (opens a full interactive map). Mirrors the web Leaflet viewer.
class MapViewer extends StatefulWidget {
  const MapViewer({
    super.key,
    this.pickup,
    this.delivery,
    this.height = 170,
    this.interactive = false,
  });
  final LatLng? pickup;
  final LatLng? delivery;
  final double height;
  final bool interactive;

  @override
  State<MapViewer> createState() => _MapViewerState();
}

class _MapViewerState extends State<MapViewer> {
  MapStyle _style = MapStyle.map;

  Marker _marker(LatLng p, Color color) => Marker(
        point: p,
        width: 40,
        height: 40,
        alignment: Alignment.topCenter,
        child: Icon(Icons.location_on, color: color, size: 38, shadows: const [Shadow(color: Colors.black26, blurRadius: 4)]),
      );

  @override
  Widget build(BuildContext context) {
    final points = [?widget.pickup, ?widget.delivery];
    if (points.isEmpty) return const SizedBox.shrink();

    final center = points.length == 1
        ? points.first
        : LatLng(
            points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
            points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
          );

    final markers = <Marker>[
      if (widget.pickup != null) _marker(widget.pickup!, AppColors.primary),
      if (widget.delivery != null) _marker(widget.delivery!, AppColors.gold),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14,
                minZoom: 3,
                maxZoom: 19,
                interactionOptions: InteractionOptions(
                  flags: widget.interactive ? InteractiveFlag.all : InteractiveFlag.none,
                ),
              ),
              children: [
                ...mapTiles(_style),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              top: 8,
              left: 8,
              child: MapStyleToggle(style: _style, onChanged: (s) => setState(() => _style = s)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: MapRoundBtn(
                icon: Icons.fullscreen_rounded,
                tooltip: 'Fullscreen',
                onTap: () => FullScreenMap.open(context, markers: markers, center: center, zoom: points.length == 1 ? 15 : 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
