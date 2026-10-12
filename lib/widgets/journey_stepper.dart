import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/enums.dart';
import '../theme/app_theme.dart';

class _Stage {
  const _Stage(this.label, this.icon, this.statuses);
  final String label;
  final IconData icon;
  final Set<OrderStatus> statuses;
}

/// The planned order journey as a vertical node stepper with connectors.
/// Two variants (Pickup & Delivery vs Walk-in), mirroring the web `pk-track`.
class JourneyStepper extends StatelessWidget {
  const JourneyStepper({super.key, required this.status, required this.type});
  final OrderStatus status;
  final OrderType type;

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

  static const _walkInJourney = [
    _Stage('Placed', Icons.receipt_long_rounded, {OrderStatus.draft, OrderStatus.placed}),
    _Stage('Cleaning', Icons.local_laundry_service_rounded,
        {OrderStatus.pickedUp, OrderStatus.atFacility, OrderStatus.inProcess}),
    _Stage('Ready', Icons.check_circle_rounded, {OrderStatus.ready, OrderStatus.outForDelivery}),
    _Stage('Collected', Icons.task_alt_rounded, {OrderStatus.delivered}),
  ];

  int _currentIndex(List<_Stage> stages) {
    for (var i = 0; i < stages.length; i++) {
      if (stages[i].statuses.contains(status)) return i;
    }
    // Unknown (e.g. cancelled/on-hold handled by the caller) → default to start.
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final stages = type == OrderType.walkIn ? _walkInJourney : _pickupJourney;
    final current = _currentIndex(stages);

    return Column(
      children: [
        for (var i = 0; i < stages.length; i++)
          _StageRow(
            stage: stages[i],
            state: i < current
                ? _NodeState.done
                : i == current
                    ? _NodeState.current
                    : _NodeState.upcoming,
            isLast: i == stages.length - 1,
          ),
      ],
    );
  }
}

enum _NodeState { done, current, upcoming }

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.state, required this.isLast});
  final _Stage stage;
  final _NodeState state;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final done = state == _NodeState.done;
    final current = state == _NodeState.current;
    final nodeColor = done
        ? AppColors.primary
        : current
            ? AppColors.gold
            : AppColors.line;
    final iconColor = done ? Colors.white : (current ? AppColors.onGold : AppColors.faint);
    final connectorColor = done ? AppColors.primary : AppColors.line;

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
                      fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 14.5,
                      color: (done || current) ? AppColors.ink : AppColors.faint,
                    ),
                  ),
                  if (current) ...[
                    const SizedBox(height: 2),
                    Text(context.t('In progress'),
                        style: const TextStyle(color: AppColors.goldDark, fontSize: 12, fontWeight: FontWeight.w600)),
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
