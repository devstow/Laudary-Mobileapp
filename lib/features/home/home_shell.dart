import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../neworder/new_order_screen.dart';
import '../orders/orders_screen.dart';
import '../payments/payments_screen.dart';
import '../profile/profile_screen.dart';
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _NewPickupFab(onTap: _newPickup),
      bottomNavigationBar: _BottomBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _NewPickupFab extends StatelessWidget {
  const _NewPickupFab({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
          boxShadow: AppShadows.glow(AppColors.primary),
          border: Border.all(color: AppColors.canvas, width: 4),
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: AppColors.surface,
      elevation: 12,
      shadowColor: AppColors.ink.withValues(alpha: 0.15),
      shape: const CircularNotchedRectangle(),
      notchMargin: 9,
      height: 66,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          _item(0, Icons.home_outlined, Icons.home_rounded, context.t('Home')),
          _item(1, Icons.receipt_long_outlined, Icons.receipt_long_rounded, context.t('Orders')),
          const SizedBox(width: 64), // notch gap
          _item(2, Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, context.t('Payments')),
          _item(3, Icons.person_outline_rounded, Icons.person_rounded, context.t('Account')),
        ],
      ),
    );
  }

  Widget _item(int i, IconData icon, IconData active, String label) {
    final selected = index == i;
    final color = selected ? AppColors.primary : AppColors.faint;
    return Expanded(
      child: InkResponse(
        onTap: () => onSelect(i),
        radius: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? active : icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 10.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
