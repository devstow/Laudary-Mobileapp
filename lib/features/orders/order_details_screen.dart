import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../models/order_detail.dart';
import '../../services/api_exception.dart';
import '../../services/order_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/journey_stepper.dart';
import '../../widgets/map_viewer.dart';
import '../../widgets/order_timeline.dart';
import '../../widgets/ui.dart';
import '../invoice/invoice_screen.dart';
import '../neworder/new_order_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.orderId, this.orderNumber});
  final String orderId;
  final String? orderNumber;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  OrderDetail? _order;
  List<OrderEvent> _timeline = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = _order == null; _error = null; });
    try {
      final svc = context.read<OrderService>();
      final r = await Future.wait([svc.detail(widget.orderId), svc.timeline(widget.orderId)]);
      if (!mounted) return;
      setState(() {
        _order = r[0] as OrderDetail;
        _timeline = r[1] as List<OrderEvent>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = ApiException.from(e).message; _loading = false; });
    }
  }

  // ── actions ──────────────────────────────────────────────────────────────
  void _viewInvoice() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InvoiceScreen(orderId: widget.orderId, orderNumber: _order?.orderNumber ?? widget.orderNumber),
    ));
  }

  Future<void> _edit(OrderDetail o) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewOrderScreen(editOrder: o)),
    );
    if (changed == true && mounted) _load();
  }

  Future<DateTime?> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
        context: context, firstDate: now, lastDate: now.add(const Duration(days: 30)), initialDate: now);
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _reschedule() async {
    final dt = await _pickDateTime();
    if (dt == null || !mounted) return;
    await _run(() => context.read<OrderService>().reschedulePickup(widget.orderId, dt), context.t('Pickup rescheduled'));
  }

  Future<void> _chooseDelivery() async {
    final dt = await _pickDateTime();
    if (dt == null || !mounted) return;
    await _run(() => context.read<OrderService>().setDeliveryTime(widget.orderId, dt), context.t('Delivery time confirmed'));
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('Cancel this order?')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ctx.t('You can cancel until your items are collected. This can\'t be undone.'),
              style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
          const SizedBox(height: 12),
          TextField(controller: reason, decoration: InputDecoration(labelText: ctx.t('Reason (optional)')), maxLines: 2),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t('Keep order'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.t('Cancel order')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => context.read<OrderService>().cancelOrder(widget.orderId, reason: reason.text.trim().isEmpty ? null : reason.text.trim()),
        context.t('Your order has been cancelled.'));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('Delete this order?')),
        content: Text(ctx.t('This removes the order from your list. You can only do this before your items are collected.'),
            style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t('Keep order'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.t('Delete order')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<OrderService>().deleteOrder(widget.orderId);
      if (!mounted) return;
      showToast(context, context.t('Your order has been removed.'));
      Navigator.of(context).pop(true); // signal the list to refresh
    } catch (e) {
      if (mounted) { showToast(context, ApiException.from(e).message, error: true); setState(() => _busy = false); }
    }
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showToast(context, okMsg);
      await _load();
    } catch (e) {
      if (mounted) showToast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().locale.code;
    final currency = context.watch<AppState>().currency; // tenant currency, like the web
    final o = _order;

    return Scaffold(
      appBar: AppBar(
        title: Text(o?.orderNumber ?? widget.orderNumber ?? context.t('Order details')),
        actions: o == null
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.receipt_long_rounded),
                  tooltip: context.t('View invoice'),
                  onPressed: _viewInvoice,
                ),
                if (o.canEdit)
                  IconButton(
                    icon: const Icon(Icons.edit_rounded),
                    tooltip: context.t('Edit order'),
                    onPressed: _busy ? null : () => _edit(o),
                  ),
                if (o.canReschedule || o.canCancel || o.canDelete)
                  PopupMenuButton<String>(
                    tooltip: context.t('More'),
                    onSelected: (v) {
                      if (v == 'reschedule') _reschedule();
                      if (v == 'cancel') _cancel();
                      if (v == 'delete') _delete();
                    },
                    itemBuilder: (_) => [
                      if (o.canReschedule)
                        PopupMenuItem(value: 'reschedule', child: _menuItem(Icons.edit_calendar_rounded, context.t('Reschedule pickup'))),
                      if (o.canCancel)
                        PopupMenuItem(value: 'cancel', child: _menuItem(Icons.close_rounded, context.t('Cancel order'), danger: true)),
                      if (o.canDelete)
                        PopupMenuItem(value: 'delete', child: _menuItem(Icons.delete_outline_rounded, context.t('Delete order'), danger: true)),
                    ],
                  ),
              ],
      ),
      // The one contextual primary action (choose delivery when ready) stays pinned + always reachable.
      bottomNavigationBar: (o != null && o.canChooseDelivery) ? _deliveryCta(o) : null,
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: SkeletonList(count: 3))
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _content(o!, currency, lang)),
    );
  }

  Widget _content(OrderDetail o, String currency, String lang) {
    final offTrack = o.status == OrderStatus.cancelled || o.status == OrderStatus.onHold;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        _hero(o, currency, lang),
        const SizedBox(height: 14),

        if (o.canChooseDelivery && o.deliveryAt == null) ...[
          _readyBanner(),
          const SizedBox(height: 14),
        ],

        // On-hold / cancelled banner stays in the always-visible summary area.
        if (offTrack) ...[
          _offTrack(o),
          const SizedBox(height: 14),
        ],

        // Tracking journey (only meaningful while the order is on track)
        if (!offTrack) ...[
          _AccordionSection(
            title: context.t('Tracking'),
            child: Padding(padding: const EdgeInsets.only(top: 4), child: JourneyStepper(status: o.status, type: o.type)),
          ),
          const SizedBox(height: 12),
        ],

        // Pickup & delivery (map + addresses + contact)
        if (o.hasPickupPin || o.pickupAddress != null || o.contactPhone != null) ...[
          _AccordionSection(
            title: context.t('Pickup & delivery'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (o.hasPickupPin || o.hasDeliveryPin) ...[
                MapViewer(
                  pickup: o.hasPickupPin ? LatLng(o.pickupLat!, o.pickupLng!) : null,
                  delivery: o.hasDeliveryPin ? LatLng(o.deliveryLat!, o.deliveryLng!) : null,
                ),
                const SizedBox(height: 12),
              ],
              if (o.pickupAddress != null && o.pickupAddress!.isNotEmpty)
                InfoRow(icon: Icons.trip_origin_rounded, label: context.t('Pickup'), value: o.pickupAddress!,
                    onTap: o.hasPickupPin ? () => _openMaps(o.pickupLat!, o.pickupLng!) : null),
              if (o.deliveryAddress != null && o.deliveryAddress!.isNotEmpty && o.deliveryAddress != o.pickupAddress)
                InfoRow(icon: Icons.flag_rounded, label: context.t('Delivery'), value: o.deliveryAddress!,
                    onTap: o.hasDeliveryPin ? () => _openMaps(o.deliveryLat!, o.deliveryLng!) : null),
              if (o.contactPhone != null && o.contactPhone!.isNotEmpty)
                InfoRow(icon: Icons.phone_rounded, label: context.t('Contact'), value: o.contactPhone!,
                    valueColor: AppColors.primary, onTap: () => _call(o.contactPhone!)),
              // Schedule folded into the same card (was a separate card) to shorten the screen.
              if (o.pickupAt != null || o.readyByAt != null || o.deliveryAt != null) ...[
                const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1)),
                if (o.pickupAt != null) InfoRow(icon: Icons.event_available_rounded, label: context.t('Pickup time'), value: _fmt(o.pickupAt!, lang)),
                if (o.readyByAt != null) InfoRow(icon: Icons.schedule_rounded, label: context.t('Ready by'), value: _fmt(o.readyByAt!, lang)),
                if (o.deliveryAt != null) InfoRow(icon: Icons.local_shipping_rounded, label: context.t('Delivery time'), value: _fmt(o.deliveryAt!, lang)),
              ],
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // Items (expanded by default — what customers check most)
        _AccordionSection(
          title: '${context.t('Items')} · ${o.items.length}',
          initiallyExpanded: true,
          child: Column(children: [for (final it in o.items) _itemRow(it, currency, lang)]),
        ),
        const SizedBox(height: 12),

        // Payment (merged: cost breakdown + payment state in one card)
        _AccordionSection(
          title: context.t('Payment'),
          child: Column(children: [
            MoneyRow(context.t('Subtotal'), money(o.subtotal, currency, lang)),
            if (o.discountAmount > 0) MoneyRow(context.t('Discount'), '- ${money(o.discountAmount, currency, lang)}'),
            if (o.expressSurcharge > 0) MoneyRow(context.t('Express surcharge'), money(o.expressSurcharge, currency, lang)),
            if (o.deliveryFee > 0) MoneyRow(context.t('Delivery fee'), money(o.deliveryFee, currency, lang)),
            MoneyRow('${context.t('VAT')} (${o.taxRate.toStringAsFixed(0)}%)', money(o.taxAmount, currency, lang)),
            const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1)),
            MoneyRow(context.t('Total'), money(o.total, currency, lang), strong: true, accent: true),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text(context.t('Status'), style: TextStyle(color: AppColors.muted, fontSize: 13.5))),
              PaymentChip(o.paymentStatus),
            ]),
            const SizedBox(height: 4),
            MoneyRow(context.t('Paid'), money(o.amountPaid, currency, lang)),
            if (o.balanceDue > 0) MoneyRow(context.t('Balance due'), money(o.balanceDue, currency, lang)),
            if (o.paymentMethod != null) InfoRow(icon: Icons.payments_rounded, label: context.t('Method'), value: context.t(o.paymentMethod!.label)),
            if (o.paymentStatus != PaymentStatus.paid && o.status != OrderStatus.cancelled) ...[
              const SizedBox(height: 8),
              Text(context.t('Payment is collected on delivery.'),
                  style: TextStyle(color: AppColors.faint, fontSize: 12.5, fontStyle: FontStyle.italic)),
            ],
          ]),
        ),

        if (o.notes != null && o.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _AccordionSection(title: context.t('Notes'), child: Text(o.notes!, style: TextStyle(color: AppColors.inkSoft, height: 1.4))),
        ],

        const SizedBox(height: 12),
        // Activity timeline
        _AccordionSection(
          title: context.t('Activity'),
          child: _timeline.isEmpty
              ? Text(context.t('No activity yet'), style: TextStyle(color: AppColors.muted))
              : OrderTimeline(events: _timeline),
        ),
      ],
    );
  }

  // Pinned bottom CTA for the delivery-time step (the one high-value action on this screen).
  Widget _deliveryCta(OrderDetail o) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: ElevatedButton.icon(
        onPressed: _busy ? null : _chooseDelivery,
        icon: _busy
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : const Icon(Icons.local_shipping_rounded),
        label: Text(context.t(o.deliveryAt == null ? 'Choose delivery time' : 'Change delivery time')),
        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, {bool danger = false}) {
    final c = danger ? AppColors.danger : AppColors.ink;
    return Row(children: [
      Icon(icon, size: 19, color: c),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _hero(OrderDetail o, String currency, String lang) {
    return BrandHero(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(o.orderNumber,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(statusIcon(o.status), color: Colors.white, size: 15),
              const SizedBox(width: 5),
              Text(context.t(o.status.label), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Text(money(o.total, currency, lang), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          if (o.isExpress)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
                Text(context.t('Express'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
              ]),
            ),
          const Spacer(),
          Text('${o.items.length} ${context.t(o.items.length == 1 ? 'item' : 'items')}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      ]),
    );
  }

  Widget _readyBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.glow(AppColors.gold),
      ),
      child: Row(children: [
        const Icon(Icons.celebration_rounded, color: Colors.white, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('Your order is ready!'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(context.t('Choose a delivery time below.'), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _offTrack(OrderDetail o) {
    final cancelled = o.status == OrderStatus.cancelled;
    final c = cancelled ? AppColors.danger : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(children: [
        Icon(cancelled ? Icons.cancel_rounded : Icons.pause_circle_rounded, color: c),
        const SizedBox(width: 12),
        Expanded(
          child: Text(cancelled ? context.t('This order was cancelled.') : context.t('This order is on hold.'),
              style: TextStyle(color: c, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _itemRow(OrderItem it, String currency, String lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(7)),
          child: Text('${it.quantity}×', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.serviceName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            if (it.notes != null && it.notes!.trim().isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(it.notes!, style: TextStyle(color: AppColors.muted, fontSize: 12))),
          ]),
        ),
        const SizedBox(width: 8),
        Text(money(it.lineTotal, currency, lang), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ]),
    );
  }

  String _fmt(DateTime dt, String lang) => DateFormat('EEE, d MMM · HH:mm', lang).format(dt);
}

/// A collapsible card styled like the app's soft cards: a tappable header
/// (title + rotating chevron) over an animated expand/collapse body.
class _AccordionSection extends StatefulWidget {
  const _AccordionSection({required this.title, required this.child, this.initiallyExpanded = false});
  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<_AccordionSection> createState() => _AccordionSectionState();
}

class _AccordionSectionState extends State<_AccordionSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Expanded(
                  child: Text(widget.title,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppColors.ink)),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
                ),
              ]),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: widget.child,
          ),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeInOut,
          alignment: Alignment.topCenter,
        ),
      ]),
    );
  }
}
