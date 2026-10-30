import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../widgets/floating_nav_bar.dart';
import 'dart:async';

import 'package:provider/provider.dart';

import '../notifications/notification_center.dart';
import '../notifications/notifications_screen.dart';
import '../update/restore_after_update.dart';
import '../update/resume_point.dart';
import 'driver_dashboard_screen.dart';
import 'driver_profile_screen.dart';
import 'driver_tasks_screen.dart';

/// Bottom-nav shell for the DRIVER experience: Home · Tasks · Account.
class DriverShell extends StatefulWidget {
  const DriverShell({super.key});
  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _index = 0;
  TaskGroup _tasksGroup = TaskGroup.all;
  DeliveryType? _tasksType;
  TaskUrgency? _tasksPriority;
  int _tasksRev = 0; // bump to re-create the Tasks tab with new initial filters

  @override
  void initState() {
    super.initState();
    ScreenTracker.tab = 0;
    // First launch after an in-app update: reopen the screen the driver was on (re-validated, loaded fresh).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) restoreAfterUpdate(context, driver: true, setTab: _selectTab);
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
    Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => NotificationsScreen(autoOpenId: id, onOpen: (n) => openDriverNotification(ctx, n))));
  }

  void _selectTab(int i) {
    if (!mounted) return;
    setState(() => _index = i.clamp(0, 2));
    ScreenTracker.tab = _index;
  }

  void _openTasks(TaskGroup group, {DeliveryType? type, TaskUrgency? priority}) {
    setState(() {
      _tasksGroup = group;
      _tasksType = type;
      _tasksPriority = priority;
      _tasksRev++;
      _index = 1;
    });
    ScreenTracker.tab = 1;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      DriverDashboardScreen(onOpenTasks: _openTasks),
      DriverTasksScreen(key: ValueKey('tasks-$_tasksRev'), initialGroup: _tasksGroup, initialType: _tasksType, initialPriority: _tasksPriority),
      const DriverProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: FloatingNavBar(
        index: _index,
        onSelect: _selectTab,
        items: [
          NavItem(Icons.home_outlined, Icons.home_rounded, context.t('Home')),
          NavItem(Icons.local_shipping_outlined, Icons.local_shipping_rounded, context.t('Tasks')),
          NavItem(Icons.person_outline_rounded, Icons.person_rounded, context.t('Account')),
        ],
      ),
    );
  }
}
