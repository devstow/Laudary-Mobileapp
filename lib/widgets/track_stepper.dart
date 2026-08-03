import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/enums.dart';
import '../theme/app_theme.dart';

class _Step {
  const _Step(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The public-tracking stepper — 5 fixed stages with status collapsing, exactly like the
/// web `Track/Index` page (distinct from the richer 8-stage Details JourneyStepper).
class TrackStepper extends StatelessWidget {
  const TrackStepper({super.key, required this.status});
  final OrderStatus status;

  static const _steps = [
    _Step('Order placed', Icons.assignment_turned_in_rounded),
    _Step('In process', Icons.local_laundry_service_rounded),
    _Step('Ready', Icons.check_circle_rounded),
    _Step('Out for delivery', Icons.delivery_dining_rounded),
    _Step('Delivered', Icons.home_rounded),
  ];

  /// Same collapse as the web `StageIndex`.
  int get _current {
    switch (status) {
      case OrderStatus.delivered:
        return 4;
      case OrderStatus.outForDelivery:
        return 3;
      case OrderStatus.ready:
        return 2;
      case OrderStatus.inProcess:
      case OrderStatus.atFacility:
      case OrderStatus.pickedUp:
        return 1;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++)
          _row(context, _steps[i], i < current ? _S.done : (i == current ? _S.active : _S.future), i == _steps.length - 1),
      ],
    );
  }

  Widget _row(BuildContext context, _Step step, _S state, bool isLast) {
    final done = state == _S.done;
    final active = state == _S.active;
    final nodeColor = done
        ? AppColors.success
        : active
            ? AppColors.primary
            : AppColors.line;
    final iconColor = (done || active) ? Colors.white : AppColors.faint;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: nodeColor,
                shape: BoxShape.circle,
                boxShadow: active ? AppShadows.glow(AppColors.primary) : null,
                border: active ? Border.all(color: AppColors.primarySoft, width: 3) : null,
              ),
              child: Icon(done ? Icons.check_rounded : step.icon, size: 18, color: iconColor),
            ),
            if (!isLast)
              Expanded(child: Container(width: 2.5, margin: const EdgeInsets.symmetric(vertical: 2), color: done ? AppColors.success : AppColors.line)),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 7, bottom: isLast ? 0 : 18),
              child: Text(
                context.t(step.label),
                style: TextStyle(
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14.5,
                  color: (done || active) ? AppColors.ink : AppColors.faint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _S { done, active, future }
