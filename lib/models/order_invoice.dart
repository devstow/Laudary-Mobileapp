import 'enums.dart';

class OrderInvoiceLine {
  OrderInvoiceLine({required this.serviceName, required this.unitPrice, required this.quantity, required this.lineTotal, this.notes});
  final String serviceName;
  final double unitPrice;
  final int quantity;
  final double lineTotal;
  final String? notes;

  factory OrderInvoiceLine.fromJson(Map<String, dynamic> j) => OrderInvoiceLine(
        serviceName: j['serviceName'] as String? ?? '',
        unitPrice: (j['unitPrice'] as num?)?.toDouble() ?? 0,
        quantity: (j['quantity'] as num?)?.toInt() ?? 0,
        lineTotal: (j['lineTotal'] as num?)?.toDouble() ?? 0,
        notes: j['notes'] as String?,
      );
}

/// Full order invoice (OrderInvoiceDto).
class OrderInvoice {
  OrderInvoice({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    this.number,
    required this.status,
    required this.currency,
    required this.subtotal,
    required this.discountAmount,
    required this.expressSurcharge,
    required this.deliveryFee,
    required this.taxRate,
    required this.taxAmount,
    required this.total,
    required this.paymentStatus,
    this.paymentMethod,
    required this.amountPaid,
    required this.balanceDue,
    this.issuedAt,
    this.paidAt,
    this.notes,
    required this.lines,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.customerAddress,
    required this.tenantName,
    this.branchName,
  });

  final String id;
  final String orderId;
  final String orderNumber;
  final String? number;
  final OrderInvoiceStatus status;
  final String currency;
  final double subtotal;
  final double discountAmount;
  final double expressSurcharge;
  final double deliveryFee;
  final double taxRate;
  final double taxAmount;
  final double total;
  final PaymentStatus paymentStatus;
  final PaymentMethod? paymentMethod;
  final double amountPaid;
  final double balanceDue;
  final DateTime? issuedAt;
  final DateTime? paidAt;
  final String? notes;
  final List<OrderInvoiceLine> lines;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String? customerAddress;
  final String tenantName;
  final String? branchName;

  static double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  factory OrderInvoice.fromJson(Map<String, dynamic> j) => OrderInvoice(
        id: j['id'] as String,
        orderId: j['orderId'] as String,
        orderNumber: j['orderNumber'] as String? ?? '',
        number: j['number'] as String?,
        status: OrderInvoiceStatus.from((j['status'] as num?)?.toInt()),
        currency: j['currency'] as String? ?? 'SAR',
        subtotal: _d(j['subtotal']),
        discountAmount: _d(j['discountAmount']),
        expressSurcharge: _d(j['expressSurcharge']),
        deliveryFee: _d(j['deliveryFee']),
        taxRate: _d(j['taxRate']),
        taxAmount: _d(j['taxAmount']),
        total: _d(j['total']),
        paymentStatus: PaymentStatus.from((j['paymentStatus'] as num?)?.toInt()),
        paymentMethod: PaymentMethod.from((j['paymentMethod'] as num?)?.toInt()),
        amountPaid: _d(j['amountPaid']),
        balanceDue: _d(j['balanceDue']),
        issuedAt: _dt(j['issuedAt']),
        paidAt: _dt(j['paidAt']),
        notes: j['notes'] as String?,
        lines: (j['lines'] as List? ?? const [])
            .map((e) => OrderInvoiceLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        customerName: j['customerName'] as String?,
        customerPhone: j['customerPhone'] as String?,
        customerEmail: j['customerEmail'] as String?,
        customerAddress: j['customerAddress'] as String?,
        tenantName: j['tenantName'] as String? ?? '',
        branchName: j['branchName'] as String?,
      );
}
