import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/delivery.dart';
import '../../models/enums.dart';
import '../../services/api_exception.dart';
import '../../services/delivery_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/driver_task_card.dart';
import '../../widgets/ui.dart';
import 'driver_task_detail_screen.dart';
import 'geofence.dart';

class DriverTasksScreen extends StatefulWidget {
  const DriverTasksScreen({super.key, this.initialGroup = TaskGroup.all, this.initialType, this.initialPriority});
  final TaskGroup initialGroup;
  final DeliveryType? initialType;
  final TaskUrgency? initialPriority;
  @override
  State<DriverTasksScreen> createState() => _DriverTasksScreenState();
}

class _DriverTasksScreenState extends State<DriverTasksScreen> {
  static const _pageSize = 15;
  static const _groups = TaskGroup.values;

  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  late final GeofenceHeartbeat _geofence = GeofenceHeartbeat(context.read<DeliveryService>());
  Timer? _debounce;

  String _q = '';
  late TaskGroup _group = widget.initialGroup;
  late DeliveryType? _type = widget.initialType;
  late TaskUrgency? _priority = widget.initialPriority;
  DateTime? _scheduledOn;
  DateTime? _assignedOn;

  final List<DeliveryTask> _items = [];
  DriverTaskPage? _page;
  int _pageNum = 1;
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
    _debounce?.cancel();
    _geofence.dispose();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters => _q.isNotEmpty || _type != null || _priority != null || _scheduledOn != null || _assignedOn != null;

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _pageNum = 1;
      });
    }
    try {
      final res = await context.read<DeliveryService>().myTasks(
            q: _q.isEmpty ? null : _q,
            group: _group,
            type: _type?.value,
            priority: _priority?.index,
            scheduledOn: _scheduledOn,
            assignedOn: _assignedOn,
            page: _pageNum,
            pageSize: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(res.items);
        _page = res;
        _loading = false;
        _loadingMore = false;
      });
      _syncGeofence();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) _error = ApiException.from(e).message;
      });
    }
  }

  void _syncGeofence() {
    _geofence.sync(
      hasInTransit: _items.any((t) => t.status == DeliveryStatus.inTransit),
      onArrived: (orders) {
        if (!mounted) return;
        showToast(context, '${context.t('Arrived at')} ${orders.join(', ')}');
        _load(reset: true);
      },
    );
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _page == null || _items.length >= _page!.totalFiltered) return;
    setState(() {
      _loadingMore = true;
      _pageNum++;
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

  void _setGroup(TaskGroup g) {
    setState(() => _group = g);
    _load(reset: true);
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        type: _type,
        priority: _priority,
        scheduledOn: _scheduledOn,
        assignedOn: _assignedOn,
        onApply: (t, p, s, a) {
          setState(() {
            _type = t;
            _priority = p;
            _scheduledOn = s;
            _assignedOn = a;
          });
          _load(reset: true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('My Tasks')),
        actions: [
          IconButton(
            tooltip: context.t('Filters'),
            onPressed: _openFilters,
            icon: Icon(Icons.tune_rounded, color: _hasActiveFilters ? AppColors.primary : AppColors.ink),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          _searchBar(),
          _tabs(),
          const SizedBox(height: 4),
          Expanded(child: _list()),
        ]),
      ),
    );
  }

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
        child: TextField(
          controller: _searchCtrl,
          onChanged: _onSearch,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.t('Order #, customer or address'),
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
      );

  Widget _tabs() => SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _groups.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final g = _groups[i];
            return FilterPill(
              label: context.t(g.label),
              selected: g == _group,
              count: _page?.countFor(g),
              onTap: () => _setGroup(g),
            );
          },
        ),
      );

  Widget _list() {
    if (_loading) return const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 0), child: SkeletonList());
    if (_error != null) return ErrorView(_error!, onRetry: () => _load(reset: true));
    if (_items.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 60),
        EmptyView(_hasActiveFilters ? context.t('No tasks found') : context.t('No tasks yet'), icon: Icons.local_shipping_outlined),
      ]);
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == _items.length) {
            final total = _page?.totalFiltered ?? _items.length;
            final more = _items.length < total;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(children: [
                if (more)
                  _loadingMore
                      ? const Padding(padding: EdgeInsets.all(6), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))
                      : OutlinedButton(onPressed: _loadMore, child: Text(context.t('Load more'))),
                const SizedBox(height: 8),
                Text('${context.t('Showing')} ${_items.length} ${context.t('of')} $total',
                    style: TextStyle(color: AppColors.faint, fontSize: 12.5)),
              ]),
            );
          }
          final t = _items[i];
          return DriverTaskCard(
            task: t,
            compact: true,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DriverTaskDetailScreen(task: t)));
              if (mounted) _load(reset: true);
            },
          );
        },
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.type, required this.priority, required this.scheduledOn, required this.assignedOn, required this.onApply});
  final DeliveryType? type;
  final TaskUrgency? priority;
  final DateTime? scheduledOn;
  final DateTime? assignedOn;
  final void Function(DeliveryType?, TaskUrgency?, DateTime?, DateTime?) onApply;
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late DeliveryType? _type = widget.type;
  late TaskUrgency? _priority = widget.priority;
  late DateTime? _sched = widget.scheduledOn;
  late DateTime? _assigned = widget.assignedOn;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 42, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
          Text(context.t('Filters'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 16),
          _label(context.t('Task type')),
          Wrap(spacing: 8, children: [
            _chip(context.t('All types'), _type == null, () => setState(() => _type = null)),
            _chip(context.t('Pickup'), _type == DeliveryType.pickup, () => setState(() => _type = DeliveryType.pickup)),
            _chip(context.t('Delivery'), _type == DeliveryType.delivery, () => setState(() => _type = DeliveryType.delivery)),
          ]),
          const SizedBox(height: 14),
          _label(context.t('Priority')),
          Wrap(spacing: 8, children: [
            _chip(context.t('Any priority'), _priority == null, () => setState(() => _priority = null)),
            _chip(context.t('Overdue'), _priority == TaskUrgency.overdue, () => setState(() => _priority = TaskUrgency.overdue)),
            _chip(context.t('Due today'), _priority == TaskUrgency.today, () => setState(() => _priority = TaskUrgency.today)),
            _chip(context.t('Upcoming'), _priority == TaskUrgency.upcoming, () => setState(() => _priority = TaskUrgency.upcoming)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _dateField(context.t('Scheduled date'), _sched, df, (d) => setState(() => _sched = d))),
            const SizedBox(width: 12),
            Expanded(child: _dateField(context.t('Assigned date'), _assigned, df, (d) => setState(() => _assigned = d))),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  widget.onApply(null, null, null, null);
                  Navigator.of(context).pop();
                },
                child: Text(context.t('Reset')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () {
                  widget.onApply(_type, _priority, _sched, _assigned);
                  Navigator.of(context).pop();
                },
                child: Text(context.t('Apply')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5)));

  Widget _chip(String label, bool selected, VoidCallback onTap) => FilterPill(label: label, selected: selected, onTap: onTap);

  Widget _dateField(String label, DateTime? value, DateFormat df, ValueChanged<DateTime?> onPick) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(label),
      InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: () async {
          final now = DateTime.now();
          final d = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 60)), lastDate: now.add(const Duration(days: 60)), initialDate: value ?? now);
          if (d != null) onPick(d);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: AppColors.line)),
          child: Row(children: [
            Icon(Icons.event_rounded, size: 17, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(value == null ? context.t('Any') : df.format(value), style: TextStyle(fontSize: 13, color: value == null ? AppColors.faint : AppColors.ink))),
            if (value != null) InkWell(onTap: () => onPick(null), child: Icon(Icons.close_rounded, size: 16, color: AppColors.faint)),
          ]),
        ),
      ),
    ]);
  }
}
