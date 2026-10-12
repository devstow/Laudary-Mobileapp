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
  String? _numberError;
  String? _phoneError;

  @override
  void dispose() {
    _number.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    final n = _number.text.trim();
    final phone = _phone.text.trim();
    // Both are required: the phone on the order identifies it (and guards against enumeration).
    setState(() {
      _numberError = n.isEmpty ? context.t('Enter your order number.') : null;
      _phoneError = phone.isEmpty ? context.t('Enter the phone number used on the order.') : null;
    });
    if (_numberError != null || _phoneError != null) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; _result = null; _notFound = false; });
    try {
      final r = await context.read<OrderService>().track(number: n, phone: phone);
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
            // Blue lookup card (Claundry delivery-card look) with white inputs + amber CTA.
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(AppRadius.card + 2),
                boxShadow: AppShadows.glow(AppColors.primary),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                PositionedDirectional(
                  end: -50,
                  top: -50,
                  child: IgnorePointer(
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 16),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 23),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.t('Track your order'),
                                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 2),
                              Text(context.t('Enter your order number and phone to see live status'),
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 12.5, height: 1.3)),
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _number,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) { if (_numberError != null) setState(() => _numberError = null); },
                        decoration: InputDecoration(
                          hintText: context.t('Order number'),
                          prefixIcon: const Icon(Icons.tag_rounded),
                          errorText: _numberError,
                          fillColor: AppColors.surface,
                          errorStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _track(),
                        onChanged: (_) { if (_phoneError != null) setState(() => _phoneError = null); },
                        decoration: InputDecoration(
                          hintText: context.t('Phone'),
                          prefixIcon: const Icon(Icons.phone_outlined),
                          errorText: _phoneError,
                          fillColor: AppColors.surface,
                          errorStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        amber: true,
                        busy: _busy,
                        onPressed: _track,
                        icon: Icons.search_rounded,
                        label: context.t('Track order'),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            if (_error != null) ErrorView(_error!, onRetry: _track),
            if (_notFound)
              EmptyView(
                context.t('Order not found'),
                icon: Icons.search_off_rounded,
                hint: context.t('Check the order number and phone, then try again'),
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
                  Container(
                    width: 46,
                    height: 46,
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(14)),
                    child: Icon(statusIcon(data.status), color: Colors.white, size: 22),
                  ),
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
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
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
