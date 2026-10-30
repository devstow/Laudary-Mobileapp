import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../neworder/new_order_screen.dart';
import '../orders/orders_screen.dart';
import '../payments/payments_screen.dart';
import '../profile/profile_screen.dart';
import '../../widgets/floating_nav_bar.dart';
import 'dashboard_screen.dart';
import 'dart:async';

import 'package:provider/provider.dart';

import '../notifications/notification_center.dart';
import '../notifications/notifications_screen.dart';
import '../update/restore_after_update.dart';
import '../update/resume_point.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _rev = 0; // bump to force tabs to re-fetch after a new booking

  @override
  void initState() {
    super.initState();
    ScreenTracker.tab = 0;
    // First launch after an in-app update: reopen the screen the customer was on (re-validated, loaded fresh).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) restoreAfterUpdate(context, driver: false, setTab: _selectTab);
    });
    // Tapped system notification (app was closed → launchTarget; app running → opens stream).
    final center = context.read<NotificationCenter>();
    _opens = center.opens.listen(_openFromNotification);
    center.launchTarget().then((t) { if (t != null) _openFromNotification(t); });
  }

  StreamSubscription<String>? _opens;

  @override
  void dispose() {
    _opens?.cancel();
    super.dispose();
  }

  void _openFromNotification(String target) {
    if (!mounted) return;
    final id = target.startsWith('notification:') ? target.substring('notification:'.length) : null;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsScreen(autoOpenId: id)));
  }

  void _selectTab(int i) {
    if (!mounted) return;
    setState(() => _index = i);
    ScreenTracker.tab = i;
  }

  Future<void> _newPickup() async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewOrderScreen()),
    );
    if (booked == true && mounted) {
      setState(() {
        _rev++;
        _index = 1; // land on My Orders to see it
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      DashboardScreen(key: ValueKey('dash-$_rev'), onNewPickup: _newPickup),
      OrdersScreen(key: ValueKey('orders-$_rev')),
      PaymentsScreen(key: ValueKey('pay-$_rev')),
      const ProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: FloatingNavBar(
        index: _index,
        onSelect: _selectTab,
        items: [
          NavItem(Icons.home_outlined, Icons.home_rounded, context.t('Home')),
          NavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, context.t('Orders')),
          NavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, context.t('Payments')),
          NavItem(Icons.person_outline_rounded, Icons.person_rounded, context.t('Account')),
        ],
        // The raised amber "+" in the middle of the bar books a new pickup (same action as before).
        centerAction: NavCenterAction(icon: Icons.add_rounded, tooltip: context.t('Book a pickup'), onTap: _newPickup),
      ),
    );
  }
}
