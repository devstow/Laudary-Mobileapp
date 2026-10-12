import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/enums.dart';
import '../../models/order_invoice.dart';
import '../../services/api_exception.dart';
import '../../services/order_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// A professional native preview of an order's invoice (parity with the web invoice document).
class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key, required this.orderId, this.orderNumber});
  final String orderId;
  final String? orderNumber;

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  late Future<OrderInvoice> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = context.read<OrderService>().invoice(widget.orderId);

  ({Color bg, Color fg}) _statusColors(OrderInvoiceStatus s) {
    switch (s) {
      case OrderInvoiceStatus.paid:
        return (bg: const Color(0xFF16A34A), fg: Colors.white);
      case OrderInvoiceStatus.pending:
        return (bg: const Color(0xFF2563EB), fg: Colors.white);
      case OrderInvoiceStatus.pendingPayment:
        return (bg: AppColors.gold, fg: AppColors.onGold);
      case OrderInvoiceStatus.voided:
        return (bg: AppColors.danger, fg: Colors.white);
      case OrderInvoiceStatus.draft:
        return (bg: AppColors.line, fg: AppColors.muted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().locale.code;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Invoice'))),
      body: FutureBuilder<OrderInvoice>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.all(20), child: SkeletonList(count: 3));
          }
          if (snap.hasError) return ErrorView(ApiException.from(snap.error!).message, onRetry: () => setState(_load));
          final inv = snap.data!;
          final cur = inv.currency;
          final sc = _statusColors(inv.status);
          final number = (inv.number == null || inv.number!.isEmpty) ? context.t('Draft — not yet issued') : '#${inv.number}';

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              BrandHero(
                padding: const EdgeInsets.all(20),
                borderRadius: BorderRadius.circular(AppRadius.card + 2),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(inv.tenantName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  if (inv.branchName != null && inv.branchName!.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text(inv.branchName!, style: const TextStyle(color: Colors.white70, fontSize: 13))),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(number, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('${context.t('Order:')} ${inv.orderNumber}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: sc.bg, borderRadius: BorderRadius.circular(AppRadius.chip)),
                      child: Text(context.t(inv.status.label), style: TextStyle(color: sc.fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),

              SoftCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('Invoice To:'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  if (inv.customerName != null) Text(inv.customerName!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (inv.customerPhone != null && inv.customerPhone!.isNotEmpty)
                    Text(inv.customerPhone!, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  if (inv.customerEmail != null && inv.customerEmail!.isNotEmpty)
                    Text(inv.customerEmail!, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  if (inv.customerAddress != null && inv.customerAddress!.isNotEmpty)
                    Text(inv.customerAddress!, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 10),
                  if (inv.issuedAt != null)
                    InfoRow(icon: Icons.event_rounded, label: context.t('Date Issued:'), value: DateFormat('d MMM yyyy', lang).format(inv.issuedAt!)),
                  if (inv.paidAt != null)
                    InfoRow(icon: Icons.verified_rounded, label: context.t('Date Paid:'), value: DateFormat('d MMM yyyy', lang).format(inv.paidAt!)),
                ]),
              ),
              const SizedBox(height: 14),

              SoftCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('Items'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink)),
                  const SizedBox(height: 10),
                  if (inv.lines.isEmpty)
                    Text(context.t('No services on this order.'), style: TextStyle(color: AppColors.muted)),
                  for (final l in inv.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(7)),
                          child: Text('${l.quantity}×', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(l.serviceName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                        const SizedBox(width: 8),
                        Text(money(l.lineTotal, cur, lang), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 14),

              SoftCard(
                child: Column(children: [
                  MoneyRow(context.t('Subtotal'), money(inv.subtotal, cur, lang)),
                  if (inv.discountAmount > 0) MoneyRow(context.t('Discount'), '- ${money(inv.discountAmount, cur, lang)}'),
                  if (inv.expressSurcharge > 0) MoneyRow(context.t('Express surcharge'), money(inv.expressSurcharge, cur, lang)),
                  if (inv.deliveryFee > 0) MoneyRow(context.t('Delivery fee'), money(inv.deliveryFee, cur, lang)),
                  MoneyRow('${context.t('VAT')} (${inv.taxRate.toStringAsFixed(0)}%)', money(inv.taxAmount, cur, lang)),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1)),
                  MoneyRow(context.t('Total'), money(inv.total, cur, lang), strong: true, accent: true),
                  if (inv.amountPaid > 0) MoneyRow(context.t('Amount paid'), money(inv.amountPaid, cur, lang)),
                  if (inv.balanceDue > 0) MoneyRow(context.t('Balance due'), money(inv.balanceDue, cur, lang)),
                ]),
              ),

              if (inv.notes != null && inv.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t('Notes'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink)),
                    const SizedBox(height: 8),
                    Text(inv.notes!, style: TextStyle(color: AppColors.inkSoft, height: 1.4)),
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
