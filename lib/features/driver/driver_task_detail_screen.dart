import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/realtime.dart';
import '../../l10n/l10n.dart';
import '../../models/delivery.dart';
import '../../models/driver_task_detail.dart';
import '../../models/enums.dart';
import '../../services/api_exception.dart';
import '../../services/delivery_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/driver_task_card.dart';
import '../../widgets/ui.dart';
import 'driver_actions.dart';

/// Single delivery-task detail — the full task card (journey + status-gated actions + navigate/call)
/// followed by everything the driver needs for the stop: what to do next, what to collect, the order
/// summary, special instructions, the amount to collect on delivery, the order's other leg and the
/// attempt history. Opened by tapping a task in a list (pass [task]) or from a notification that only
/// names the order (pass [orderNumber]). Actions run + reload in place; live updates reload too.
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
  DriverTaskDetail? _detail;
  bool _busy = false;
  StreamSubscription<RealtimeEvent>? _rt;

  String get _orderNo => widget.task?.orderNumber ?? widget.orderNumber ?? '';

  @override
  void initState() {
    super.initState();
    _rt = context.read<RealtimeClient>().events.listen((e) {
      final oid = _detail?.task.orderId ?? widget.task?.orderId;
      if (e.touchesOrders && mounted && oid != null && (e.orderId ?? '').toLowerCase() == oid.toLowerCase()) _reload();
    });
  }

  @override
  void dispose() {
    _rt?.cancel();
    super.dispose();
  }

  void _reload() => setState(() => _future = _find());

  Future<DeliveryTask?> _find() async {
    final svc = context.read<DeliveryService>();
    final page = await svc.myTasks(group: TaskGroup.all, pageSize: 50);
    DeliveryTask? found;
    // Prefer an exact id match (from a list tap).
    final id = widget.task?.id;
    if (id != null) {
      final byId = page.items.where((t) => t.id == id).toList();
      if (byId.isNotEmpty) found = byId.first;
    }
    if (found == null) {
      // Otherwise match by order number (from a notification).
      final matches = page.items.where((t) => (t.orderNumber ?? '') == _orderNo).toList();
      if (matches.isNotEmpty) {
        matches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        found = matches.firstWhere((t) => t.status.isActionable, orElse: () => matches.first);
      }
    }
    found ??= widget.task; // fall back to the task we already have, if any
    if (found != null) {
      // The full record (order, items, instructions, amount to collect, legs, history) — best effort.
      try {
        final d = await svc.taskDetail(found.id);
        if (mounted) setState(() => _detail = d);
      } catch (_) {
        if (mounted) setState(() => _detail = null);
      }
    }
    return found;
  }

  Future<void> _act(DeliveryTask task, DriverAction action) async {
    setState(() => _busy = true);
    final changed = await runDriverAction(context, context.read<DeliveryService>(), task, action);
    if (!mounted) return;
    setState(() => _busy = false);
    if (changed) _reload();
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
            return ErrorView(ApiException.from(snap.error!).message, onRetry: _reload);
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
          final d = _detail;
          final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _NextStep(task: task, collect: d?.collectOnDelivery ?? false),
                DriverTaskCard(task: task, busy: _busy, onAction: (a) => _act(task, a)),
                if (d != null) ...[
                  if (d.collectOnDelivery && task.status != DeliveryStatus.completed && !task.status.isClosed) ...[
                    const SizedBox(height: 12),
                    _CollectCard(detail: d, lang: lang),
                  ],
                  if ((d.taskNotes ?? '').isNotEmpty || (d.orderNotes ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _InstructionsCard(detail: d),
                  ],
                  const SizedBox(height: 20),
                  SectionHeader('${context.t(task.isPickup ? 'Items to collect' : 'Items to hand over')} · ${d.itemCount}'),
                  const SizedBox(height: 10),
                  SoftCard(
                    child: d.items.isEmpty
                        ? Text(context.t('No services listed on this order.'), style: TextStyle(color: AppColors.muted, fontSize: 13))
                        : Column(children: [for (final it in d.items) _ItemRow(item: it)]),
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(context.t('Order summary')),
                  const SizedBox(height: 10),
                  SoftCard(child: _OrderSummary(detail: d, lang: lang)),
                  if (d.legs.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SectionHeader(context.t('Order journey')),
                    const SizedBox(height: 10),
                    SoftCard(child: Column(children: [for (final l in d.legs) _LegRow(leg: l, lang: lang)])),
                  ],
                  if (d.history.length > 1 || (d.history.length == 1 && d.history.first.endedAt != null)) ...[
                    const SizedBox(height: 20),
                    SectionHeader(context.t('Task history')),
                    const SizedBox(height: 10),
                    SoftCard(child: Column(children: [for (final h in d.history) _AttemptRow(attempt: h, lang: lang)])),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// "What to do now" — the single next permitted action, derived from the task workflow.
class _NextStep extends StatelessWidget {
  const _NextStep({required this.task, required this.collect});
  final DeliveryTask task;
  final bool collect;

  @override
  Widget build(BuildContext context) {
    String? title, text;
    IconData icon = Icons.arrow_circle_right_rounded;
    switch (task.status) {
      case DeliveryStatus.assigned:
        icon = Icons.inbox_rounded;
        title = context.t('Accept this task');
        text = context.t('Review the stop below, then accept it to start — or reject it with a reason so the dispatcher can reassign.');
        break;
      case DeliveryStatus.accepted:
        icon = Icons.local_shipping_rounded;
        title = context.t('Start the trip');
        text = context.t(task.isPickup ? 'Head to the customer to collect the items.' : 'Head to the customer to deliver the clean items.');
        break;
      case DeliveryStatus.inTransit:
        icon = Icons.where_to_vote_rounded;
        title = context.t('Mark arrived');
        text = context.t('Tap “Mark arrived” when you reach the address (it is also detected automatically from your location).');
        break;
      case DeliveryStatus.arrived:
        icon = Icons.check_circle_rounded;
        title = context.t(task.isPickup ? 'Complete the pickup' : 'Complete the delivery');
        text = task.isPickup
            ? context.t('Check the items with the customer, attach a photo if you like, then complete.')
            : context.t(collect ? 'Hand over the items, collect the balance due, then complete with a proof photo.' : 'Hand over the items, then complete with a proof photo.');
        break;
      case DeliveryStatus.pending:
        icon = Icons.schedule_rounded;
        title = context.t('Waiting for assignment');
        text = context.t('This task is back in the queue; a dispatcher will assign it.');
        break;
      default:
        return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${context.t('Next step')}: $title', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink)),
              const SizedBox(height: 3),
              Text(text, style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5, height: 1.35)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Amber "collect on delivery" card — the balance the customer still owes on this order.
class _CollectCard extends StatelessWidget {
  const _CollectCard({required this.detail, required this.lang});
  final DriverTaskDetail detail;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(gradient: AppColors.goldGradient, shape: BoxShape.circle),
          child: const Icon(Icons.payments_rounded, color: AppColors.onGold, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('Collect on delivery'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink)),
            const SizedBox(height: 2),
            Text(
              detail.paymentMethod != null
                  ? '${context.t('Balance the customer still owes for this order.')} (${context.t('Method')}: ${context.t(detail.paymentMethod!.label)})'
                  : context.t('Balance the customer still owes for this order.'),
              style: TextStyle(color: AppColors.inkSoft, fontSize: 12, height: 1.3),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Text(money(detail.balanceDue, detail.currency, lang), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.goldDark)),
      ]),
    );
  }
}

class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard({required this.detail});
  final DriverTaskDetail detail;

  @override
  Widget build(BuildContext context) {
    final lines = [if ((detail.taskNotes ?? '').isNotEmpty) detail.taskNotes!, if ((detail.orderNotes ?? '').isNotEmpty) detail.orderNotes!];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.sticky_note_2_rounded, color: AppColors.warning, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('Special instructions'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.ink)),
            const SizedBox(height: 4),
            for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(l, style: TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.35))),
          ]),
        ),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final DriverTaskItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(8)),
          child: Text('×${item.quantity}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.serviceName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
            if ((item.notes ?? '').isNotEmpty) Text(item.notes!, style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.detail, required this.lang});
  final DriverTaskDetail detail;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM, HH:mm', lang);
    final d = detail;
    return Column(children: [
      InfoRow(icon: Icons.tag_rounded, label: context.t('Order'), value: d.orderNumber),
      InfoRow(icon: Icons.local_laundry_service_rounded, label: context.t('Order status'), value: context.t(d.orderStatus.label), valueColor: AppColors.primary),
      InfoRow(icon: Icons.category_rounded, label: context.t('Order type'), value: '${context.t(d.orderType.label)}${d.speed == ServiceSpeed.express ? ' · ${context.t('Express')}' : ''}'),
      InfoRow(icon: Icons.event_rounded, label: context.t('Placed'), value: df.format(d.orderPlacedAt)),
      if (d.pickupAt != null) InfoRow(icon: Icons.download_rounded, label: context.t('Pickup time'), value: df.format(d.pickupAt!)),
      if (d.readyByAt != null) InfoRow(icon: Icons.schedule_rounded, label: context.t('Ready by'), value: df.format(d.readyByAt!)),
      if (d.deliveryAt != null) InfoRow(icon: Icons.upload_rounded, label: context.t('Delivery time'), value: df.format(d.deliveryAt!)),
      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1)),
      MoneyRow(context.t('Total'), money(d.orderTotal, d.currency, lang), strong: true),
      MoneyRow(context.t('Paid'), money(d.amountPaid, d.currency, lang)),
      MoneyRow(context.t('Balance due'), money(d.balanceDue, d.currency, lang), accent: d.balanceDue > 0),
      const SizedBox(height: 4),
      Align(alignment: AlignmentDirectional.centerStart, child: PaymentChip(d.paymentStatus)),
    ]);
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({required this.leg, required this.lang});
  final DriverTaskLeg leg;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM, HH:mm', lang);
    final c = deliveryTypeColor(leg.type);
    final sc = deliveryStatusColor(leg.status);
    final who = leg.isMine ? context.t('You') : (leg.driverName ?? context.t('Unassigned'));
    final when = leg.completedAt ?? leg.scheduledAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)), child: Icon(leg.type == DeliveryType.pickup ? Icons.download_rounded : Icons.upload_rounded, color: c, size: 18)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${context.t(leg.type.label)}${leg.attemptNumber > 1 ? ' · ${context.t('Attempt')} ${leg.attemptNumber}' : ''}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.ink)),
            Text('$who${when != null ? ' · ${df.format(when)}' : ''}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(color: sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: Text(context.t(leg.status.label), style: TextStyle(color: sc, fontWeight: FontWeight.w800, fontSize: 11)),
        ),
      ]),
    );
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.attempt, required this.lang});
  final DriverTaskAttempt attempt;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM, HH:mm', lang);
    final sc = deliveryStatusColor(attempt.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(color: sc.withValues(alpha: 0.13), shape: BoxShape.circle), child: Icon(deliveryStatusIcon(attempt.status), color: sc, size: 16)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${context.t('Attempt')} ${attempt.attemptNumber} · ${context.t(attempt.status.label)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink)),
            Text('${attempt.driverName ?? '—'} · ${df.format(attempt.assignedAt)}${attempt.endedAt != null ? ' → ${df.format(attempt.endedAt!)}' : ''}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            if ((attempt.reason ?? '').isNotEmpty) Text('“${attempt.reason}”', style: TextStyle(color: AppColors.inkSoft, fontSize: 12, fontStyle: FontStyle.italic)),
          ]),
        ),
      ]),
    );
  }
}
