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

  Widget _summary(String lang) {
    final cur = context.read<AppState>().currency; // tenant currency, like the web
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Row(children: [
          Expanded(child: _stat(context.t('Billed'), money(_billed, cur, lang), AppColors.ink)),
          _divider(),
          Expanded(child: _stat(context.t('Paid'), money(_paid, cur, lang), AppColors.success)),
          _divider(),
          Expanded(child: _stat(context.t('Outstanding'), money(_outstanding, cur, lang), AppColors.danger)),
        ]),
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 40, color: AppColors.line);

  Widget _stat(String label, String value, Color color) => Column(children: [
        Text(value, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ]);

  Widget _paymentBar() {
    String label(PaymentStatus? p) => p == null ? context.t('All') : context.t(p.label);
    return SizedBox(
      height: 40,
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
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 100),
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
