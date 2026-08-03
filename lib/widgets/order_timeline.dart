import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/enums.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Chronological activity log of an order's status events — mirrors the web
/// `_OrderTimeline.cshtml` exactly: oldest-first, customer-friendly labels,
/// web point colours, "MMM d, HH:mm" timestamps, and a "by {actor} · {Source}" line.
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.events});
  final List<OrderEvent> events;

  /// Customer-friendly label override (only AtFacility differs), like the web partial.
  static String label(BuildContext context, OrderStatus s) =>
      s == OrderStatus.atFacility ? context.t('At the laundry') : context.t(s.label);

  /// Web point colour: Delivered → success, Cancelled/OnHold → danger, else primary.
  static Color pointColor(OrderStatus s) {
    if (s == OrderStatus.delivered) return AppColors.success;
    if (s == OrderStatus.cancelled || s == OrderStatus.onHold) return AppColors.danger;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final df = DateFormat('MMM d, HH:mm', lang);
    // Oldest-first (ascending), exactly like the web timeline.
    final sorted = [...events]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return Column(
      children: [
        for (var i = 0; i < sorted.length; i++)
          _EventRow(event: sorted[i], isLast: i == sorted.length - 1, dateText: df.format(sorted[i].occurredAt)),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.isLast, required this.dateText});
  final OrderEvent event;
  final bool isLast;
  final String dateText;

  @override
  Widget build(BuildContext context) {
    final c = OrderTimeline.pointColor(event.toStatus);
    final hasActor = (event.actorName ?? '').trim().isNotEmpty;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(statusIcon(event.toStatus), size: 15, color: c),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: AppColors.line)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(OrderTimeline.label(context, event.toStatus),
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
                      ),
                      const SizedBox(width: 8),
                      Text(dateText, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                  if (event.note != null && event.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                      child: Text(event.note!, style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5, height: 1.35)),
                    ),
                  ],
                  if (hasActor) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${context.t('by')} ${event.actorName}${event.source != null ? ' · ${context.t(event.source!.label)}' : ''}',
                      style: TextStyle(color: AppColors.faint, fontSize: 11.5, fontStyle: FontStyle.italic),
                    ),
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
