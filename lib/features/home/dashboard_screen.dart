import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../services/api_exception.dart';
import '../../services/notification_service.dart';
import '../../services/order_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/order_card.dart';
import '../../widgets/ui.dart';
import '../notifications/notifications_screen.dart';
import '../orders/orders_screen.dart';
import '../track/track_screen.dart';
import '../orders/order_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onNewPickup});
  final VoidCallback onNewPickup;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  late Future<CustomerOrderPage> _future;
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = context.read<OrderService>().myOrders(pageSize: 100);
    _loadUnread();
    // Poll the unread count so the bell badge updates on its own when a new
    // notification arrives — same approach as the web bell (which polls ~25s).
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _loadUnread());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh immediately when the app returns to the foreground.
    if (state == AppLifecycleState.resumed) _loadUnread();
  }

  Future<void> _refresh() async {
    setState(() => _future = context.read<OrderService>().myOrders(pageSize: 100));
    _loadUnread();
    await _future;
  }

  Future<void> _loadUnread() async {
    try {
      final n = await context.read<NotificationService>().unreadCount();
      if (mounted && n != _unread) setState(() => _unread = n); // only rebuild when it changes
    } catch (_) {/* best-effort */}
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    _loadUnread(); // refresh the badge after the user views/clears notifications
  }

  int _count(CustomerOrderPage p, Set<OrderStatus> statuses) {
    var n = 0;
    p.statusCounts.forEach((k, v) {
      if (statuses.contains(k)) n += v;
    });
    return n;
  }

  int _active(CustomerOrderPage p) {
    var n = 0;
    p.statusCounts.forEach((k, v) {
      if (k.phase != OrderPhase.done && k.phase != OrderPhase.cancelled) n += v;
    });
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final name = (app.user?.fullName ?? '').split(' ').first;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<CustomerOrderPage>(
          future: _future,
          builder: (context, snap) {
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                _Header(name: name, tenant: app.tenantName ?? '', logoUrl: app.tenantLogoUrl, unread: _unread, onBell: _openNotifications),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
                  child: Builder(builder: (context) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(padding: EdgeInsets.only(top: 8), child: SkeletonList(count: 3));
                    }
                    if (snap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: ErrorView(ApiException.from(snap.error!).message, onRetry: _refresh),
                      );
                    }
                    final p = snap.data!;
                    final activeOrders = p.items
                        .where((o) => o.status.phase != OrderPhase.done && o.status.phase != OrderPhase.cancelled)
                        .take(5)
                        .toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // KPI grid
                        Row(children: [
                          Expanded(child: _Kpi(icon: Icons.pending_actions_rounded, color: AppColors.info, value: '${_active(p)}', label: context.t('Active orders'))),
                          const SizedBox(width: 12),
                          Expanded(child: _Kpi(icon: Icons.local_laundry_service_rounded, color: AppColors.warning, value: '${_count(p, {OrderStatus.pickedUp, OrderStatus.atFacility, OrderStatus.inProcess})}', label: context.t('In cleaning'))),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: _Kpi(icon: Icons.check_circle_rounded, color: AppColors.primary, value: '${_count(p, {OrderStatus.ready, OrderStatus.outForDelivery})}', label: context.t('Ready / on the way'))),
                          const SizedBox(width: 12),
                          Expanded(child: _Kpi(icon: Icons.receipt_long_rounded, color: AppColors.gold, value: '${p.allCount}', label: context.t('Total orders'))),
                        ]),
                        const SizedBox(height: 18),

                        _BookPickupCta(onTap: widget.onNewPickup),
                        const SizedBox(height: 14),

                        // Quick actions
                        Row(children: [
                          Expanded(child: _QuickAction(icon: Icons.travel_explore_rounded, label: context.t('Track'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrackScreen())))),
                          const SizedBox(width: 12),
                          Expanded(child: _QuickAction(icon: Icons.notifications_none_rounded, label: context.t('Alerts'), onTap: _openNotifications)),
                          const SizedBox(width: 12),
                          Expanded(child: _QuickAction(icon: Icons.receipt_long_outlined, label: context.t('My Orders'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersScreen())))),
                        ]),
                        const SizedBox(height: 24),

                        SectionHeader(context.t('Active orders'),
                            actionLabel: p.allCount > activeOrders.length ? context.t('View all') : null,
                            onAction: p.allCount > activeOrders.length
                                ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersScreen()))
                                : null),
                        const SizedBox(height: 12),
                        if (activeOrders.isEmpty)
                          EmptyView(context.t('No active orders'),
                              icon: Icons.local_laundry_service_rounded, hint: context.t('Book a pickup to get started'))
                        else
                          ...activeOrders.map((o) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: OrderCard(o, onTap: () async {
                                  await Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => OrderDetailsScreen(orderId: o.id, orderNumber: o.orderNumber)));
                                  if (context.mounted) _refresh();
                                }),
                              )),
                      ],
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.tenant, required this.unread, required this.onBell, this.logoUrl});
  final String name;
  final String tenant;
  final int unread;
  final VoidCallback onBell;
  final String? logoUrl;
  @override
  Widget build(BuildContext context) {
    final hasLogo = logoUrl != null && logoUrl!.isNotEmpty;
    return BrandHero(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 20, 26),
      child: Row(
        children: [
          if (hasLogo) ...[
            Container(
              width: 40, height: 40, padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(11)),
              child: Image.network(logoUrl!, fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(Icons.local_laundry_service_rounded, color: AppColors.primary, size: 22)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${context.t('Hello')}${name.isEmpty ? '' : ', $name'} 👋',
                    style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.storefront_rounded, color: Colors.white70, size: 15),
                  const SizedBox(width: 5),
                  Flexible(child: Text(tenant, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13.5))),
                ]),
              ],
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: Colors.white.withValues(alpha: 0.18),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onBell,
                  child: const Padding(padding: EdgeInsets.all(11), child: Icon(Icons.notifications_none_rounded, color: Colors.white, size: 24)),
                ),
              ),
              if (unread > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.primaryDark, width: 1.5),
                    ),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, height: 1.1),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.icon, required this.color, required this.value, required this.label});
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 19),
            ),
            const Spacer(),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ]),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.2)),
        ],
      ),
    );
  }
}

class _BookPickupCta extends StatelessWidget {
  const _BookPickupCta({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.goldGradient,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.glow(AppColors.gold),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('Book a pickup'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.5)),
              const SizedBox(height: 2),
              Text(context.t('We collect, clean & deliver'), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ]),
          ),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white),
        ]),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(height: 8),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.ink)),
      ]),
    );
  }
}
