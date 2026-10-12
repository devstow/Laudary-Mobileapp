import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../neworder/new_order_screen.dart';
import '../orders/orders_screen.dart';
import '../payments/payments_screen.dart';
import '../profile/profile_screen.dart';
import '../../widgets/floating_nav_bar.dart';
import 'dashboard_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _rev = 0; // bump to force tabs to re-fetch after a new booking

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
        onSelect: (i) => setState(() => _index = i),
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
