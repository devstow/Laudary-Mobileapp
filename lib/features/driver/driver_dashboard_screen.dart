import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/ai.dart';
import '../../models/delivery.dart';
import '../../models/enums.dart';
import '../../models/notification.dart';
import '../../services/api_exception.dart';
import '../../services/delivery_service.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/driver_task_card.dart';
import '../../widgets/ui.dart';
import '../assistant/assistant_screen.dart';
import '../notifications/notifications_screen.dart';
import 'driver_task_detail_screen.dart';
import 'geofence.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key, required this.onOpenTasks});
  final void Function(TaskGroup group, {DeliveryType? type, TaskUrgency? priority}) onOpenTasks;
  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> with WidgetsBindingObserver {
  late Future<DriverDashboard> _future;
  late final GeofenceHeartbeat _geofence = GeofenceHeartbeat(context.read<DeliveryService>());
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _fetch();
    _loadUnread();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _loadUnread());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _geofence.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadUnread();
  }

  Future<DriverDashboard> _fetch() async {
    final d = await context.read<DeliveryService>().dashboard();
    _geofence.sync(
      hasInTransit: d.active.any((t) => t.status == DeliveryStatus.inTransit),
      onArrived: (orders) {
        if (!mounted) return;
        showToast(context, '${context.t('Arrived at')} ${orders.join(', ')}');
        _refresh();
      },
    );
    return d;
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    _loadUnread();
    await _future;
  }

  Future<void> _loadUnread() async {
    try {
      final n = await context.read<NotificationService>().unreadCount();
      if (mounted && n != _unread) setState(() => _unread = n);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsScreen(onOpen: _openDriverNotification)));
    _loadUnread();
  }

  /// Driver notifications name the order number (no id) → open that task's detail.
  Future<void> _openDriverNotification(AppNotification n) async {
    final orderNo = n.orderNumberRef;
    if (orderNo == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DriverTaskDetailScreen(orderNumber: orderNo, title: orderNo),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.locale.code;
    final name = (app.user?.fullName ?? '').split(' ').first;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<DriverDashboard>(
          future: _future,
          builder: (context, snap) {
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                _header(context, name, DateFormat('EEEE, dd MMM', lang).format(DateTime.now()),
                    snap.data?.activeCount ?? 0),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 116),
                  child: Builder(builder: (context) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(padding: EdgeInsets.only(top: 8), child: SkeletonList(count: 3));
                    }
                    if (snap.hasError) {
                      return Padding(padding: const EdgeInsets.only(top: 40), child: ErrorView(ApiException.from(snap.error!).message, onRetry: _refresh));
                    }
                    final d = snap.data!;
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _kpis(context, d),
                      const SizedBox(height: 18),
                      _quickActions(context),
                      const SizedBox(height: 24),
                      SectionHeader(context.t('Active tasks')),
                      const SizedBox(height: 12),
                      if (d.active.isEmpty)
                        EmptyView(context.t("You're all caught up"), icon: Icons.local_shipping_outlined, hint: context.t('New pickups and deliveries will appear here.'))
                      else ...[
                        // Only the latest 5 on Home; the rest live on the Tasks screen.
                        ...d.active.take(5).toList().asMap().entries.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: DriverTaskCard(
                                task: e.value,
                                stopNumber: e.key + 1,
                                compact: true,
                                onTap: () async {
                                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DriverTaskDetailScreen(task: e.value)));
                                  if (mounted) _refresh();
                                },
                              ),
                            )),
                        if (d.activeCount > 5)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => widget.onOpenTasks(TaskGroup.active),
                              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                              label: Text('${context.t('Show more')} (${d.activeCount})'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            ),
                          ),
                      ],
                      if (d.recentCompleted.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        SectionHeader(context.t('Recent activity')),
                        const SizedBox(height: 12),
                        ...d.recentCompleted.take(8).map((t) => _recentRow(context, t, lang)),
                      ],
                    ]);
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String name, String dateStr, int active) {
    final fullName = context.read<AppState>().user?.fullName ?? '';
    final words = fullName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
    final initials = words.isEmpty ? '?' : words.map((w) => w[0].toUpperCase()).join();
    return BrandHero(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 20, 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            alignment: Alignment.center,
            child: Text(initials, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 17)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${context.t('Hello')}${name.isEmpty ? '' : ', $name'} 👋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text(dateStr, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 10),
          const AssistantButton(onDark: true, pageContext: AiPageContext(module: 'driver_home')),
          Stack(clipBehavior: Clip.none, children: [
            SquareIconButton(icon: Icons.notifications_none_rounded, onTap: _openNotifications, onDark: true, tooltip: context.t('Notifications')),
            if (_unread > 0)
              PositionedDirectional(
                end: -4,
                top: -4,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                    decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primaryDark, width: 2)),
                    child: Text(_unread > 9 ? '9+' : '$_unread',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.onGold, fontSize: 10, fontWeight: FontWeight.w900, height: 1.25)),
                  ),
                ),
              ),
          ]),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(gradient: AppColors.goldGradient, shape: BoxShape.circle),
              child: const Icon(Icons.route_rounded, color: AppColors.onGold, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('$active ${context.t('active stop(s)')}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            Icon(Icons.local_shipping_rounded, color: Colors.white.withValues(alpha: 0.8), size: 22),
          ]),
        ),
      ]),
    );
  }

  Widget _kpis(BuildContext context, DriverDashboard d) {
    Widget tile(IconData i, Color c, String v, String l, VoidCallback onTap) => Expanded(
          child: SoftCard(
            onTap: onTap,
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 32, height: 32, decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(9)), child: Icon(i, color: c, size: 18)),
                const Spacer(),
                Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text(l, style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.2))),
                Icon(Icons.chevron_right_rounded, size: 15, color: AppColors.faint),
              ]),
            ]),
          ),
        );
    void open(TaskGroup g, {DeliveryType? type, TaskUrgency? priority}) => widget.onOpenTasks(g, type: type, priority: priority);
    return Column(children: [
      Row(children: [
        tile(Icons.download_rounded, AppColors.warning, '${d.pendingPickups}', context.t("Today's pickups"), () => open(TaskGroup.all, type: DeliveryType.pickup, priority: TaskUrgency.today)),
        const SizedBox(width: 12),
        tile(Icons.upload_rounded, AppColors.success, '${d.pendingDeliveries}', context.t("Today's deliveries"), () => open(TaskGroup.all, type: DeliveryType.delivery, priority: TaskUrgency.today)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        tile(Icons.pending_actions_rounded, AppColors.info, '${d.activeCount}', context.t('Pending tasks'), () => open(TaskGroup.todo)),
        const SizedBox(width: 12),
        tile(Icons.local_shipping_rounded, AppColors.primary, '${d.inProgress}', context.t('In progress'), () => open(TaskGroup.active)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        tile(Icons.schedule_rounded, AppColors.goldDark, '${d.upcomingCount}', context.t('Upcoming'), () => open(TaskGroup.all, priority: TaskUrgency.upcoming)),
        const SizedBox(width: 12),
        tile(Icons.emoji_events_rounded, AppColors.success, '${d.completedTotal}', context.t('Total completed'), () => open(TaskGroup.completed)),
      ]),
    ]);
  }

  /// Bordered square action tiles (same "Categories" language as the customer home).
  Widget _quickActions(BuildContext context) {
    Widget a(IconData i, String l, VoidCallback onTap, {int badge = 0}) => Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.tile),
              onTap: onTap,
              child: Column(children: [
                Container(
                  height: 64,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                    border: Border.all(color: AppColors.line, width: 1.3),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Stack(alignment: Alignment.center, children: [
                    Icon(i, color: AppColors.primary, size: 26),
                    if (badge > 0)
                      PositionedDirectional(
                        top: 8,
                        end: 8,
                        child: Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)),
                      ),
                  ]),
                ),
                const SizedBox(height: 7),
                Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.inkSoft)),
              ]),
            ),
          ),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      a(Icons.list_alt_rounded, context.t('My tasks'), () => widget.onOpenTasks(TaskGroup.all)),
      const SizedBox(width: 12),
      a(Icons.report_problem_rounded, context.t('Issues'), () => widget.onOpenTasks(TaskGroup.issues)),
      const SizedBox(width: 12),
      a(Icons.notifications_active_rounded, context.t('Alerts'), _openNotifications, badge: _unread),
    ]);
  }

  Widget _recentRow(BuildContext context, DeliveryTask t, String lang) {
    final c = deliveryTypeColor(t.type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(13),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)), child: Icon(t.isPickup ? Icons.download_rounded : Icons.upload_rounded, color: c, size: 19)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.orderNumber ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text('${t.customerName ?? '—'} · ${t.completedAt != null ? DateFormat('dd MMM, HH:mm', lang).format(t.completedAt!) : ''}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
        ]),
      ),
    );
  }
}
