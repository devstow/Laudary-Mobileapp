import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/enums.dart';
import '../models/order.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// A premium order summary card used across dashboard, orders and payments.
class OrderCard extends StatelessWidget {
  const OrderCard(this.order, {super.key, this.onTap});
  final OrderListItem order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final currency = context.watch<AppState>().currency; // tenant currency, like the web
    final df = DateFormat('d MMM · HH:mm', lang);
    final isPickup = order.type == OrderType.pickupAndDelivery;

    return SoftCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(14)),
                  child: Icon(isPickup ? Icons.local_shipping_rounded : Icons.storefront_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(order.orderNumber,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink)),
                        ),
                        if (order.speed == ServiceSpeed.express) ...[
                          const SizedBox(width: 6),
                          const _ExpressTag(),
                        ],
                      ]),
                      const SizedBox(height: 4),
                      Text('${order.itemCount} ${context.t(order.itemCount == 1 ? 'item' : 'items')}',
                          style: TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(order.status, dense: true),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border(top: BorderSide(color: AppColors.lineSoft)),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_month_rounded, size: 14, color: AppColors.faint),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(df.format(order.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                if (order.balanceDue > 0) ...[
                  Text('${context.t('Due')} ${money(order.balanceDue, currency, lang)}',
                      style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 11.5)),
                  const SizedBox(width: 8),
                ] else ...[
                  PaymentChip(order.paymentStatus),
                  const SizedBox(width: 8),
                ],
                Text(money(order.total, currency, lang),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpressTag extends StatelessWidget {
  const _ExpressTag();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.bolt_rounded, size: 12, color: AppColors.onGold),
        const SizedBox(width: 2),
        Text(context.t('Express'), style: const TextStyle(color: AppColors.onGold, fontWeight: FontWeight.w800, fontSize: 10.5)),
      ]),
    );
  }
}
