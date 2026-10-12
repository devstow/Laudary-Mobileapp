import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../services/api_exception.dart';
import '../../services/order_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/order_card.dart';
import '../../widgets/ui.dart';
import '../orders/order_details_screen.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  static const _pageSize = 15;
  static const _paymentFilters = <PaymentStatus?>[null, PaymentStatus.unpaid, PaymentStatus.partial, PaymentStatus.paid];

  final _scroll = ScrollController();
  PaymentStatus? _payment;

  final List<OrderListItem> _items = [];
  double _billed = 0, _paid = 0, _outstanding = 0;
  int _page = 1, _totalFiltered = 0;
  bool _loading = true, _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    }
    try {
      final res = await context.read<OrderService>().myOrders(
            payment: _payment?.value,
            page: _page,
            pageSize: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(res.items);
        _billed = res.totalBilled;
        _paid = res.totalPaid;
        _outstanding = res.outstanding;
        _totalFiltered = res.totalFiltered;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) _error = ApiException.from(e).message;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _items.length >= _totalFiltered) return;
    setState(() {
      _loadingMore = true;
      _page++;
    });
    await _load();
  }

  void _setPayment(PaymentStatus? p) {
    setState(() => _payment = p);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().locale.code;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Payments'))),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(child: _summary(lang)),
              SliverToBoxAdapter(child: _paymentBar()),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              _sliverBody(),
            ],
          ),
        ),
      ),
    );
  }

  /// Claundry "card" visual: a blue gradient wallet card with the outstanding balance
  /// up top and billed / paid underneath.
  Widget _summary(String lang) {
    final cur = context.read<AppState>().currency; // tenant currency, like the web
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(AppRadius.card + 2),
          boxShadow: AppShadows.glow(AppColors.primary),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          PositionedDirectional(end: -40, top: -50, child: _ring(170)),
          PositionedDirectional(end: 40, bottom: -70, child: _ring(130)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 38,
                  height: 30,
                  decoration: BoxDecoration(gradient: AppColors.goldGradient, borderRadius: BorderRadius.circular(7)),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.onGold, size: 18),
                ),
                const Spacer(),
                Text(context.t('Payments'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w800, fontSize: 13)),
              ]),
              const SizedBox(height: 18),
              Text(context.t('Outstanding'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(money(_outstanding, cur, lang),
                    style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.control)),
                child: Row(children: [
                  Expanded(child: _stat(context.t('Billed'), money(_billed, cur, lang))),
                  Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.25)),
                  const SizedBox(width: 14),
                  Expanded(child: _stat(context.t('Paid'), money(_paid, cur, lang))),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  static Widget _ring(double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 16),
          ),
        ),
      );

  Widget _stat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ]);

  Widget _paymentBar() {
    String label(PaymentStatus? p) => p == null ? context.t('All') : context.t(p.label);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _paymentFilters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => FilterPill(
          label: label(_paymentFilters[i]),
          selected: _paymentFilters[i] == _payment,
          onTap: () => _setPayment(_paymentFilters[i]),
        ),
      ),
    );
  }

  Widget _sliverBody() {
    if (_loading) {
      return const SliverPadding(padding: EdgeInsets.fromLTRB(20, 8, 20, 0), sliver: SliverToBoxAdapter(child: SkeletonList()));
    }
    if (_error != null) {
      return SliverFillRemaining(hasScrollBody: false, child: ErrorView(_error!, onRetry: () => _load(reset: true)));
    }
    if (_items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyView(context.t('No payments to show'), icon: Icons.account_balance_wallet_outlined),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 116),
      sliver: SliverList.separated(
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == _items.length) {
            final more = _items.length < _totalFiltered;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(children: [
                if (more)
                  _loadingMore
                      ? const Padding(padding: EdgeInsets.all(6), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))
                      : OutlinedButton(onPressed: _loadMore, child: Text(context.t('Load more'))),
                const SizedBox(height: 8),
                Text('${context.t('Showing')} ${_items.length} ${context.t('of')} $_totalFiltered',
                    style: TextStyle(color: AppColors.faint, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(context.t('Payment is collected on delivery.'),
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.faint, fontSize: 12)),
              ]),
            );
          }
          final o = _items[i];
          return OrderCard(o, onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OrderDetailsScreen(orderId: o.id, orderNumber: o.orderNumber)));
            if (mounted) _load(reset: true);
          });
        },
      ),
    );
  }
}
