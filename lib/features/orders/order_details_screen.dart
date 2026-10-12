import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../l10n/l10n.dart';
import '../../models/ai.dart';
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
import '../assistant/assistant_screen.dart';
import '../invoice/invoice_screen.dart';
import '../receipt/receipt_screen.dart';
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

  void _viewReceipt() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReceiptScreen(orderId: widget.orderId, orderNumber: _order?.orderNumber ?? widget.orderNumber),
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
            ? [_assistant()]
            : [
                _assistant(),
                IconButton(
                  icon: const Icon(Icons.description_rounded),
                  tooltip: context.t('View invoice'),
                  onPressed: _viewInvoice,
                ),
                // A receipt exists only once payment is fully completed (same rule as web/portal).
                if (o.paymentStatus == PaymentStatus.paid)
                  IconButton(
                    icon: const Icon(Icons.receipt_long_rounded),
                    tooltip: context.t('View receipt'),
                    onPressed: _viewReceipt,
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
            icon: Icons.route_rounded,
            child: Padding(padding: const EdgeInsets.only(top: 4), child: JourneyStepper(status: o.status, type: o.type)),
          ),
          const SizedBox(height: 12),
        ],

        // Pickup & delivery (map + addresses + contact)
        if (o.hasPickupPin || o.pickupAddress != null || o.contactPhone != null) ...[
          _AccordionSection(
            title: context.t('Pickup & delivery'),
            icon: Icons.location_on_rounded,
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
          icon: Icons.checkroom_rounded,
          initiallyExpanded: true,
          child: Column(children: [for (final it in o.items) _itemRow(it, currency, lang)]),
        ),
        const SizedBox(height: 12),

        // Payment (merged: cost breakdown + payment state in one card)
        _AccordionSection(
          title: context.t('Payment'),
          icon: Icons.account_balance_wallet_rounded,
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
          _AccordionSection(title: context.t('Notes'), icon: Icons.sticky_note_2_rounded, child: Text(o.notes!, style: TextStyle(color: AppColors.inkSoft, height: 1.4))),
        ],

        const SizedBox(height: 12),
        // Activity timeline
        _AccordionSection(
          title: context.t('Activity'),
          icon: Icons.history_rounded,
          child: _timeline.isEmpty
              ? Text(context.t('No activity yet'), style: TextStyle(color: AppColors.muted))
              : OrderTimeline(events: _timeline),
        ),
      ],
    );
  }

  // Pinned bottom CTA for the delivery-time step (the one high-value action on this screen).
  Widget _deliveryCta(OrderDetail o) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        boxShadow: AppShadows.card,
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: PrimaryButton(
          onPressed: _chooseDelivery,
          busy: _busy,
          icon: Icons.local_shipping_rounded,
          label: context.t(o.deliveryAt == null ? 'Choose delivery time' : 'Change delivery time'),
        ),
      ),
    );
  }

  // Opens the assistant about THIS order ("Where is this order?", "Cancel this order").
  Widget _assistant() => AssistantButton(
        plain: true,
        pageContext: AiPageContext(module: 'my_orders', recordType: 'order', recordId: widget.orderId),
      );

  Widget _menuItem(IconData icon, String label, {bool danger = false}) {
    final c = danger ? AppColors.danger : AppColors.ink;
    return Row(children: [
      Icon(icon, size: 19, color: c),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    ]);
  }

  /// How far along the order is (0..1) for the progress ring — same 5-stage collapse
  /// the tracking stepper uses.
  double _progress(OrderStatus s) {
    switch (s) {
      case OrderStatus.delivered:
        return 1;
      case OrderStatus.outForDelivery:
        return 0.8;
      case OrderStatus.ready:
        return 0.6;
      case OrderStatus.inProcess:
      case OrderStatus.atFacility:
      case OrderStatus.pickedUp:
        return 0.4;
      case OrderStatus.cancelled:
      case OrderStatus.onHold:
        return 1;
      default:
        return 0.2;
    }
  }

  /// Claundry "Order Details" header: a progress ring around the status icon, then the
  /// order summary and a soft-blue info panel.
  Widget _hero(OrderDetail o, String currency, String lang) {
    final c = statusColor(o.status);
    final p = _progress(o.status);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      child: Column(children: [
        SizedBox(
          width: 132,
          height: 132,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: p),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: 9,
                  strokeCap: StrokeCap.round,
                  color: c,
                  backgroundColor: c.withValues(alpha: 0.12),
                ),
              ),
            ),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(color: c.withValues(alpha: 0.25), width: 2),
              ),
              child: Icon(statusIcon(o.status), color: c, size: 40),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        StatusChip(o.status),
        const SizedBox(height: 10),
        Text(o.orderNumber,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.ink, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(money(o.total, currency, lang),
                style: const TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.w900)),
            Text('·', style: TextStyle(color: AppColors.faint)),
            Text('${o.items.length} ${context.t(o.items.length == 1 ? 'item' : 'items')}',
                style: TextStyle(color: AppColors.muted, fontSize: 13.5, fontWeight: FontWeight.w600)),
            if (o.isExpress)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bolt_rounded, size: 13, color: AppColors.onGold),
                  Text(context.t('Express'), style: const TextStyle(color: AppColors.onGold, fontWeight: FontWeight.w800, fontSize: 11)),
                ]),
              ),
          ],
        ),
        if (o.pickupAt != null || o.deliveryAt != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Column(children: [
              if (o.pickupAt != null) _panelRow(context.t('Pickup time'), _fmt(o.pickupAt!, lang)),
              if (o.deliveryAt != null) _panelRow(context.t('Delivery time'), _fmt(o.deliveryAt!, lang)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _panelRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text('$label :', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 12.5)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ),
        ]),
      );

  Widget _readyBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.glow(AppColors.goldDark),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.celebration_rounded, color: AppColors.onGold, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('Your order is ready!'),
                style: const TextStyle(color: AppColors.onGold, fontWeight: FontWeight.w900, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(context.t('Choose a delivery time below.'),
                style: TextStyle(color: AppColors.onGold.withValues(alpha: 0.8), fontSize: 12.5, fontWeight: FontWeight.w500)),
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
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
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

  /// Claundry "My Bag" style item row: round thumb, name + unit line, qty badge, total.
  Widget _itemRow(OrderItem it, String currency, String lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _itemThumb(it.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.serviceName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
              if (it.notes != null && it.notes!.trim().isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(it.notes!, style: TextStyle(color: AppColors.muted, fontSize: 12))),
              const SizedBox(height: 3),
              Text(money(it.lineTotal, currency, lang),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.primary)),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.line),
            ),
            child: Text('×${it.quantity}', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  Widget _itemThumb(String? url) {
    final resolved = AppConfig.mediaUrl(url);
    final fallback = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
      child: const Icon(Icons.local_laundry_service_rounded, color: AppColors.primary, size: 21),
    );
    if (resolved == null) return fallback;
    return ClipOval(
      child: Image.network(resolved, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }

  String _fmt(DateTime dt, String lang) => DateFormat('EEE, d MMM · HH:mm', lang).format(dt);
}

/// A collapsible card styled like the app's soft cards: a tappable header
/// (icon tile + title + rotating chevron) over an animated expand/collapse body.
class _AccordionSection extends StatefulWidget {
  const _AccordionSection({required this.title, required this.child, this.initiallyExpanded = false, this.icon});
  final String title;
  final Widget child;
  final bool initiallyExpanded;
  final IconData? icon;

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
              padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
              child: Row(children: [
                if (widget.icon != null) ...[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(11)),
                    child: Icon(widget.icon, color: AppColors.primary, size: 19),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(widget.title,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink)),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(9)),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.muted, size: 20),
                  ),
                ),
              ]),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
