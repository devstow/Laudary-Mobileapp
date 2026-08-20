import 'enums.dart';

class OrderItem {
  OrderItem({this.serviceId, required this.serviceName, required this.unitPrice, required this.quantity, required this.lineTotal, this.notes, this.imageUrl});
  final String? serviceId;
  final String serviceName;
  final double unitPrice;
  final int quantity;
  final double lineTotal;
  final String? notes;

  /// Relative/absolute service image URL; resolve with AppConfig.mediaUrl before loading.
  final String? imageUrl;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        serviceId: j['serviceId'] as String?,
        serviceName: j['serviceName'] as String? ?? '',
        unitPrice: (j['unitPrice'] as num?)?.toDouble() ?? 0,
        quantity: (j['quantity'] as num?)?.toInt() ?? 0,
        lineTotal: (j['lineTotal'] as num?)?.toDouble() ?? 0,
        notes: j['notes'] as String?,
        imageUrl: j['imageUrl'] as String?,
      );
}

/// Full order (OrderDetailDto).
class OrderDetail {
  OrderDetail({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.type,
    required this.speed,
    required this.currency,
    required this.subtotal,
    required this.discountAmount,
    required this.expressSurcharge,
    required this.deliveryFee,
    required this.taxRate,
    required this.taxAmount,
    required this.total,
    required this.amountPaid,
    required this.balanceDue,
    required this.paymentStatus,
    this.paymentMethod,
    this.contactPhone,
    this.pickupAddress,
    this.deliveryAddress,
    this.pickupLat,
    this.pickupLng,
    this.deliveryLat,
    this.deliveryLng,
    this.pickupAt,
    this.readyByAt,
    this.deliveryAt,
    this.notes,
    required this.items,
    this.canCancel = false,
    this.canDelete = false,
    this.canEdit = false,
    required this.invoiceStatus,
  });

  final String id;
  final String orderNumber;
  final OrderStatus status;
  final OrderType type;
  final ServiceSpeed speed;
  final String currency;
  final double subtotal;
  final double discountAmount;
  final double expressSurcharge;
  final double deliveryFee;
  final double taxRate;
  final double taxAmount;
  final double total;
  final double amountPaid;
  final double balanceDue;
  final PaymentStatus paymentStatus;
  final PaymentMethod? paymentMethod;
  final String? contactPhone;
  final String? pickupAddress;
  final String? deliveryAddress;
  final double? pickupLat;
  final double? pickupLng;
  final double? deliveryLat;
  final double? deliveryLng;
  final DateTime? pickupAt;
  final DateTime? readyByAt;
  final DateTime? deliveryAt;
  final String? notes;
  final List<OrderItem> items;

  /// Customer may cancel/delete/edit only before the order is collected (server is authoritative).
  final bool canCancel;
  final bool canDelete;
  final bool canEdit;

  /// Invoice status derived from the order lifecycle (for the badge).
  final OrderInvoiceStatus invoiceStatus;

  bool get isExpress => speed == ServiceSpeed.express;
  bool get hasPickupPin => pickupLat != null && pickupLng != null;
  bool get hasDeliveryPin => deliveryLat != null && deliveryLng != null;

  /// Customer may reschedule the pickup only before it's collected.
  bool get canReschedule =>
      type == OrderType.pickupAndDelivery &&
      const {OrderStatus.draft, OrderStatus.placed, OrderStatus.pickupScheduled}.contains(status);

  /// Customer may pick a delivery slot once the order is ready.
  bool get canChooseDelivery => type == OrderType.pickupAndDelivery && status == OrderStatus.ready;

  static double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
  static double? _dn(dynamic v) => v == null ? null : (v as num).toDouble();
  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  factory OrderDetail.fromJson(Map<String, dynamic> j) => OrderDetail(
        id: j['id'] as String,
        orderNumber: j['orderNumber'] as String? ?? '',
        status: OrderStatus.from((j['status'] as num?)?.toInt()),
        type: OrderType.from((j['type'] as num?)?.toInt()),
        speed: ServiceSpeed.from((j['speed'] as num?)?.toInt()),
        currency: j['currency'] as String? ?? 'SAR',
        subtotal: _d(j['subtotal']),
        discountAmount: _d(j['discountAmount']),
        expressSurcharge: _d(j['expressSurcharge']),
        deliveryFee: _d(j['deliveryFee']),
        taxRate: _d(j['taxRate']),
        taxAmount: _d(j['taxAmount']),
        total: _d(j['total']),
        amountPaid: _d(j['amountPaid']),
        balanceDue: _d(j['balanceDue']),
        paymentStatus: PaymentStatus.from((j['paymentStatus'] as num?)?.toInt()),
        paymentMethod: PaymentMethod.from((j['paymentMethod'] as num?)?.toInt()),
        contactPhone: j['contactPhone'] as String?,
        pickupAddress: j['pickupAddress'] as String?,
        deliveryAddress: j['deliveryAddress'] as String?,
        pickupLat: _dn(j['pickupLatitude']),
        pickupLng: _dn(j['pickupLongitude']),
        deliveryLat: _dn(j['deliveryLatitude']),
        deliveryLng: _dn(j['deliveryLongitude']),
        pickupAt: _dt(j['pickupAt']),
        readyByAt: _dt(j['readyByAt']),
        deliveryAt: _dt(j['deliveryAt']),
        notes: j['notes'] as String?,
        items: (j['items'] as List? ?? const [])
            .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        canCancel: j['canCancel'] as bool? ?? false,
        canDelete: j['canDelete'] as bool? ?? false,
        canEdit: j['canEdit'] as bool? ?? false,
        invoiceStatus: OrderInvoiceStatus.from((j['invoiceStatus'] as num?)?.toInt()),
      );
}
