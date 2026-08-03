import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/notification.dart';
import '../../services/api_exception.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import '../orders/order_details_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.onOpen});

  /// Optional custom "open" handler (e.g. the driver routes to a task instead of customer
  /// order-tracking). Called after the notification is marked read. When null, the default
  /// customer behavior applies (tap → order tracking via the url's order id).
  final Future<void> Function(AppNotification item)? onOpen;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<AppNotification>> _future;
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = context.read<NotificationService>().all();

  Future<void> _markAll() async {
    await context.read<NotificationService>().markAllRead();
    if (mounted) setState(_reload);
  }

  Future<void> _clearAll() async {
    await context.read<NotificationService>().clearAll();
    if (mounted) setState(_reload);
  }

  /// Mark the notification read, then — if it points to an order — open that order's
  /// tracking page. Refreshes the list on return so the read state updates.
  Future<void> _open(AppNotification item) async {
    if (!item.isRead) {
      await context.read<NotificationService>().markRead(item.id);
      if (mounted) setState(_reload);
    }
    if (!mounted) return;
    // Role-specific routing (driver → task) when provided.
    if (widget.onOpen != null) {
      await widget.onOpen!(item);
      if (mounted) setState(_reload);
      return;
    }
    // Default (customer): open the order's tracking page.
    final oid = item.orderId;
    if (oid == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailsScreen(orderId: oid)));
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Notifications')),
        actions: [
          IconButton(tooltip: context.t('Mark all read'), onPressed: _markAll, icon: const Icon(Icons.done_all_rounded)),
          IconButton(tooltip: context.t('Clear all'), onPressed: _clearAll, icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_reload);
          await _future;
        },
        child: FutureBuilder<List<AppNotification>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: const [SkeletonList(count: 6)],
              );
            }
            if (snap.hasError) {
              return ErrorView(ApiException.from(snap.error!).message, onRetry: () => setState(_reload));
            }
            final all = snap.data ?? const <AppNotification>[];
            final unreadCount = all.where((n) => !n.isRead).length;
            final items = _unreadOnly ? all.where((n) => !n.isRead).toList() : all;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Row(children: [
                  FilterPill(
                    label: context.t('All'),
                    selected: !_unreadOnly,
                    count: all.length,
                    onTap: () => setState(() => _unreadOnly = false),
                  ),
                  const SizedBox(width: 10),
                  FilterPill(
                    label: context.t('Unread'),
                    selected: _unreadOnly,
                    count: unreadCount,
                    onTap: () => setState(() => _unreadOnly = true),
                  ),
                ]),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: EmptyView(
                      _unreadOnly ? context.t('No unread notifications') : context.t('No notifications'),
                      icon: Icons.notifications_off_rounded,
                    ),
                  )
                else
                  ...items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _NotificationTile(
                          item: item,
                          time: _relativeTime(context, item.createdAt),
                          onTap: () => _open(item),
                          onTrack: item.orderId != null ? () => _open(item) : null,
                        ),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Compact relative time: "just now", "5m ago", "3h ago", "2d ago", else a date.
String _relativeTime(BuildContext context, DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return context.t('just now');
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ${context.t('ago')}';
  if (diff.inHours < 24) return '${diff.inHours}h ${context.t('ago')}';
  if (diff.inDays < 7) return '${diff.inDays}d ${context.t('ago')}';
  return '${dt.day}/${dt.month}/${dt.year}';
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.time, required this.onTap, this.onTrack});
  final AppNotification item;
  final String time;
  final VoidCallback onTap;
  final VoidCallback? onTrack;

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(item.color);
    return SoftCard(
      onTap: onTap,
      color: item.isRead ? AppColors.surface : accent.withValues(alpha: 0.06),
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Icon(_iconFor(item.icon), color: accent, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: item.isRead ? FontWeight.w700 : FontWeight.w800,
                    color: AppColors.ink,
                    fontSize: 14.5,
                  ),
                ),
              ),
              if (!item.isRead) ...[
                const SizedBox(width: 8),
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
              ],
            ]),
            if (item.body != null && item.body!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(item.body!, style: TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.35)),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Text(time, style: TextStyle(color: AppColors.faint, fontSize: 11.5, fontWeight: FontWeight.w600)),
              if (onTrack != null) ...[
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  onTap: onTrack,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.travel_explore_rounded, size: 15, color: AppColors.primary),
                      const SizedBox(width: 5),
                      Text(context.t('Track order'),
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12)),
                    ]),
                  ),
                ),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Map a server colour hint ("#RRGGBB", "success", "warning"…) to a palette colour.
Color _accentColor(String hint) {
  final h = hint.trim().toLowerCase();
  switch (h) {
    case 'success':
    case 'green':
      return AppColors.success;
    case 'warning':
    case 'orange':
    case 'yellow':
      return AppColors.warning;
    case 'danger':
    case 'error':
    case 'red':
      return AppColors.danger;
    case 'info':
    case 'blue':
      return AppColors.info;
    case 'gold':
      return AppColors.gold;
  }
  if (h.startsWith('#') && (h.length == 7 || h.length == 4)) {
    var hex = h.substring(1);
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return AppColors.primary;
}

/// Map a server icon hint to a Material icon, defaulting to a bell.
IconData _iconFor(String hint) {
  final h = hint.trim().toLowerCase();
  if (h.contains('truck') || h.contains('delivery') || h.contains('shipping')) return Icons.local_shipping_rounded;
  if (h.contains('check') || h.contains('done') || h.contains('ready')) return Icons.check_circle_rounded;
  if (h.contains('cash') || h.contains('pay') || h.contains('money') || h.contains('wallet')) return Icons.payments_rounded;
  if (h.contains('receipt') || h.contains('order') || h.contains('invoice')) return Icons.receipt_long_rounded;
  if (h.contains('calendar') || h.contains('clock') || h.contains('schedule')) return Icons.event_available_rounded;
  if (h.contains('alert') || h.contains('warning')) return Icons.warning_amber_rounded;
  if (h.contains('wash') || h.contains('laundry')) return Icons.local_laundry_service_rounded;
  return Icons.notifications_rounded;
}
