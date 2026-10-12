import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../widgets/floating_nav_bar.dart';
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

  void _openTasks(TaskGroup group, {DeliveryType? type, TaskUrgency? priority}) {
    setState(() {
      _tasksGroup = group;
      _tasksType = type;
      _tasksPriority = priority;
      _tasksRev++;
      _index = 1;
    });
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
        onSelect: (i) => setState(() => _index = i),
        items: [
          NavItem(Icons.home_outlined, Icons.home_rounded, context.t('Home')),
          NavItem(Icons.local_shipping_outlined, Icons.local_shipping_rounded, context.t('Tasks')),
          NavItem(Icons.person_outline_rounded, Icons.person_rounded, context.t('Account')),
        ],
      ),
    );
  }
}
