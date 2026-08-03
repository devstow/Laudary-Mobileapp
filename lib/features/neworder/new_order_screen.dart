import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../models/map_settings.dart';
import '../../models/order_detail.dart';
import '../../models/service_item.dart';
import '../../services/api_exception.dart';
import '../../services/order_service.dart';
import '../../services/profile_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map_picker.dart';
import '../../widgets/map_viewer.dart';
import '../../widgets/quantity_stepper.dart';
import '../../widgets/ui.dart';
import 'service_picker_screen.dart';

class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({super.key, this.editOrder});

  /// When set, the screen edits this existing order instead of creating a new one.
  final OrderDetail? editOrder;

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  final Map<String, int> _qty = {};
  final Map<String, ServiceItem> _byId = {};

  DateTime? _pickupAt;
  LatLng? _pin;

  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  final _scroll = ScrollController();
  final _servicesKey = GlobalKey();
  final _timeKey = GlobalKey();

  MapSettings _mapSettings = MapSettings.fallback;
  bool _busy = false;
  bool _showErrors = false;

  bool get _isEdit => widget.editOrder != null;

  @override
  void initState() {
    super.initState();
    if (widget.editOrder != null) {
      _prefillFromOrder(widget.editOrder!);
    } else {
      _prefillFromProfile();
    }
    _loadMapSettings();
  }

  // Seed the form from an existing order for editing (services, pickup time, location, contact, notes).
  void _prefillFromOrder(OrderDetail o) {
    for (final it in o.items) {
      final sid = it.serviceId;
      if (sid == null) continue;
      _qty[sid] = it.quantity;
      _byId[sid] = ServiceItem(
        id: sid,
        name: it.serviceName,
        unit: ServiceUnit.perPiece,
        basePrice: it.unitPrice,
        currency: o.currency,
      );
    }
    _pickupAt = o.pickupAt;
    if (o.hasPickupPin) _pin = LatLng(o.pickupLat!, o.pickupLng!);
    _address.text = o.pickupAddress ?? '';
    _phone.text = o.contactPhone ?? '';
    _notes.text = o.notes ?? '';
  }

  Future<void> _prefillFromProfile() async {
    try {
      final p = await context.read<ProfileService>().get();
      if (!mounted) return;
      setState(() {
        if (_address.text.isEmpty && (p.address ?? '').isNotEmpty) _address.text = p.address!;
        if (_phone.text.isEmpty && (p.phone ?? '').isNotEmpty) _phone.text = p.phone!;
      });
    } catch (_) {/* best-effort */}
  }

  Future<void> _loadMapSettings() async {
    final s = await context.read<OrderService>().mapSettings();
    if (mounted) setState(() => _mapSettings = s);
  }

  @override
  void dispose() {
    _address.dispose();
    _phone.dispose();
    _notes.dispose();
    _scroll.dispose();
    super.dispose();
  }

  double get _estimate {
    var total = 0.0;
    _qty.forEach((id, q) => total += (_byId[id]?.basePrice ?? 0) * q);
    return total;
  }

  int get _serviceCount => _qty.values.where((q) => q > 0).length;
  bool get _hasServices => _serviceCount > 0;
  bool get _hasTime => _pickupAt != null;

  Future<void> _openServicePicker() async {
    final result = await Navigator.of(context).push<ServiceSelection>(
      MaterialPageRoute(builder: (_) => ServicePickerScreen(initial: _qty, byId: _byId)),
    );
    if (result == null || !mounted) return;
    setState(() {
      _qty
        ..clear()
        ..addAll(result.qty);
      _byId.addAll(result.byId);
    });
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
        context: context, firstDate: now, lastDate: now.add(const Duration(days: 30)), initialDate: _pickupAt ?? now);
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_pickupAt ?? now.add(const Duration(hours: 1))));
    if (time == null) return;
    setState(() => _pickupAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<PickedLocation>(MaterialPageRoute(
      builder: (_) => MapPickerScreen(
        settings: _mapSettings,
        initial: _pin,
        initialAddress: _address.text.trim().isEmpty ? null : _address.text.trim(),
      ),
    ));
    if (result == null || !mounted) return;
    setState(() {
      _pin = result.point;
      if (result.address.isNotEmpty) _address.text = result.address;
    });
  }

  Future<void> _review(String lang, String currency) async {
    setState(() => _showErrors = true);
    // Per-field validation (separate messages, like the web) — scroll to the first problem.
    if (!_hasServices) {
      _scrollTo(_servicesKey);
      return;
    }
    if (!_hasTime) {
      _scrollTo(_timeKey);
      return;
    }
    // Review & confirm step — a summary the customer approves before we place the order.
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfirmSheet(
        services: _qty.entries.where((e) => e.value > 0 && _byId[e.key] != null).map((e) => (item: _byId[e.key]!, qty: e.value)).toList(),
        estimate: _estimate,
        currency: currency,
        lang: lang,
        pickupAt: _pickupAt!,
        address: _address.text.trim(),
        pin: _pin,
        phone: _phone.text.trim(),
        notes: _notes.text.trim(),
        confirmLabel: context.t(_isEdit ? 'Save changes' : 'Request pickup'),
      ),
    );
    if (confirmed == true) await _book();
  }

  Future<void> _book() async {
    final items = _qty.entries
        .where((e) => e.value > 0)
        .map((e) => (serviceId: e.key, quantity: e.value, notes: null as String?))
        .toList();
    final addr = _address.text.trim().isEmpty ? null : _address.text.trim();
    final phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    setState(() => _busy = true);
    try {
      final svc = context.read<OrderService>();
      if (_isEdit) {
        await svc.updateOrder(
          orderId: widget.editOrder!.id,
          pickupAt: _pickupAt!, pickupAddress: addr, lat: _pin?.latitude, lng: _pin?.longitude,
          contactPhone: phone, notes: notes, items: items,
        );
      } else {
        await svc.bookPickup(
          pickupAt: _pickupAt!, pickupAddress: addr, lat: _pin?.latitude, lng: _pin?.longitude,
          contactPhone: phone, notes: notes, items: items,
        );
      }
      if (!mounted) return;
      showToast(context, _isEdit
          ? context.t('Your order has been updated.')
          : context.t("Your pickup request has been placed. We'll be in touch to collect your items."));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showToast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scrollTo(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().locale.code;
    final currency = context.watch<AppState>().currency;
    final df = DateFormat('EEE, d MMM · HH:mm', lang);

    return Scaffold(
      appBar: AppBar(title: Text(context.t(_isEdit ? 'Edit order' : 'Book a pickup'))),
      bottomNavigationBar: _bottomBar(lang, currency),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          // 1) Services
          Container(key: _servicesKey),
          _stepLabel('1', context.t('Choose your services')),
          const SizedBox(height: 12),
          _servicesSection(lang, currency),
          if (_showErrors && !_hasServices) _fieldError(context.t('Please add at least one service.')),

          const SizedBox(height: 24),
          // 2) Pickup location
          _stepLabel('2', context.t('Pickup location')),
          const SizedBox(height: 12),
          _locationSection(),

          const SizedBox(height: 24),
          // 3) Pickup time + contact
          Container(key: _timeKey),
          _stepLabel('3', context.t('Pickup time & contact')),
          const SizedBox(height: 12),
          _timeCard(df),
          if (_showErrors && !_hasTime) _fieldError(context.t('Please choose your preferred pickup time.')),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: 50,
            decoration: InputDecoration(
              labelText: context.t('Contact phone'),
              counterText: '',
              prefixIcon: const Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: context.t('Notes'),
              hintText: context.t('e.g. gate code, delicate items'),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 6),
          Text(context.t('Final price is confirmed by the laundry after inspection.'),
              style: TextStyle(color: AppColors.faint, fontSize: 12, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  // ── Services ────────────────────────────────────────────────────────────
  Widget _servicesSection(String lang, String currency) {
    final selected = _qty.entries.where((e) => e.value > 0).toList();
    return Column(
      children: [
        if (selected.isEmpty)
          SoftCard(
            onTap: _openServicePicker,
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.local_laundry_service_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('Add services'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(context.t('Search and pick what you need cleaned'), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.faint),
            ]),
          )
        else ...[
          ...selected.map((e) {
            final s = _byId[e.key];
            if (s == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SoftCard(
                padding: const EdgeInsets.all(13),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      const SizedBox(height: 3),
                      Text('${money(s.basePrice, currency, lang)} / ${context.t(s.unit.label)}  ·  ${context.t('Line total')} ${money(s.basePrice * e.value, currency, lang)}',
                          style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  QuantityStepper(value: e.value, min: 0, onChanged: (q) => setState(() => q <= 0 ? _qty.remove(e.key) : _qty[e.key] = q)),
                ]),
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: _openServicePicker,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(context.t('Add / edit services')),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      ],
    );
  }

  // ── Pickup location (multi-line address + map pin + lat/lng) ─────────────
  Widget _locationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _address,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: context.t('Pickup address'),
            hintText: context.t('Building, street, district'),
            counterText: '',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 10),
        if (_pin != null) ...[
          SoftCard(
            padding: const EdgeInsets.all(12),
            onTap: _pickLocation,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MapViewer(pickup: _pin, height: 140),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.my_location_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${context.t('Pinned at')} ${_pin!.latitude.toStringAsFixed(5)}, ${_pin!.longitude.toStringAsFixed(5)}',
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(onPressed: _pickLocation, child: Text(context.t('Change'))),
              ]),
            ]),
          ),
        ] else
          OutlinedButton.icon(
            onPressed: _pickLocation,
            icon: const Icon(Icons.add_location_alt_rounded, size: 20),
            label: Text(context.t('Pin location on map')),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
      ],
    );
  }

  Widget _stepLabel(String n, String title) {
    return Row(children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
        child: Text(n, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
      ),
      const SizedBox(width: 10),
      Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink)),
    ]);
  }

  Widget _fieldError(String msg) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, size: 15, color: AppColors.danger),
          const SizedBox(width: 6),
          Expanded(child: Text(msg, style: const TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _timeCard(DateFormat df) {
    final set = _pickupAt != null;
    final error = _showErrors && !set;
    return SoftCard(
      onTap: _pickTime,
      padding: const EdgeInsets.all(16),
      color: error ? AppColors.danger.withValues(alpha: 0.04) : null,
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.event_rounded, color: AppColors.goldDark, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(context.t('Preferred pickup time'), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const Text(' *', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 3),
            Text(set ? df.format(_pickupAt!) : context.t('Choose date & time'),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: set ? AppColors.ink : AppColors.faint)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: AppColors.faint),
      ]),
    );
  }

  Widget _bottomBar(String lang, String currency) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${context.t('Estimated')} · $_serviceCount ${context.t(_serviceCount == 1 ? 'service' : 'services')}',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(money(_estimate, currency, lang), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.ink)),
          ]),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _busy ? null : () => _review(lang, currency),
              child: _busy
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(context.t('Review & confirm')),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Review & confirm — a summary the customer approves before the order is placed.
class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.services,
    required this.estimate,
    required this.currency,
    required this.lang,
    required this.pickupAt,
    required this.address,
    required this.pin,
    required this.phone,
    required this.notes,
    required this.confirmLabel,
  });
  final List<({ServiceItem item, int qty})> services;
  final double estimate;
  final String currency;
  final String lang;
  final DateTime pickupAt;
  final String address;
  final LatLng? pin;
  final String phone;
  final String notes;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, d MMM yyyy · HH:mm', lang);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 42, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Text(context.t('Confirm your pickup'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 16),
            Text(context.t('Services').toUpperCase(),
                style: TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            ...services.map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(7)),
                      child: Text('${s.qty}×', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s.item.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text(money(s.item.basePrice * s.qty, currency, lang), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                )),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
            MoneyRow(context.t('Estimated total'), money(estimate, currency, lang), strong: true, accent: true),
            const SizedBox(height: 10),
            InfoRow(icon: Icons.event_rounded, label: context.t('Pickup time'), value: df.format(pickupAt)),
            if (address.isNotEmpty) InfoRow(icon: Icons.location_on_rounded, label: context.t('Pickup address'), value: address),
            if (pin != null)
              InfoRow(icon: Icons.my_location_rounded, label: context.t('Pinned at'),
                  value: '${pin!.latitude.toStringAsFixed(5)}, ${pin!.longitude.toStringAsFixed(5)}'),
            if (phone.isNotEmpty) InfoRow(icon: Icons.phone_rounded, label: context.t('Contact phone'), value: phone),
            if (notes.isNotEmpty) InfoRow(icon: Icons.sticky_note_2_outlined, label: context.t('Notes'), value: notes),
            const SizedBox(height: 10),
            Text(context.t('Payment is collected on delivery. Final price confirmed after inspection.'),
                style: TextStyle(color: AppColors.faint, fontSize: 12, fontStyle: FontStyle.italic)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.t('Back')))),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(confirmLabel),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
