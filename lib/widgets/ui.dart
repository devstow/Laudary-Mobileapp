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

/// Colour + label pill for an order status (Claundry-style soft tinted badge).
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});
  final OrderStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 9 : 11, vertical: dense ? 4 : 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(status), color: c, size: dense ? 12.5 : 14),
          const SizedBox(width: 5),
          Text(context.t(status.label),
              style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: dense ? 11 : 12, letterSpacing: 0.1)),
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
      child: Text(context.t(status.label), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Surfaces & structure
// ─────────────────────────────────────────────────────────────────────────────

/// The standard rounded white card with a soft blue-tinted lift.
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
        border: Border.all(color: AppColors.lineSoft),
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

/// The blue brand hero header (rounded bottom, soft decorative rings), used behind
/// screen titles — the Claundry "delivery card" look.
class BrandHero extends StatelessWidget {
  const BrandHero({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24), this.borderRadius});
  final Widget child;
  final EdgeInsets padding;

  /// Defaults to a rounded bottom (full-bleed header); pass a full radius for an in-page card.
  final BorderRadius? borderRadius;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: Stack(
          children: [
            // Decorative washing-machine-door rings, like the reference's promo art.
            PositionedDirectional(end: -60, top: -50, child: _ring(190, 0.10)),
            PositionedDirectional(end: 30, bottom: -70, child: _ring(130, 0.07)),
            PositionedDirectional(start: -40, bottom: -60, child: _ring(110, 0.05)),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }

  static Widget _ring(double size, double alpha) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: alpha * 2.2), width: 14),
            color: Colors.white.withValues(alpha: alpha * 0.6),
          ),
        ),
      );
}

/// A rounded, bordered square icon button — the reference's app-bar action style.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({super.key, required this.icon, required this.onTap, this.tooltip, this.onDark = false});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  /// True when placed on the blue hero (white glass style).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: onDark ? Colors.white.withValues(alpha: 0.18) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: onDark ? Colors.white.withValues(alpha: 0.22) : AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 21, color: onDark ? Colors.white : AppColors.ink),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
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
        Expanded(
          child: Text(title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.ink)),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: const Size(44, 36),
              foregroundColor: AppColors.muted,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            child: Text(actionLabel!),
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(color: AppColors.muted, fontSize: 13.5, fontWeight: FontWeight.w500))),
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
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.brandGradient : null,
          color: selected ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: selected ? Colors.transparent : AppColors.line),
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
                color: selected ? AppColors.gold : AppColors.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: selected ? AppColors.onGold : AppColors.primary, fontWeight: FontWeight.w800, fontSize: 11)),
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
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, boxShadow: AppShadows.soft),
            child: const CircularProgressIndicator(strokeWidth: 2.6, strokeCap: StrokeCap.round),
          ),
        ),
      );
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
              colors: [AppColors.lineSoft, AppColors.primarySoft, AppColors.lineSoft],
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
                SkeletonBox(height: 46, width: 46, radius: 14),
                SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SkeletonBox(height: 14, width: 130),
                    SizedBox(height: 8),
                    SkeletonBox(height: 11, width: 84),
                  ]),
                ),
                SkeletonBox(height: 22, width: 64, radius: 8),
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
          _IllustrationBadge(icon: Icons.cloud_off_rounded, color: AppColors.danger),
          const SizedBox(height: 18),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.4)),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 170,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.t('Retry')),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
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
          _IllustrationBadge(icon: icon, color: AppColors.primary),
          const SizedBox(height: 18),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w800)),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.4)),
          ],
        ]),
      ),
    );
  }
}

/// Concentric soft circles with an icon — the reference's "washing machine door"
/// illustration language for empty / error states.
class _IllustrationBadge extends StatelessWidget {
  const _IllustrationBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.18), width: 3),
          boxShadow: AppShadows.soft,
        ),
        child: Icon(icon, size: 38, color: color),
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
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: error ? Colors.white : AppColors.success, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: error ? AppColors.danger : null,
    ));
}

// ─────────────────────────────────────────────────────────────────────────────
// Buttons & banners
// ─────────────────────────────────────────────────────────────────────────────

/// Full-width gradient call-to-action (Claundry "Log in" / "Checkout" button).
/// Shows a spinner while [busy]; disabled when [onPressed] is null.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon, this.amber = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  /// Amber accent variant (secondary emphasis CTAs).
  final bool amber;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final fg = amber ? AppColors.onGold : Colors.white;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled || busy ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: amber ? AppColors.goldGradient : AppColors.brandGradient,
          borderRadius: BorderRadius.circular(AppRadius.control),
          boxShadow: enabled ? AppShadows.glow(amber ? AppColors.goldDark : AppColors.primary) : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 54,
              width: double.infinity,
              child: Center(
                child: busy
                    ? SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 8)],
                        Flexible(
                          child: Text(label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: fg, fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                        ),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline error message box (forms / requests).
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline_rounded, size: 19, color: AppColors.danger),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, height: 1.35))),
      ]),
    );
  }
}
