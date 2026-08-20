import 'enums.dart';

class OrderReceiptLine {
  OrderReceiptLine({required this.serviceName, required this.unitPrice, required this.quantity, required this.lineTotal, this.notes});
  final String serviceName;
  final double unitPrice;
  final int quantity;
  final double lineTotal;
  final String? notes;

  factory OrderReceiptLine.fromJson(Map<String, dynamic> j) => OrderReceiptLine(
        serviceName: j['serviceName'] as String? ?? '',
        unitPrice: (j['unitPrice'] as num?)?.toDouble() ?? 0,
        quantity: (j['quantity'] as num?)?.toInt() ?? 0,
        lineTotal: (j['lineTotal'] as num?)?.toDouble() ?? 0,
        notes: j['notes'] as String?,
      );
}

/// Full order payment receipt (OrderReceiptDto).
class OrderReceipt {
  OrderReceipt({
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
    required this.orderDate,
    this.pickupAt,
    this.deliveryAt,
    this.notes,
    required this.lines,
    required this.amountInWords,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.customerAddress,
    required this.tenantName,
    this.tenantLogoUrl,
    this.taxNumber,
    this.branchName,
    this.branchAddress,
    this.branchPhone,
    this.branchEmail,
    this.cashierName,
  });

  final String id;
  final String orderId;
  final String orderNumber;
  final String? number;
  final OrderReceiptStatus status;
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
  final DateTime orderDate;
  final DateTime? pickupAt;
  final DateTime? deliveryAt;
  final String? notes;
  final List<OrderReceiptLine> lines;
  final String amountInWords;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String? customerAddress;
  final String tenantName;
  final String? tenantLogoUrl;
  final String? taxNumber;
  final String? branchName;
  final String? branchAddress;
  final String? branchPhone;
  final String? branchEmail;
  final String? cashierName;

  static double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  factory OrderReceipt.fromJson(Map<String, dynamic> j) => OrderReceipt(
        id: j['id'] as String,
        orderId: j['orderId'] as String,
        orderNumber: j['orderNumber'] as String? ?? '',
        number: j['number'] as String?,
        status: OrderReceiptStatus.from((j['status'] as num?)?.toInt()),
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
        orderDate: _dt(j['orderDate']) ?? DateTime.now(),
        pickupAt: _dt(j['pickupAt']),
        deliveryAt: _dt(j['deliveryAt']),
        notes: j['notes'] as String?,
        lines: (j['lines'] as List? ?? const [])
            .map((e) => OrderReceiptLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        amountInWords: j['amountInWords'] as String? ?? '',
        customerName: j['customerName'] as String?,
        customerPhone: j['customerPhone'] as String?,
        customerEmail: j['customerEmail'] as String?,
        customerAddress: j['customerAddress'] as String?,
        tenantName: j['tenantName'] as String? ?? '',
        tenantLogoUrl: j['tenantLogoUrl'] as String?,
        taxNumber: j['taxNumber'] as String?,
        branchName: j['branchName'] as String?,
        branchAddress: j['branchAddress'] as String?,
        branchPhone: j['branchPhone'] as String?,
        branchEmail: j['branchEmail'] as String?,
        cashierName: j['cashierName'] as String?,
      );
}
