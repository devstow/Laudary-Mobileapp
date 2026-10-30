import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../services/delivery_service.dart';
import '../../services/order_service.dart';
import '../../state/app_state.dart';
import '../driver/driver_task_detail_screen.dart';
import '../orders/order_details_screen.dart';
import 'update_controller.dart';

/// Called once by the driver / customer shell after sign-in: on the first launch after an update, says so and
/// reopens the screen the user was on — re-checked against the server first (the task may have been reassigned,
/// the order hidden by a permission change), so an invalid screen is never restored. Data is loaded fresh by the
/// screen itself; no action is ever replayed.
Future<void> restoreAfterUpdate(BuildContext context, {required bool driver, required void Function(int tab) setTab}) async {
  final upd = context.read<UpdateController>();
  final userId = context.read<AppState>().user?.id;
  final version = upd.takeUpdatedTo();
  final point = userId == null ? null : upd.takeResume(userId);
  if (version == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final nav = Navigator.of(context);
  final t = context.t;
  final deliveries = context.read<DeliveryService>();
  final orders = context.read<OrderService>();
  // "Ready": confirmed by the running build itself (not by the download or the installer).
  await showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
      title: Text(t('Update complete')),
      content: Text('${t('Welcome back! You are now using version')} ${ltr(version)}.', textAlign: TextAlign.center),
      actions: [FilledButton(onPressed: () => Navigator.of(d).pop(), child: Text(t('Continue')))],
    ),
  );
  if (point == null) return;

  setTab(point.tab);
  if (point.id == null) return;
  try {
    if (driver && point.kind == 'driverTask') {
      final page = await deliveries.myTasks(group: TaskGroup.all, pageSize: 50);
      final task = page.items.where((x) => x.id == point.id).firstOrNull;
      if (task == null) {
        setTab(1);
        messenger?.showSnackBar(SnackBar(content: Text(t('The task you were viewing is no longer assigned to you.'))));
        return;
      }
      await nav.push(MaterialPageRoute(builder: (_) => DriverTaskDetailScreen(task: task)));
    } else if (!driver && point.kind == 'order') {
      await orders.detail(point.id!); // still visible to this user?
      await nav.push(MaterialPageRoute(builder: (_) => OrderDetailsScreen(orderId: point.id!, orderNumber: point.label)));
    }
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text(t('The screen you were on could not be reopened.'))));
  }
}
