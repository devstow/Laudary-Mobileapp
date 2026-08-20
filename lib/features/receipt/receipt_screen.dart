import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../models/order_receipt.dart';
import '../../services/api_exception.dart';
import '../../services/order_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// A POS/thermal-style native preview of an order's payment receipt (parity with the web receipt).
/// Supports downloading/opening the exact PDF the API renders.
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.orderId, this.orderNumber});
  final String orderId;
  final String? orderNumber;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  late Future<OrderReceipt> _future;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = context.read<OrderService>().receipt(widget.orderId);

  ({Color bg, Color fg}) _statusColors(OrderReceiptStatus s) {
    switch (s) {
      case OrderReceiptStatus.paid:
        return (bg: const Color(0xFF16A34A), fg: Colors.white);
      case OrderReceiptStatus.issued:
        return (bg: AppColors.gold, fg: Colors.white);
      case OrderReceiptStatus.voided:
        return (bg: AppColors.danger, fg: Colors.white);
      case OrderReceiptStatus.pending:
        return (bg: AppColors.line, fg: AppColors.muted);
    }
  }

  Future<void> _download(OrderReceipt r) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await context.read<OrderService>().receiptPdfBytes(widget.orderId);
      final name = (r.number == null || r.number!.isEmpty) ? r.orderNumber : r.number!;
      final file = File('${Directory.systemTemp.path}/Receipt-$name.pdf');
      await file.writeAsBytes(bytes, flush: true);
      final uri = Uri.file(file.path);
      var opened = false;
      if (await canLaunchUrl(uri)) {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (mounted && !opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.t('Saved')}: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiException.from(e).message)),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().locale.code;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Receipt')),
        actions: [
          FutureBuilder<OrderReceipt>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              return IconButton(
                tooltip: context.t('Download / Print'),
                icon: _downloading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                    : const Icon(Icons.download_rounded),
                onPressed: _downloading ? null : () => _download(snap.data!),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<OrderReceipt>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.all(20), child: SkeletonList(count: 3));
          }
          if (snap.hasError) return ErrorView(ApiException.from(snap.error!).message, onRetry: () => setState(_load));
          final r = snap.data!;
          return _ReceiptBody(r: r, lang: lang, statusColors: _statusColors);
        },
      ),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({required this.r, required this.lang, required this.statusColors});
  final OrderReceipt r;
  final String lang;
  final ({Color bg, Color fg}) Function(OrderReceiptStatus) statusColors;

  String _num(double v) => NumberFormat('#,##0.00', 'en').format(v);
  String _cur(double v) => money(v, r.currency, lang);
  String _dt(DateTime? d) => d == null ? '—' : DateFormat('dd-MM-yyyy · hh:mm a', lang).format(d);

  @override
  Widget build(BuildContext context) {
    final sc = statusColors(r.status);
    final logo = AppConfig.mediaUrl(r.tenantLogoUrl);
    // A receipt is only ever fetched once it's issued (payment fully completed), so a number is always
    // present; never show "Provisional". Fall back to the order number defensively if it were ever empty.
    final receiptNo = (r.number == null || r.number!.isEmpty) ? '#${r.orderNumber}' : r.number!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                boxShadow: AppShadows.soft,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // ── Business header ──
                if (logo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Center(child: Image.network(logo, height: 46, errorBuilder: (_, _, _) => const SizedBox.shrink())),
                  ),
                Center(child: Text(r.tenantName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: 0.5, color: AppColors.ink))),
                if ((r.branchName ?? '').isNotEmpty) _centerMuted(r.branchName!),
                if ((r.branchAddress ?? '').isNotEmpty) _centerMuted(r.branchAddress!),
                if ((r.branchPhone ?? '').isNotEmpty) _centerMuted('${context.t('TEL')}: ${r.branchPhone}'),
                if ((r.branchEmail ?? '').isNotEmpty) _centerMuted('${context.t('EMAIL')}: ${r.branchEmail}'),

                const _Dashed(),
                Center(
                  child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(context.t('Sales Receipt'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.5, color: AppColors.ink)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: sc.bg, borderRadius: BorderRadius.circular(AppRadius.chip)),
                      child: Text(context.t(r.status.label), style: TextStyle(color: sc.fg, fontWeight: FontWeight.w800, fontSize: 11)),
                    ),
                  ]),
                ),
                const _Dashed(),

                // ── Info block ──
                if ((r.customerName ?? '').isNotEmpty) _kv(context.t('Client'), r.customerName!),
                if ((r.customerPhone ?? '').isNotEmpty) _kv(context.t('Phone'), r.customerPhone!),
                if ((r.customerAddress ?? '').isNotEmpty) _kv(context.t('Address'), r.customerAddress!),
                _kv(context.t('Order No.'), '#${r.orderNumber}'),
                _kv(context.t('Receipt No.'), receiptNo),
                _kv(context.t('Date'), _dt(r.orderDate)),
                if (r.pickupAt != null) _kv(context.t('Pickup'), _dt(r.pickupAt)),
                if (r.deliveryAt != null) _kv(context.t('Delivery'), _dt(r.deliveryAt)),
                if ((r.taxNumber ?? '').isNotEmpty) _kv(context.t('Tax No.'), r.taxNumber!),

                const _Dashed(),
                Row(children: [
                  Expanded(child: Text(context.t('ITEM'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  Text(context.t('AMOUNT'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ]),
                const _Dashed(thin: true),
                if (r.lines.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(context.t('No services on this order.'), style: TextStyle(color: AppColors.muted))),
                for (final l in r.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l.serviceName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${l.quantity} × ${_num(l.unitPrice)}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Text(_num(l.lineTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ),

                const _Dashed(),
                _total(context.t('SUBTOTAL'), _num(r.subtotal), strong: true),
                if (r.discountAmount > 0) _total(context.t('Discount'), '-${_num(r.discountAmount)}'),
                if (r.expressSurcharge > 0) _total(context.t('Express surcharge'), _num(r.expressSurcharge)),
                if (r.deliveryFee > 0) _total(context.t('Delivery fee'), _num(r.deliveryFee)),
                _total('${context.t('VAT')} (${r.taxRate.toStringAsFixed(r.taxRate == r.taxRate.roundToDouble() ? 0 : 2)}%)', _num(r.taxAmount)),
                const _Dashed(thin: true),
                Row(children: [
                  Expanded(child: Text(context.t('TOTAL'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                  Text(_cur(r.total), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.primary)),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${context.t('Amount in Words')}: ${r.amountInWords}',
                      style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.muted, fontSize: 12)),
                ),

                const _Dashed(),
                _kv(context.t('Payment'), context.t(r.paymentStatus.label)),
                if (r.paymentMethod != null) _kv(context.t('Method'), context.t(r.paymentMethod!.label)),
                _kv(context.t('Amount Paid'), _cur(r.amountPaid)),
                _kv(context.t('Balance'), _cur(r.balanceDue)),
                if ((r.cashierName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _kv(context.t('Cashier'), r.cashierName!),
                ],
                if ((r.notes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('${context.t('Note')}: ${r.notes}', style: TextStyle(color: AppColors.inkSoft)),
                ],

                const _Dashed(),
                Center(child: Text(context.t('THANK YOU FOR TRUSTING US!'), style: const TextStyle(fontWeight: FontWeight.w800))),
                Center(child: Text(r.tenantName, style: TextStyle(color: AppColors.muted, fontSize: 12))),
              ]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _centerMuted(String text) =>
      Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12.5)));

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label: ', style: TextStyle(color: AppColors.muted)),
          Expanded(child: Text(value, textAlign: TextAlign.right)),
        ]),
      );

  Widget _total(String label, String value, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: strong ? AppColors.ink : AppColors.muted, fontWeight: strong ? FontWeight.w700 : FontWeight.w400))),
          Text(value, style: TextStyle(fontWeight: strong ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );
}

/// A thin dashed horizontal rule (thermal-receipt style).
class _Dashed extends StatelessWidget {
  const _Dashed({this.thin = false});
  final bool thin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: thin ? 5 : 9),
      child: LayoutBuilder(builder: (context, c) {
        const dashW = 4.0, gap = 3.0;
        final count = (c.maxWidth / (dashW + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(count, (_) => Container(width: dashW, height: 1, color: AppColors.line)),
        );
      }),
    );
  }
}
