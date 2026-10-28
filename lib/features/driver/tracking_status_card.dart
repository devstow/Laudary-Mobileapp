import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'location_tracker.dart';

/// Driver dashboard: is my location being shared with dispatch right now? Shows the real state (never "live"
/// when it isn't) and the one action that fixes a blocked state (allow access / turn on GPS / open settings).
class TrackingStatusCard extends StatefulWidget {
  const TrackingStatusCard({super.key});

  @override
  State<TrackingStatusCard> createState() => _TrackingStatusCardState();
}

class _TrackingStatusCardState extends State<TrackingStatusCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Re-render "sent 12s ago" without waiting for the next fix.
    _tick = Timer.periodic(const Duration(seconds: 10), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _ago(BuildContext context, DateTime? t) {
    if (t == null) return context.t('not yet');
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return '$s ${context.t('sec ago')}';
    return '${(s / 60).round()} ${context.t('min ago')}';
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.watch<LocationTracker>();
    if (tr.state == TrackingState.off || tr.state == TrackingState.notADriver) return const SizedBox.shrink();

    late final Color color;
    late final IconData icon;
    late final String title;
    String? body;
    String? action;
    Future<void> Function()? onAction;

    switch (tr.state) {
      case TrackingState.active:
        color = AppColors.success;
        icon = Icons.my_location_rounded;
        title = context.t('Sharing your location');
        body = '${context.t('Last sent')} ${_ago(context, tr.lastSentAt)}'
            '${tr.insideBranchName != null ? ' · ${context.t('At')} ${tr.insideBranchName}' : ''}';
      case TrackingState.offline:
        color = AppColors.warning;
        icon = Icons.cloud_off_rounded;
        title = context.t('No connection — locations saved');
        body = '${tr.buffered} ${context.t('waiting to send')}';
      case TrackingState.starting:
        color = AppColors.info;
        icon = Icons.location_searching_rounded;
        title = context.t('Starting location sharing…');
      case TrackingState.serviceDisabled:
        color = AppColors.danger;
        icon = Icons.location_disabled_rounded;
        title = context.t('Location (GPS) is turned off');
        body = context.t('Dispatch can\'t see you on the map.');
        action = context.t('Turn on');
        onAction = () async { await Geolocator.openLocationSettings(); };
      case TrackingState.permissionDenied:
        color = AppColors.danger;
        icon = Icons.location_off_rounded;
        title = context.t('Location access needed');
        body = context.t('Dispatch can\'t see you on the map.');
        action = context.t('Allow');
        onAction = () => tr.start();
      case TrackingState.permissionDeniedForever:
        color = AppColors.danger;
        icon = Icons.location_off_rounded;
        title = context.t('Location access is blocked');
        body = context.t('Allow location for Smart Wash in your phone settings.');
        action = context.t('Settings');
        onAction = () async { await Geolocator.openAppSettings(); };
      default:
        color = AppColors.danger;
        icon = Icons.error_outline_rounded;
        title = context.t('Location sharing stopped');
        action = context.t('Retry');
        onAction = () => tr.start();
    }

    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink)),
            if (body != null) ...[
              const SizedBox(height: 2),
              Text(body, style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.25)),
            ],
          ]),
        ),
        if (action != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(action, style: TextStyle(color: color, fontWeight: FontWeight.w800))),
      ]),
    );
  }
}
