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
    final c = statusColor(order.status);

    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [c.withValues(alpha: 0.16), c.withValues(alpha: 0.06)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(isPickup ? Icons.local_shipping_rounded : Icons.storefront_rounded, color: c, size: 22),
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
                        const SizedBox(width: 8),
                        const _ExpressTag(),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text('${order.itemCount} ${context.t(order.itemCount == 1 ? 'item' : 'items')} · ${df.format(order.createdAt)}',
                        style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              StatusChip(order.status, dense: true),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
          Row(
            children: [
              Text(money(order.total, currency, lang),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AppColors.ink)),
              const SizedBox(width: 10),
              PaymentChip(order.paymentStatus),
              const Spacer(),
              if (order.balanceDue > 0)
                Text('${context.t('Due')} ${money(order.balanceDue, currency, lang)}',
                    style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ],
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
      decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.bolt_rounded, size: 12, color: AppColors.goldDark),
        const SizedBox(width: 2),
        Text(context.t('Express'), style: const TextStyle(color: AppColors.goldDark, fontWeight: FontWeight.w800, fontSize: 10.5)),
      ]),
    );
  }
}
