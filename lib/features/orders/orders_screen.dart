import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../services/api_exception.dart';
import '../../services/order_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/order_card.dart';
import '../../widgets/ui.dart';
import 'order_details_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const _pageSize = 15;
  static const _statusFilters = <OrderStatus?>[
    null,
    OrderStatus.placed,
    OrderStatus.pickupScheduled,
    OrderStatus.inProcess,
    OrderStatus.ready,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
    OrderStatus.cancelled,
  ];

  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  String _q = '';
  OrderStatus? _status;
  OrderType? _type;

  final List<OrderListItem> _items = [];
  Map<OrderStatus, int> _counts = const {};
  int _page = 1;
  int _totalFiltered = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
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
            q: _q.isEmpty ? null : _q,
            status: _status?.value,
            type: _type?.value,
            page: _page,
            pageSize: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(res.items);
        _counts = res.statusCounts;
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

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _q = v.trim();
      _load(reset: true);
    });
  }

  void _setStatus(OrderStatus? s) {
    setState(() => _status = s);
    _load(reset: true);
  }

  void _setType(OrderType? t) {
    setState(() => _type = t);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('My Orders')),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _searchBar(),
            _statusBar(),
            const SizedBox(height: 8),
            Expanded(child: _list()),
          ],
        ),
      ),
    );
  }

  /// The amber square filter button beside the search box (Claundry style) — opens the
  /// existing service-type menu.
  Widget _typeMenu() {
    final active = _type != null;
    return PopupMenuButton<OrderType?>(
      tooltip: context.t('Service type'),
      onSelected: _setType,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      itemBuilder: (context) => [
        _typeItem(null, context.t('All types')),
        _typeItem(OrderType.pickupAndDelivery, context.t('Pickup & Delivery')),
        _typeItem(OrderType.walkIn, context.t('Walk-in')),
      ],
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: AppColors.goldGradient,
          borderRadius: BorderRadius.circular(AppRadius.control),
          boxShadow: AppShadows.glow(AppColors.goldDark),
        ),
        child: Stack(alignment: Alignment.center, children: [
          const Icon(Icons.tune_rounded, color: AppColors.onGold, size: 22),
          if (active)
            PositionedDirectional(
              top: 9,
              end: 9,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: AppColors.gold, width: 1.5)),
              ),
            ),
        ]),
      ),
    );
  }

  PopupMenuItem<OrderType?> _typeItem(OrderType? t, String label) => PopupMenuItem(
        value: t,
        child: Row(children: [
          Icon(_type == t ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18, color: _type == t ? AppColors.primary : AppColors.faint),
          const SizedBox(width: 10),
          Text(label),
        ]),
      );

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Row(children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.control), boxShadow: AppShadows.soft),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: context.t('Search order number'),
                prefixIcon: const Icon(Icons.search_rounded),
                fillColor: AppColors.surface,
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          _q = '';
                          _load(reset: true);
                        },
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _typeMenu(),
      ]),
    );
  }

  Widget _statusBar() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        clipBehavior: Clip.none,
        itemCount: _statusFilters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = _statusFilters[i];
          return FilterPill(
            label: f == null ? context.t('All') : context.t(f.label),
            selected: f == _status,
            count: f == null ? null : (_counts[f] ?? 0),
            onTap: () => _setStatus(f),
          );
        },
      ),
    );
  }

  // Leaves room for the floating bottom bar when this screen is a Home tab.
  static const _bottomPad = 116.0;

  Widget _list() {
    if (_loading) return const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 0), child: SkeletonList());
    if (_error != null) return ErrorView(_error!, onRetry: () => _load(reset: true));
    if (_items.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 60),
        EmptyView(
          _q.isNotEmpty || _status != null || _type != null ? context.t('No orders match your filters') : context.t('No orders yet'),
          icon: Icons.local_laundry_service_rounded,
        ),
      ]);
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, _bottomPad),
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
