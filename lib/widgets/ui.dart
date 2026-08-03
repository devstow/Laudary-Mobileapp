import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/enums.dart';
import '../theme/app_theme.dart';

/// Format money in the given ISO currency code (e.g. "SAR 150.00"), digits localized.
String money(double amount, String currency, String lang) {
  final f = NumberFormat.currency(locale: lang == 'ar' ? 'ar' : 'en', symbol: '$currency ', decimalDigits: 2);
  return f.format(amount);
}

// ─────────────────────────────────────────────────────────────────────────────
// Status visuals (single source of truth for colour + icon per order status).
// ─────────────────────────────────────────────────────────────────────────────

Color statusColor(OrderStatus s) {
  switch (s.phase) {
    case OrderPhase.done:
      return AppColors.success;
    case OrderPhase.cancelled:
      return AppColors.danger;
    case OrderPhase.ready:
      return AppColors.primary;
    case OrderPhase.active:
      return AppColors.warning;
    case OrderPhase.pending:
      return AppColors.info;
  }
}

IconData statusIcon(OrderStatus s) {
  switch (s) {
    case OrderStatus.draft:
    case OrderStatus.placed:
      return Icons.receipt_long_rounded;
    case OrderStatus.pickupScheduled:
      return Icons.event_available_rounded;
    case OrderStatus.pickedUp:
      return Icons.local_shipping_rounded;
    case OrderStatus.atFacility:
      return Icons.factory_rounded;
    case OrderStatus.inProcess:
      return Icons.local_laundry_service_rounded;
    case OrderStatus.ready:
      return Icons.check_circle_rounded;
    case OrderStatus.outForDelivery:
      return Icons.delivery_dining_rounded;
    case OrderStatus.delivered:
      return Icons.task_alt_rounded;
    case OrderStatus.cancelled:
      return Icons.cancel_rounded;
    case OrderStatus.onHold:
      return Icons.pause_circle_rounded;
  }
}

/// Colour + label pill for an order status.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});
  final OrderStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 5 : 6),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(status), color: c, size: dense ? 13 : 15),
          const SizedBox(width: 5),
          Text(context.t(status.label),
              style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: dense ? 11.5 : 12.5)),
        ],
      ),
    );
  }
}

class PaymentChip extends StatelessWidget {
  const PaymentChip(this.status, {super.key});
  final PaymentStatus status;
  @override
  Widget build(BuildContext context) {
    final color = status == PaymentStatus.paid
        ? AppColors.success
        : status == PaymentStatus.partial
            ? AppColors.warning
            : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(context.t(status.label), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Surfaces & structure
// ─────────────────────────────────────────────────────────────────────────────

/// The standard rounded white card with a soft lift.
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap, this.color});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.soft,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(AppRadius.card), onTap: onTap, child: card),
    );
  }
}

/// A gradient brand hero header (rounded bottom), used behind screen titles.
class BrandHero extends StatelessWidget {
  const BrandHero({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: child,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(actionLabel!),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ]),
          ),
      ],
    );
  }
}

/// Label + value row for detail cards.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, required this.value, this.valueColor, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: AppColors.muted),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(color: AppColors.muted, fontSize: 13.5))),
        const SizedBox(width: 12),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end,
              style: TextStyle(color: valueColor ?? AppColors.ink, fontWeight: FontWeight.w700, fontSize: 13.5)),
        ),
        if (onTap != null) ...[const SizedBox(width: 4), Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.faint)],
      ]),
    );
    if (onTap == null) return row;
    return InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: row);
  }
}

/// Money summary row (Subtotal / VAT / Total …).
class MoneyRow extends StatelessWidget {
  const MoneyRow(this.label, this.value, {super.key, this.strong = false, this.accent = false});
  final String label;
  final String value;
  final bool strong;
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final size = strong ? 17.0 : 14.0;
    final color = accent ? AppColors.primary : AppColors.ink;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: strong ? 4 : 5),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: strong ? AppColors.ink : AppColors.muted,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                  fontSize: strong ? 15 : 14)),
        ),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filters
// ─────────────────────────────────────────────────────────────────────────────

class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.selected, required this.onTap, this.count});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: selected ? AppColors.primary : AppColors.line),
          boxShadow: selected ? AppShadows.glow(AppColors.primary) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : AppColors.inkSoft, fontWeight: FontWeight.w700, fontSize: 13)),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? Colors.white24 : AppColors.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: selected ? Colors.white : AppColors.primary, fontWeight: FontWeight.w800, fontSize: 11)),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// State views: loading (skeleton), error, empty
// ─────────────────────────────────────────────────────────────────────────────

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(strokeWidth: 2.6)));
}

/// A shimmering placeholder box.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height = 16, this.width = double.infinity, this.radius = 8});
  final double height;
  final double width;
  final double radius;
  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t), 0),
              colors: [AppColors.lineSoft, AppColors.line, AppColors.lineSoft],
            ),
          ),
        );
      },
    );
  }
}

/// A few skeleton cards to fill a list while loading.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4});
  final int count;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SoftCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Row(children: [
                SkeletonBox(height: 42, width: 42, radius: 12),
                SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SkeletonBox(height: 14, width: 120),
                    SizedBox(height: 8),
                    SkeletonBox(height: 11, width: 80),
                  ]),
                ),
              ]),
              SizedBox(height: 16),
              SkeletonBox(height: 12),
            ]),
          ),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: const Icon(Icons.cloud_off_rounded, size: 34, color: AppColors.danger),
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 14.5)),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 160,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.t('Retry')),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.message, {super.key, this.icon = Icons.inbox_rounded, this.hint});
  final String message;
  final IconData icon;
  final String? hint;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
            child: Icon(icon, size: 42, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w700)),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
          ],
        ]),
      ),
    );
  }
}

/// A snackbar helper with success/error tone.
void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: error ? AppColors.danger : AppColors.ink,
    ));
}
