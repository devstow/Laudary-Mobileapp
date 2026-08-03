import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';

/// A small, non-interactive map preview with pickup/delivery markers.
class MapViewer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final points = [?pickup, ?delivery];
    if (points.isEmpty) return const SizedBox.shrink();

    final center = points.length == 1
        ? points.first
        : LatLng(
            points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
            points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
            interactionOptions: InteractionOptions(
              flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.smartwash.customer',
              maxZoom: 19,
            ),
            MarkerLayer(markers: [
              if (pickup != null) _marker(pickup!, AppColors.primary),
              if (delivery != null) _marker(delivery!, AppColors.gold),
            ]),
          ],
        ),
      ),
    );
  }

  Marker _marker(LatLng p, Color color) => Marker(
        point: p,
        width: 40,
        height: 40,
        alignment: Alignment.topCenter,
        child: Icon(Icons.location_on, color: color, size: 38, shadows: const [Shadow(color: Colors.black26, blurRadius: 4)]),
      );
}
