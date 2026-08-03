import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../theme/app_theme.dart';
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
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: context.t('Home')),
          NavigationDestination(icon: const Icon(Icons.local_shipping_outlined), selectedIcon: const Icon(Icons.local_shipping_rounded), label: context.t('Tasks')),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: context.t('Account')),
        ],
      ),
    );
  }
}
