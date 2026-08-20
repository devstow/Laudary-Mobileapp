import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../l10n/l10n.dart';
import '../../models/service_item.dart';
import '../../services/api_exception.dart';
import '../../services/order_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/quantity_stepper.dart';
import '../../widgets/ui.dart';

typedef ServiceSelection = ({Map<String, int> qty, Map<String, ServiceItem> byId});

/// A searchable, lazily-paginated catalog picker — stays fast with 1,000+ services.
/// Selections persist across searches/pages (kept by id), and are returned on Done.
class ServicePickerScreen extends StatefulWidget {
  const ServicePickerScreen({super.key, required this.initial, required this.byId});
  final Map<String, int> initial;
  final Map<String, ServiceItem> byId;

  @override
  State<ServicePickerScreen> createState() => _ServicePickerScreenState();
}

class _ServicePickerScreenState extends State<ServicePickerScreen> {
  static const _pageSize = 20;
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  late final Map<String, int> _qty = {...widget.initial};
  late final Map<String, ServiceItem> _byId = {...widget.byId};

  final List<ServiceItem> _items = [];
  String _q = '';
  int _page = 1;
  bool _loading = true, _loadingMore = false, _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    }
    try {
      final res = await context.read<OrderService>().services(q: _q, page: _page, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(res);
        for (final s in res) {
          _byId[s.id] = s;
        }
        _hasMore = res.length == _pageSize;
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
    if (_loadingMore || _loading || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _page++;
    });
    await _load();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _q = v.trim();
      _load(reset: true);
    });
  }

  int get _selectedCount => _qty.values.where((q) => q > 0).length;
  double get _total {
    var t = 0.0;
    _qty.forEach((id, q) => t += (_byId[id]?.basePrice ?? 0) * q);
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().locale.code;
    final currency = context.watch<AppState>().currency;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('Select services'))),
      bottomNavigationBar: _bottomBar(lang, currency),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: context.t('Search services'),
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          _q = '';
                          _load(reset: true);
                        }),
              ),
            ),
          ),
          Expanded(child: _list(lang, currency)),
        ],
      ),
    );
  }

  Widget _list(String lang, String currency) {
    if (_loading) return const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 0), child: SkeletonList());
    if (_error != null) return ErrorView(_error!, onRetry: () => _load(reset: true));
    if (_items.isEmpty) {
      return EmptyView(
        _q.isEmpty ? context.t('No services available') : context.t('No services match your search'),
        icon: Icons.local_laundry_service_rounded,
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount: _items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == _items.length) {
          if (!_hasMore) return const SizedBox(height: 4);
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
          );
        }
        final s = _items[i];
        return _ServiceRow(
          service: s,
          lang: lang,
          currency: currency,
          qty: _qty[s.id] ?? 0,
          onChanged: (q) => setState(() => q <= 0 ? _qty.remove(s.id) : _qty[s.id] = q),
        );
      },
    );
  }

  Widget _bottomBar(String lang, String currency) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('$_selectedCount ${context.t('selected')}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(money(_total, currency, lang), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.ink)),
          ]),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop<ServiceSelection>((qty: _qty, byId: _byId)),
              child: Text(context.t('Done')),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, required this.lang, required this.currency, required this.qty, required this.onChanged});
  final ServiceItem service;
  final String lang;
  final String currency;
  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: selected ? AppColors.primary : AppColors.line, width: selected ? 1.4 : 1),
        boxShadow: selected ? null : AppShadows.soft,
      ),
      child: Row(children: [
        _ServiceThumb(url: service.imageUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(service.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            if ((service.category ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(service.category!, style: TextStyle(color: AppColors.faint, fontSize: 11.5)),
              ),
            const SizedBox(height: 3),
            Text('${money(service.basePrice, currency, lang)} / ${context.t(service.unit.label)}',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
            if (qty > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${context.t('Line total')}: ${money(service.basePrice * qty, currency, lang)}',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
          ]),
        ),
        const SizedBox(width: 10),
        if (qty == 0)
          IconButton.filledTonal(
            onPressed: () => onChanged(1),
            icon: const Icon(Icons.add_rounded),
            style: IconButton.styleFrom(backgroundColor: AppColors.primarySoft, foregroundColor: AppColors.primary),
          )
        else
          QuantityStepper(value: qty, onChanged: onChanged, min: 0),
      ]),
    );
  }
}

/// Square service thumbnail with a graceful icon fallback (no image, or load error).
class _ServiceThumb extends StatelessWidget {
  const _ServiceThumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final resolved = AppConfig.mediaUrl(url);
    final fallback = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Icon(Icons.local_laundry_service_rounded, color: AppColors.primary, size: 22),
    );
    if (resolved == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Image.network(
        resolved,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
