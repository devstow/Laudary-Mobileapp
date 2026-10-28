import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/enums.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';

class _Stage {
  const _Stage(this.label, this.icon, this.statuses);
  final String label;
  final IconData icon;
  final Set<OrderStatus> statuses;
}

/// The planned order journey as a vertical node stepper with connectors.
/// Variants: driver pickup & delivery, customer drop-off & delivery, and walk-in — mirroring
/// the web `pk-track`. Each reached stage shows WHEN it happened (from the order timeline).
/// The final stage (Delivered / Collected) is a finished state: once reached it shows as
/// done with "Completed", never as "In progress".
class JourneyStepper extends StatelessWidget {
  const JourneyStepper({
    super.key,
    required this.status,
    required this.type,
    this.pickupMethod = PickupMethod.driverPickup,
    this.events = const [],
  });
  final OrderStatus status;
  final OrderType type;
  final PickupMethod pickupMethod;

  /// The customer-visible order timeline (used for the per-stage timestamps).
  final List<OrderEvent> events;

  static const _pickupJourney = [
    _Stage('Placed', Icons.receipt_long_rounded, {OrderStatus.draft, OrderStatus.placed}),
    _Stage('Pickup', Icons.event_available_rounded, {OrderStatus.pickupScheduled}),
    _Stage('Collected', Icons.local_shipping_rounded, {OrderStatus.pickedUp}),
    _Stage('At facility', Icons.factory_rounded, {OrderStatus.atFacility}),
    _Stage('Cleaning', Icons.local_laundry_service_rounded, {OrderStatus.inProcess}),
    _Stage('Ready', Icons.check_circle_rounded, {OrderStatus.ready}),
    _Stage('On its way', Icons.delivery_dining_rounded, {OrderStatus.outForDelivery}),
    _Stage('Delivered', Icons.task_alt_rounded, {OrderStatus.delivered}),
  ];

  static const _dropOffJourney = [
    _Stage('Placed', Icons.receipt_long_rounded, {OrderStatus.draft, OrderStatus.placed}),
    _Stage('Received at branch', Icons.storefront_rounded, {OrderStatus.atFacility}),
    _Stage('Cleaning', Icons.local_laundry_service_rounded, {OrderStatus.inProcess}),
    _Stage('Ready', Icons.check_circle_rounded, {OrderStatus.ready}),
    _Stage('On its way', Icons.delivery_dining_rounded, {OrderStatus.outForDelivery}),
    _Stage('Delivered', Icons.task_alt_rounded, {OrderStatus.delivered}),
  ];

  static const _walkInJourney = [
    _Stage('Placed', Icons.receipt_long_rounded, {OrderStatus.draft, OrderStatus.placed}),
    _Stage('Cleaning', Icons.local_laundry_service_rounded,
        {OrderStatus.pickedUp, OrderStatus.atFacility, OrderStatus.inProcess}),
    _Stage('Ready', Icons.check_circle_rounded, {OrderStatus.ready, OrderStatus.outForDelivery}),
    _Stage('Collected', Icons.task_alt_rounded, {OrderStatus.delivered}),
  ];

  List<_Stage> get _stages {
    if (type == OrderType.walkIn) return _walkInJourney;
    return pickupMethod == PickupMethod.customerDropOff ? _dropOffJourney : _pickupJourney;
  }

  int _currentIndex(List<_Stage> stages) {
    for (var i = 0; i < stages.length; i++) {
      if (stages[i].statuses.contains(status)) return i;
    }
    // Unknown (e.g. cancelled/on-hold handled by the caller) → default to start.
    return 0;
  }

  /// When the order first reached a stage (earliest event INTO one of its statuses).
  DateTime? _reachedAt(_Stage s) {
    DateTime? at;
    for (final e in events) {
      if (!s.statuses.contains(e.toStatus)) continue;
      if (e.fromStatus != null && s.statuses.contains(e.fromStatus)) continue; // a note within the stage
      if (at == null || e.occurredAt.isBefore(at)) at = e.occurredAt;
    }
    return at;
  }

  @override
  Widget build(BuildContext context) {
    final stages = _stages;
    final current = _currentIndex(stages);
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final df = DateFormat('d MMM, HH:mm', lang);

    return Column(
      children: [
        for (var i = 0; i < stages.length; i++)
          _StageRow(
            stage: stages[i],
            // The last stage, once reached, is the end of the journey → done, not "in progress".
            state: i < current || (i == current && i == stages.length - 1)
                ? _NodeState.done
                : i == current
                    ? _NodeState.current
                    : _NodeState.upcoming,
            isLast: i == stages.length - 1,
            isFinal: i == current && i == stages.length - 1,
            time: i <= current ? _reachedAt(stages[i]) : null,
            df: df,
          ),
      ],
    );
  }
}

enum _NodeState { done, current, upcoming }

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.state, required this.isLast, required this.isFinal, required this.df, this.time});
  final _Stage stage;
  final _NodeState state;
  final bool isLast;
  final bool isFinal;
  final DateTime? time;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final done = state == _NodeState.done;
    final current = state == _NodeState.current;
    final nodeColor = isFinal
        ? AppColors.success
        : done
            ? AppColors.primary
            : current
                ? AppColors.gold
                : AppColors.line;
    final iconColor = (done || isFinal) ? Colors.white : (current ? AppColors.onGold : AppColors.faint);
    final connectorColor = done ? AppColors.primary : AppColors.line;

    // Sub-line: "Completed · 12 Oct, 14:05" for the finished journey, "In progress · …" for the
    // current stage, and just the time a past stage was reached otherwise.
    String? sub;
    var subColor = AppColors.muted;
    if (isFinal) {
      sub = context.t('Completed');
      subColor = AppColors.success;
    } else if (current) {
      sub = context.t('In progress');
      subColor = AppColors.goldDark;
    }
    final when = time == null ? null : df.format(time!);
    final subText = [?sub, ?when].join(' · ');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: nodeColor,
                  shape: BoxShape.circle,
                  boxShadow: current ? AppShadows.glow(AppColors.goldDark) : null,
                  border: current ? Border.all(color: AppColors.goldSoft, width: 3) : null,
                ),
                child: Icon(done ? Icons.check_rounded : stage.icon, size: 19, color: iconColor),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2.5, margin: const EdgeInsets.symmetric(vertical: 2), color: connectorColor),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 8, bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(stage.label),
                    style: TextStyle(
                      fontWeight: (current || isFinal) ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 14.5,
                      color: (done || current) ? AppColors.ink : AppColors.faint,
                    ),
                  ),
                  if (subText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subText, style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
