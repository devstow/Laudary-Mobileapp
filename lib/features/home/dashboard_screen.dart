import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/ai.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../services/api_exception.dart';
import '../../services/notification_service.dart';
import '../../services/order_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/order_card.dart';
import '../../widgets/ui.dart';
import '../assistant/assistant_screen.dart';
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

    void openTrack() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrackScreen()));
    void openOrders() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersScreen()));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<CustomerOrderPage>(
          future: _future,
          builder: (context, snap) {
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                _Header(
                  name: name,
                  fullName: app.user?.fullName ?? '',
                  tenant: app.tenantName ?? '',
                  logoUrl: app.tenantLogoUrl,
                  unread: _unread,
                  onBell: _openNotifications,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: _PromoBanner(onTap: widget.onNewPickup),
                ),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SectionHeader(context.t('Quick actions')),
                    const SizedBox(height: 12),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _CategoryTile(icon: Icons.add_box_rounded, label: context.t('Book a pickup'), highlight: true, onTap: widget.onNewPickup)),
                      const SizedBox(width: 10),
                      Expanded(child: _CategoryTile(icon: Icons.travel_explore_rounded, label: context.t('Track'), onTap: openTrack)),
                      const SizedBox(width: 10),
                      Expanded(child: _CategoryTile(icon: Icons.receipt_long_rounded, label: context.t('My Orders'), onTap: openOrders)),
                      const SizedBox(width: 10),
                      Expanded(child: _CategoryTile(icon: Icons.notifications_active_rounded, label: context.t('Alerts'), onTap: _openNotifications, badge: _unread)),
                    ]),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                  child: Builder(builder: (context) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const SkeletonList(count: 3);
                    }
                    if (snap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
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
                        SectionHeader(context.t('Overview')),
                        const SizedBox(height: 12),
                        _StatsCard(stats: [
                          _Stat(Icons.pending_actions_rounded, AppColors.info, '${_active(p)}', context.t('Active orders')),
                          _Stat(Icons.local_laundry_service_rounded, AppColors.warning,
                              '${_count(p, {OrderStatus.pickedUp, OrderStatus.atFacility, OrderStatus.inProcess})}', context.t('In cleaning')),
                          _Stat(Icons.check_circle_rounded, AppColors.primary,
                              '${_count(p, {OrderStatus.ready, OrderStatus.outForDelivery})}', context.t('Ready / on the way')),
                          _Stat(Icons.receipt_long_rounded, AppColors.goldDark, '${p.allCount}', context.t('Total orders')),
                        ]),
                        const SizedBox(height: 24),
                        SectionHeader(context.t('Active orders'),
                            actionLabel: p.allCount > activeOrders.length ? context.t('View all') : null,
                            onAction: p.allCount > activeOrders.length ? openOrders : null),
                        const SizedBox(height: 12),
                        if (activeOrders.isEmpty)
                          SoftCard(
                            child: EmptyView(context.t('No active orders'),
                                icon: Icons.local_laundry_service_rounded, hint: context.t('Book a pickup to get started')),
                          )
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

/// Greeting row (Claundry home header): avatar, name + business, bell.
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.fullName,
    required this.tenant,
    required this.unread,
    required this.onBell,
    this.logoUrl,
  });
  final String name;
  final String fullName;
  final String tenant;
  final int unread;
  final VoidCallback onBell;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoUrl != null && logoUrl!.isNotEmpty;
    final words = fullName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
    final initials = words.isEmpty ? '?' : words.map((w) => w[0].toUpperCase()).join();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 20, 18),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.center,
            child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${context.t('Hello')}${name.isEmpty ? '' : ', $name'} 👋',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.ink, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                const SizedBox(height: 3),
                Row(children: [
                  if (hasLogo)
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsetsDirectional.only(end: 5),
                      child: Image.network(logoUrl!, fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 15)),
                    )
                  else
                    const Padding(
                      padding: EdgeInsetsDirectional.only(end: 5),
                      child: Icon(Icons.storefront_rounded, color: AppColors.primary, size: 15),
                    ),
                  Flexible(
                    child: Text(tenant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const AssistantButton(pageContext: AiPageContext(module: 'dashboard')),
          Stack(
            clipBehavior: Clip.none,
            children: [
              SquareIconButton(icon: Icons.notifications_none_rounded, onTap: onBell, tooltip: context.t('Notifications')),
              if (unread > 0)
                PositionedDirectional(
                  end: -4,
                  top: -4,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.canvas, width: 2),
                      ),
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1.25),
                      ),
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

/// Blue promo card with an amber "Book now" (the reference's discount banner,
/// repurposed for the real "Book a pickup" action).
class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 156,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(AppRadius.card + 2),
          boxShadow: AppShadows.glow(AppColors.primary),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // Washing-machine door illustration built from rings.
          PositionedDirectional(
            end: -26,
            top: -10,
            child: Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 2),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 8),
                ),
                child: const Icon(Icons.local_laundry_service_rounded, color: Colors.white, size: 46),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 150, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(context.t('Book a pickup'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.3)),
                const SizedBox(height: 4),
                Text(context.t('We collect, clean & deliver'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.3)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(context.t('Book now'),
                        style: const TextStyle(color: AppColors.onGold, fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(width: 4),
                    Icon(rtl ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded, color: AppColors.onGold, size: 16),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Bordered square tile with an icon + label (the reference's "Categories" row).
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.icon, required this.label, required this.onTap, this.highlight = false, this.badge = 0});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.tile),
        onTap: onTap,
        child: Column(children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: highlight ? AppColors.primarySoft : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                    border: Border.all(color: highlight ? AppColors.primary.withValues(alpha: 0.45) : AppColors.line, width: 1.3),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 28),
                ),
              ),
              if (badge > 0)
                PositionedDirectional(
                  end: 6,
                  top: 6,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 7),
          Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, height: 1.2, color: AppColors.inkSoft)),
        ]),
      ),
    );
  }
}

class _Stat {
  const _Stat(this.icon, this.color, this.value, this.label);
  final IconData icon;
  final Color color;
  final String value;
  final String label;
}

/// One card holding the four order counters in a 2x2 grid.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});
  final List<_Stat> stats;
  @override
  Widget build(BuildContext context) {
    Widget cell(_Stat s) => Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: s.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(s.icon, color: s.color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.1)),
                const SizedBox(height: 2),
                Text(s.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.2)),
              ]),
            ),
          ]),
        );

    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: cell(stats[0])),
            VerticalDivider(width: 1, color: AppColors.lineSoft),
            Expanded(child: cell(stats[1])),
          ]),
        ),
        Divider(height: 1, color: AppColors.lineSoft),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: cell(stats[2])),
            VerticalDivider(width: 1, color: AppColors.lineSoft),
            Expanded(child: cell(stats[3])),
          ]),
        ),
      ]),
    );
  }
}
