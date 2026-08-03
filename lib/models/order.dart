import 'enums.dart';

/// A row in "My Orders" / "Payments" (OrderListDto).
class OrderListItem {
  OrderListItem({
    required this.id,
    required this.orderNumber,
    this.customerName,
    required this.status,
    required this.type,
    required this.speed,
    required this.paymentStatus,
    required this.itemCount,
    required this.total,
    required this.amountPaid,
    required this.balanceDue,
    required this.currency,
    this.pickupAt,
    this.readyByAt,
    this.deliveryAt,
    required this.createdAt,
  });

  final String id;
  final String orderNumber;
  final String? customerName;
  final OrderStatus status;
  final OrderType type;
  final ServiceSpeed speed;
  final PaymentStatus paymentStatus;
  final int itemCount;
  final double total;
  final double amountPaid;
  final double balanceDue;
  final String currency;
  final DateTime? pickupAt;
  final DateTime? readyByAt;
  final DateTime? deliveryAt;
  final DateTime createdAt;

  static double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  factory OrderListItem.fromJson(Map<String, dynamic> j) => OrderListItem(
        id: j['id'] as String,
        orderNumber: j['orderNumber'] as String? ?? '',
        customerName: j['customerName'] as String?,
        status: OrderStatus.from((j['status'] as num?)?.toInt()),
        type: OrderType.from((j['type'] as num?)?.toInt()),
        speed: ServiceSpeed.from((j['speed'] as num?)?.toInt()),
        paymentStatus: PaymentStatus.from((j['paymentStatus'] as num?)?.toInt()),
        itemCount: (j['itemCount'] as num?)?.toInt() ?? 0,
        total: _d(j['total']),
        amountPaid: _d(j['amountPaid']),
        balanceDue: _d(j['balanceDue']),
        currency: j['currency'] as String? ?? 'SAR',
        pickupAt: _dt(j['pickupAt']),
        readyByAt: _dt(j['readyByAt']),
        deliveryAt: _dt(j['deliveryAt']),
        createdAt: _dt(j['createdAt']) ?? DateTime.now(),
      );
}

/// Paged result + status counts + payment aggregates (CustomerOrderListResult).
class CustomerOrderPage {
  CustomerOrderPage({
    required this.items,
    required this.page,
    required this.totalFiltered,
    required this.allCount,
    required this.statusCounts,
    required this.totalBilled,
    required this.totalPaid,
    required this.outstanding,
    required this.currency,
  });

  final List<OrderListItem> items;
  final int page;
  final int totalFiltered;
  final int allCount;
  final Map<OrderStatus, int> statusCounts;
  final double totalBilled;
  final double totalPaid;
  final double outstanding;
  final String currency;

  factory CustomerOrderPage.fromJson(Map<String, dynamic> j) => CustomerOrderPage(
        items: (j['items'] as List? ?? const [])
            .map((e) => OrderListItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        page: (j['page'] as num?)?.toInt() ?? 1,
        totalFiltered: (j['totalFiltered'] as num?)?.toInt() ?? 0,
        allCount: (j['allCount'] as num?)?.toInt() ?? 0,
        statusCounts: () {
          final raw = (j['statusCounts'] as Map?) ?? const {};
          final out = <OrderStatus, int>{};
          raw.forEach((k, v) {
            final st = OrderStatus.fromKey(k);
            if (st != null) out[st] = (out[st] ?? 0) + (v as num).toInt();
          });
          return out;
        }(),
        totalBilled: OrderListItem._d(j['totalBilled']),
        totalPaid: OrderListItem._d(j['totalPaid']),
        outstanding: OrderListItem._d(j['outstanding']),
        currency: j['currency'] as String? ?? 'SAR',
      );
}

/// Public tracking payload (OrderTrackingDto).
class OrderTracking {
  OrderTracking({
    required this.orderNumber,
    required this.status,
    required this.total,
    required this.currency,
    this.readyByAt,
    this.deliveryAt,
    required this.timeline,
  });

  final String orderNumber;
  final OrderStatus status;
  final double total;
  final String currency;
  final DateTime? readyByAt;
  final DateTime? deliveryAt;
  final List<OrderEvent> timeline;

  factory OrderTracking.fromJson(Map<String, dynamic> j) => OrderTracking(
        orderNumber: j['orderNumber'] as String? ?? '',
        status: OrderStatus.from((j['status'] as num?)?.toInt()),
        total: OrderListItem._d(j['total']),
        currency: j['currency'] as String? ?? 'SAR',
        readyByAt: OrderListItem._dt(j['readyByAt']),
        deliveryAt: OrderListItem._dt(j['deliveryAt']),
        timeline: (j['timeline'] as List? ?? const [])
            .map((e) => OrderEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class OrderEvent {
  OrderEvent({required this.toStatus, this.fromStatus, this.source, this.actorName, this.note, required this.occurredAt});
  final OrderStatus toStatus;
  final OrderStatus? fromStatus;
  final EventSource? source;
  final String? actorName;
  final String? note;
  final DateTime occurredAt;

  factory OrderEvent.fromJson(Map<String, dynamic> j) => OrderEvent(
        toStatus: OrderStatus.from((j['toStatus'] as num?)?.toInt()),
        fromStatus: j['fromStatus'] == null ? null : OrderStatus.from((j['fromStatus'] as num?)?.toInt()),
        source: j['source'] == null ? null : EventSource.from((j['source'] as num?)?.toInt()),
        actorName: j['actorName'] as String?,
        note: j['note'] as String?,
        occurredAt: OrderListItem._dt(j['occurredAt']) ?? DateTime.now(),
      );
}
