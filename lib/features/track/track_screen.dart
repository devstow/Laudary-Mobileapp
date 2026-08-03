import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../services/api_exception.dart';
import '../../services/order_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/order_timeline.dart';
import '../../widgets/track_stepper.dart';
import '../../widgets/ui.dart';

class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key});
  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  final _number = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;
  OrderTracking? _result;
  bool _notFound = false;

  @override
  void dispose() {
    _number.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    final n = _number.text.trim();
    if (n.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; _result = null; _notFound = false; });
    try {
      final tenant = context.read<AppState>().tenantIdentifier!;
      final phone = _phone.text.trim();
      final r = await context.read<OrderService>().track(tenant: tenant, number: n, phone: phone.isEmpty ? null : phone);
      setState(() { _result = r; _notFound = r == null; });
    } catch (e) {
      setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().locale.code;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Track'))),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            SoftCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                      child: const Icon(Icons.local_shipping_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.t('Track your order'), style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(context.t('Enter your order number to see live status'),
                              style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _number,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(hintText: context.t('Order number'), prefixIcon: const Icon(Icons.tag_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _track(),
                    decoration: InputDecoration(
                      hintText: context.t('Phone (optional)'),
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _track,
                    icon: _busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : const Icon(Icons.search_rounded, size: 20),
                    label: Text(context.t('Track order')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_error != null) ErrorView(_error!, onRetry: _track),
            if (_notFound)
              EmptyView(
                context.t('Order not found'),
                icon: Icons.search_off_rounded,
                hint: context.t('Check the order number and try again'),
              ),
            if (_result != null) _TrackResult(_result!, lang: lang),
          ],
        ),
      ),
    );
  }
}

class _TrackResult extends StatelessWidget {
  const _TrackResult(this.data, {required this.lang});
  final OrderTracking data;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<AppState>().currency; // tenant currency, like the web
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.t('Order number'), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        const SizedBox(height: 3),
                        Text(data.orderNumber,
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.ink, letterSpacing: -0.2)),
                      ],
                    ),
                  ),
                  StatusChip(data.status),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              MoneyRow(context.t('Total'), money(data.total, currency, lang), strong: true, accent: true),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // Progress stepper (or a closed-order alert), like the web Track page.
        if (_closed) _closedAlert(context) else SoftCard(child: TrackStepper(status: data.status)),
        if (data.readyByAt != null || data.deliveryAt != null) ...[
          const SizedBox(height: 12),
          _scheduleCard(context),
        ],
        const SizedBox(height: 18),
        SectionHeader(context.t('Order timeline')),
        const SizedBox(height: 12),
        SoftCard(
          child: data.timeline.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(context.t('No activity yet'), style: TextStyle(color: AppColors.muted)),
                )
              : OrderTimeline(events: data.timeline),
        ),
      ],
    );
  }

  bool get _closed => data.status == OrderStatus.cancelled || data.status == OrderStatus.onHold;

  Widget _closedAlert(BuildContext context) {
    final cancelled = data.status == OrderStatus.cancelled;
    final c = cancelled ? AppColors.danger : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Row(children: [
        Icon(cancelled ? Icons.cancel_rounded : Icons.pause_circle_rounded, color: c),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            cancelled
                ? context.t('This order was cancelled.')
                : context.t('This order is on hold — the laundry will contact you.'),
            style: TextStyle(color: c, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  Widget _scheduleCard(BuildContext context) {
    final df = DateFormat('MMM d, HH:mm', lang);
    return SoftCard(
      child: Column(children: [
        if (data.readyByAt != null)
          InfoRow(icon: Icons.schedule_rounded, label: context.t('Ready by'), value: df.format(data.readyByAt!)),
        if (data.deliveryAt != null)
          InfoRow(icon: Icons.local_shipping_rounded, label: context.t('Expected delivery'), value: df.format(data.deliveryAt!)),
      ]),
    );
  }
}
