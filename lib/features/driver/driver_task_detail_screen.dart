import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/delivery.dart';
import '../../models/enums.dart';
import '../../services/api_exception.dart';
import '../../services/delivery_service.dart';
import '../../widgets/driver_task_card.dart';
import '../../widgets/ui.dart';
import 'driver_actions.dart';

/// Single delivery-task detail — the full task card (journey + status-gated actions +
/// navigate/call). Opened by tapping a task in a list (pass [task]) or from a notification
/// that only names the order (pass [orderNumber]). Actions run + reload in place.
class DriverTaskDetailScreen extends StatefulWidget {
  const DriverTaskDetailScreen({super.key, this.task, this.orderNumber, this.title})
      : assert(task != null || orderNumber != null, 'Provide a task or an order number');
  final DeliveryTask? task;
  final String? orderNumber;
  final String? title;

  @override
  State<DriverTaskDetailScreen> createState() => _DriverTaskDetailScreenState();
}

class _DriverTaskDetailScreenState extends State<DriverTaskDetailScreen> {
  late Future<DeliveryTask?> _future = _find();
  bool _busy = false;

  String get _orderNo => widget.task?.orderNumber ?? widget.orderNumber ?? '';

  Future<DeliveryTask?> _find() async {
    final page = await context.read<DeliveryService>().myTasks(group: TaskGroup.all, pageSize: 50);
    // Prefer an exact id match (from a list tap).
    final id = widget.task?.id;
    if (id != null) {
      final byId = page.items.where((t) => t.id == id).toList();
      if (byId.isNotEmpty) return byId.first;
    }
    // Otherwise match by order number (from a notification).
    final matches = page.items.where((t) => (t.orderNumber ?? '') == _orderNo).toList();
    if (matches.isEmpty) return widget.task; // fall back to the task we already have, if any
    matches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches.firstWhere((t) => t.status.isActionable, orElse: () => matches.first);
  }

  Future<void> _act(DeliveryTask task, DriverAction action) async {
    setState(() => _busy = true);
    final changed = await runDriverAction(context, context.read<DeliveryService>(), task, action);
    if (!mounted) return;
    setState(() => _busy = false);
    if (changed) setState(() => _future = _find());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? (_orderNo.isEmpty ? context.t('Task') : _orderNo))),
      body: FutureBuilder<DeliveryTask?>(
        future: _future,
        initialData: widget.task,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && snap.data == null) {
            return const Padding(padding: EdgeInsets.all(20), child: SkeletonList(count: 1));
          }
          if (snap.hasError && snap.data == null) {
            return ErrorView(ApiException.from(snap.error!).message, onRetry: () => setState(() => _future = _find()));
          }
          final task = snap.data;
          if (task == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: EmptyView(context.t('Task not found'), icon: Icons.local_shipping_outlined, hint: context.t('It may have been reassigned or removed.')),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _find()),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                DriverTaskCard(task: task, busy: _busy, onAction: (a) => _act(task, a)),
              ],
            ),
          );
        },
      ),
    );
  }
}
