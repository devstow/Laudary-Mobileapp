import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/navigation/navigation_screen.dart';
import '../l10n/l10n.dart';
import '../models/delivery.dart';
import '../models/enums.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Driver actions the card can request (parent runs the service call + reason/proof flow).
enum DriverAction { accept, reject, start, arrived, complete, fail, dropOff }

Color deliveryStatusColor(DeliveryStatus s) {
  switch (s) {
    case DeliveryStatus.assigned:
      return AppColors.warning;
    case DeliveryStatus.accepted:
    case DeliveryStatus.inTransit:
      return AppColors.info;
    case DeliveryStatus.arrived:
    case DeliveryStatus.droppedOff:
      return AppColors.primary;
    case DeliveryStatus.collected:
      return AppColors.info;
    case DeliveryStatus.completed:
      return AppColors.success;
    case DeliveryStatus.failed:
    case DeliveryStatus.rejected:
      return AppColors.danger;
    case DeliveryStatus.pending:
    case DeliveryStatus.cancelled:
      return AppColors.faint;
  }
}

IconData deliveryStatusIcon(DeliveryStatus s) {
  switch (s) {
    case DeliveryStatus.pending:
      return Icons.inbox_rounded;
    case DeliveryStatus.assigned:
      return Icons.pending_actions_rounded;
    case DeliveryStatus.accepted:
      return Icons.thumb_up_rounded;
    case DeliveryStatus.inTransit:
      return Icons.local_shipping_rounded;
    case DeliveryStatus.arrived:
      return Icons.where_to_vote_rounded;
    case DeliveryStatus.collected:
      return Icons.inventory_2_rounded;
    case DeliveryStatus.droppedOff:
      return Icons.storefront_rounded;
    case DeliveryStatus.completed:
      return Icons.check_circle_rounded;
    case DeliveryStatus.failed:
      return Icons.error_rounded;
    case DeliveryStatus.rejected:
      return Icons.thumb_down_rounded;
    case DeliveryStatus.cancelled:
      return Icons.cancel_rounded;
  }
}

Color deliveryTypeColor(DeliveryType t) => t == DeliveryType.pickup ? AppColors.warning : AppColors.success;

/// The driver's task card. In [compact] mode it's a tappable summary (used in lists) — no
/// journey/action buttons; tapping opens the detail. In full mode it shows the journey stepper
/// + status-gated actions (used on the task detail screen).
class DriverTaskCard extends StatelessWidget {
  const DriverTaskCard({super.key, required this.task, this.stopNumber, this.onAction, this.busy = false, this.compact = false, this.onTap});
  final DeliveryTask task;
  final int? stopNumber;
  final void Function(DriverAction action)? onAction;
  final bool busy;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final df = DateFormat('EEE dd MMM, HH:mm', lang);
    final tColor = deliveryTypeColor(task.type);
    final sColor = deliveryStatusColor(task.status);
    final offTrack = task.status.journeyIndexFor(task.type) < 0;

    return SoftCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header: type + order# (+ stop/attempt) ......... status chip
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: tColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
            child: Icon(task.isPickup ? Icons.download_rounded : Icons.upload_rounded, color: tColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (stopNumber != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(6)),
                    child: Text('$stopNumber', style: const TextStyle(color: AppColors.onGold, fontWeight: FontWeight.w900, fontSize: 11)),
                  ),
                ],
                Flexible(child: Text(task.orderNumber ?? '—', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink))),
                const SizedBox(width: 6),
                _typeTag(context, task.type, tColor),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.person_rounded, size: 14, color: AppColors.muted),
                const SizedBox(width: 4),
                Expanded(child: Text(task.customerName ?? '—', overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontSize: 13))),
                if (task.attemptNumber > 1) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(6)),
                    child: Text('${context.t('Attempt')} ${task.attemptNumber}', style: const TextStyle(color: AppColors.goldDark, fontWeight: FontWeight.w700, fontSize: 10.5)),
                  ),
                ],
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          _statusChip(context, sColor),
        ]),

        _urgencyChip(context),

        const SizedBox(height: 12),
        // Address + schedule + phone
        if (task.headingToBranch || task.status == DeliveryStatus.droppedOff)
          _line(Icons.storefront_rounded, '${context.t('Drop off at branch')}: ${task.branchName ?? '—'}')
        else
          _line(Icons.location_on_rounded, '${context.t(task.isPickup ? 'Collect from' : 'Deliver to')}: ${task.address ?? context.t('No address on file')}'),
        if (task.scheduledAt != null) _line(Icons.event_rounded, '${context.t('Scheduled')}: ${df.format(task.scheduledAt!)}'),
        if (task.collectedAt != null) _line(Icons.inventory_2_rounded, '${context.t('Collected')}: ${df.format(task.collectedAt!)}'),
        if (task.droppedOffAt != null) _line(Icons.storefront_rounded, '${context.t('Handed over at branch')}: ${df.format(task.droppedOffAt!)}'),
        if (task.receivedAt != null) _line(Icons.check_circle_rounded, '${context.t('Received at branch')}: ${df.format(task.receivedAt!)}')
        else if (task.completedAt != null) _line(Icons.check_circle_rounded, '${context.t('Done')}: ${df.format(task.completedAt!)}'),

        const SizedBox(height: 12),

        if (offTrack)
          _offTrackAlert(context)
        else if (compact)
          _detailsHint(context)
        else ...[
          _MiniJourney(status: task.status, type: task.type),
          const SizedBox(height: 14),
          _actions(context),
        ],
      ]),
    );
  }

  Widget _detailsHint(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(context.t('View details'), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
        ],
      );

  /// Overdue / Today priority chip (day-granularity, computed from the schedule) — only for
  /// on-track tasks, mirroring the web card. Upcoming shows nothing.
  Widget _urgencyChip(BuildContext context) {
    if (task.status.journeyIndexFor(task.type) < 0 ||
        task.status == DeliveryStatus.completed ||
        task.status == DeliveryStatus.collected ||
        task.status == DeliveryStatus.droppedOff) {
      return const SizedBox.shrink(); // the stop itself is done
    }
    final s = task.scheduledAt;
    if (s == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(s.year, s.month, s.day);
    Widget? chip;
    if (due.isBefore(today)) {
      chip = _urgencyPill(context, 'Overdue', AppColors.danger, Icons.alarm_rounded);
    } else if (due == today) {
      chip = _urgencyPill(context, 'Today', AppColors.warning, Icons.event_rounded);
    }
    if (chip == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(alignment: AlignmentDirectional.centerStart, child: chip),
    );
  }

  Widget _urgencyPill(BuildContext context, String label, Color c, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(context.t(label), style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11)),
        ]),
      );

  Widget _typeTag(BuildContext context, DeliveryType t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
        child: Text(context.t(t.label), style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 10.5)),
      );

  Widget _statusChip(BuildContext context, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(deliveryStatusIcon(task.status), size: 14, color: c),
          const SizedBox(width: 4),
          Text(context.t(task.status.label), style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11.5)),
        ]),
      );

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.3))),
        ]),
      );

  Widget _offTrackAlert(BuildContext context) {
    final rejected = task.status == DeliveryStatus.rejected;
    final failed = task.status == DeliveryStatus.failed;
    final c = (rejected || failed) ? AppColors.danger : AppColors.faint;
    final msg = rejected
        ? (task.rejectionReason ?? task.failureReason ?? context.t('You rejected this task.'))
        : failed
            ? (task.failureReason ?? context.t('Marked as failed.'))
            : context.t('This task was cancelled.');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(deliveryStatusIcon(task.status), size: 18, color: c),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12.5, height: 1.3))),
      ]),
    );
  }

  Widget _actions(BuildContext context) {
    final buttons = <Widget>[];
    // Navigate (in-app map + route) + Call are available when we have coords / phone. Once a
    // pickup is collected the destination is the branch.
    if (task.headingToBranch) {
      buttons.add(_ghostBtn(context, Icons.navigation_rounded, context.t('Navigate to branch'), () => _navigate(context)));
    } else if (task.hasLocation && task.status != DeliveryStatus.droppedOff) {
      buttons.add(_ghostBtn(context, Icons.navigation_rounded, context.t('Navigate'), () => _navigate(context)));
    }
    if ((task.contactPhone ?? '').isNotEmpty) buttons.add(_ghostBtn(context, Icons.call_rounded, context.t('Call'), () => _call(context)));

    switch (task.status) {
      case DeliveryStatus.assigned:
        buttons.add(_primaryBtn(context, Icons.check_rounded, context.t('Accept'), AppColors.success, () => onAction?.call(DriverAction.accept)));
        buttons.add(_dangerBtn(context, context.t('Reject'), () => onAction?.call(DriverAction.reject)));
        break;
      case DeliveryStatus.accepted:
        buttons.add(_primaryBtn(context, Icons.local_shipping_rounded, context.t('Start trip'), AppColors.primary, () => onAction?.call(DriverAction.start)));
        buttons.add(_dangerBtn(context, context.t("Can't complete"), () => onAction?.call(DriverAction.fail)));
        break;
      case DeliveryStatus.inTransit:
        buttons.add(_primaryBtn(context, Icons.where_to_vote_rounded, context.t('Mark arrived'), AppColors.primary, () => onAction?.call(DriverAction.arrived)));
        buttons.add(_dangerBtn(context, context.t("Can't complete"), () => onAction?.call(DriverAction.fail)));
        break;
      case DeliveryStatus.arrived:
        buttons.add(_primaryBtn(context, task.isPickup ? Icons.inventory_2_rounded : Icons.check_circle_rounded,
            context.t(task.isPickup ? 'Mark collected' : 'Complete delivery'), AppColors.success, () => onAction?.call(DriverAction.complete)));
        buttons.add(_dangerBtn(context, context.t("Can't complete"), () => onAction?.call(DriverAction.fail)));
        break;
      case DeliveryStatus.collected:
        buttons.add(_primaryBtn(context, Icons.storefront_rounded, context.t('Handed over at branch'), AppColors.primary, () => onAction?.call(DriverAction.dropOff)));
        break;
      case DeliveryStatus.droppedOff:
        buttons.add(Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hourglass_top_rounded, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Flexible(child: Text(context.t('Waiting for the branch to confirm receipt.'), style: TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600))),
        ]));
        break;
      default:
        break;
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }

  /// In-app navigation (map, live position, road route) — no hand-off to an external maps app.
  Future<void> _navigate(BuildContext context) {
    final toBranch = task.headingToBranch;
    return NavigationScreen.open(
      context,
      destination: toBranch ? LatLng(task.branchLat!, task.branchLng!) : LatLng(task.lat!, task.lng!),
      title: toBranch ? (task.branchName ?? context.t('Branch')) : (task.customerName ?? task.orderNumber ?? context.t('Destination')),
      subtitle: '${task.orderNumber ?? ''} · ${context.t(toBranch ? 'Drop off at branch' : (task.isPickup ? 'Collect from' : 'Deliver to'))}',
      address: toBranch ? task.branchName : task.address,
      phone: toBranch ? null : task.contactPhone,
      color: deliveryTypeColor(task.type),
    );
  }

  Future<void> _call(BuildContext context) =>
      _launch(context, Uri(scheme: 'tel', path: task.contactPhone), external: false);

  // Try to launch directly (don't pre-gate on canLaunchUrl, which false-negatives without
  // the right manifest <queries>); surface a toast only if it genuinely fails.
  Future<void> _launch(BuildContext context, Uri uri, {required bool external}) async {
    try {
      final ok = await launchUrl(uri, mode: external ? LaunchMode.externalApplication : LaunchMode.platformDefault);
      if (!ok && context.mounted) showToast(context, context.t('Could not open this on your device.'), error: true);
    } catch (_) {
      if (context.mounted) showToast(context, context.t('Could not open this on your device.'), error: true);
    }
  }

  Widget _primaryBtn(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) => ElevatedButton.icon(
        onPressed: busy ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(backgroundColor: color, minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16)),
      );

  Widget _dangerBtn(BuildContext context, String label, VoidCallback onTap) => OutlinedButton(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger), minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16)),
        child: Text(label),
      );

  Widget _ghostBtn(BuildContext context, IconData icon, String label, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: BorderSide(color: AppColors.line), minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 14)),
      );
}

/// Compact horizontal journey. Delivery: New → Accepted → In transit → Arrived → Done.
/// Pickup: … → Arrived → Collected → At branch → Received (the branch confirms receipt).
class _MiniJourney extends StatelessWidget {
  const _MiniJourney({required this.status, required this.type});
  final DeliveryStatus status;
  final DeliveryType type;

  static const _labels = ['New', 'Accepted', 'In transit', 'Arrived', 'Done'];
  static const _icons = [
    Icons.fiber_new_rounded,
    Icons.thumb_up_rounded,
    Icons.local_shipping_rounded,
    Icons.where_to_vote_rounded,
    Icons.check_circle_rounded,
  ];
  static const _pickupLabels = ['New', 'Accepted', 'In transit', 'Arrived', 'Collected', 'At branch', 'Received'];
  static const _pickupIcons = [
    Icons.fiber_new_rounded,
    Icons.thumb_up_rounded,
    Icons.local_shipping_rounded,
    Icons.where_to_vote_rounded,
    Icons.inventory_2_rounded,
    Icons.storefront_rounded,
    Icons.check_circle_rounded,
  ];

  bool get _pickup => type == DeliveryType.pickup;

  @override
  Widget build(BuildContext context) {
    final current = status.journeyIndexFor(type);
    final n = _pickup ? _pickupLabels.length : _labels.length;
    return Row(
      children: [
        for (var i = 0; i < n; i++) ...[
          _node(context, i, current, n),
          if (i < n - 1) Expanded(child: Container(height: 2.5, color: i < current ? AppColors.primary : AppColors.line)),
        ],
      ],
    );
  }

  Widget _node(BuildContext context, int i, int current, int n) {
    // The last node, once reached, is the finished state — done, not "active".
    final done = i < current || (i == current && i == n - 1);
    final active = i == current && !done;
    final labels = _pickup ? _pickupLabels : _labels;
    final icons = _pickup ? _pickupIcons : _icons;
    final size = n > 5 ? 26.0 : 30.0;
    final labelW = n > 5 ? 42.0 : 54.0;
    final color = done ? AppColors.primary : (active ? AppColors.gold : AppColors.line);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: active ? AppShadows.glow(AppColors.goldDark) : null),
        child: Icon(done ? Icons.check_rounded : icons[i], size: 15, color: done ? Colors.white : (active ? AppColors.onGold : AppColors.faint)),
      ),
      const SizedBox(height: 3),
      SizedBox(
        width: labelW,
        child: Text(context.t(labels[i]),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, fontWeight: active ? FontWeight.w800 : FontWeight.w500, color: (done || active) ? AppColors.ink : AppColors.faint)),
      ),
    ]);
  }
}
