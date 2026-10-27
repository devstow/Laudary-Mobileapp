import 'delivery.dart';
import 'enums.dart';

/// One laundry line on the order behind a task (what to collect / hand over).
class DriverTaskItem {
  DriverTaskItem({required this.serviceName, required this.quantity, this.notes});
  final String serviceName;
  final int quantity;
  final String? notes;

  factory DriverTaskItem.fromJson(Map<String, dynamic> j) => DriverTaskItem(
        serviceName: j['serviceName'] as String? ?? '',
        quantity: (j['quantity'] as num?)?.toInt() ?? 0,
        notes: j['notes'] as String?,
      );
}

/// Another leg of the same order (the pickup for a delivery task and vice-versa).
class DriverTaskLeg {
  DriverTaskLeg({required this.id, required this.type, required this.status, this.scheduledAt, this.completedAt, this.driverName, required this.isMine, required this.attemptNumber});
  final String id;
  final DeliveryType type;
  final DeliveryStatus status;
  final DateTime? scheduledAt;
  final DateTime? completedAt;
  final String? driverName;
  final bool isMine;
  final int attemptNumber;

  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  factory DriverTaskLeg.fromJson(Map<String, dynamic> j) => DriverTaskLeg(
        id: j['id'] as String,
        type: DeliveryType.from((j['type'] as num?)?.toInt()),
        status: DeliveryStatus.from((j['status'] as num?)?.toInt()),
        scheduledAt: _dt(j['scheduledAt']),
        completedAt: _dt(j['completedAt']),
        driverName: j['driverName'] as String?,
        isMine: j['isMine'] as bool? ?? false,
        attemptNumber: (j['attemptNumber'] as num?)?.toInt() ?? 1,
      );
}

/// One assignment attempt of a leg (the task's history).
class DriverTaskAttempt {
  DriverTaskAttempt({required this.attemptNumber, this.driverName, required this.status, required this.assignedAt, this.endedAt, this.reason});
  final int attemptNumber;
  final String? driverName;
  final DeliveryStatus status;
  final DateTime assignedAt;
  final DateTime? endedAt;
  final String? reason;

  factory DriverTaskAttempt.fromJson(Map<String, dynamic> j) => DriverTaskAttempt(
        attemptNumber: (j['attemptNumber'] as num?)?.toInt() ?? 1,
        driverName: j['driverName'] as String?,
        status: DeliveryStatus.from((j['status'] as num?)?.toInt()),
        assignedAt: DateTime.tryParse(j['assignedAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        endedAt: j['rejectedAt'] == null ? null : DateTime.tryParse(j['rejectedAt'] as String)?.toLocal(),
        reason: j['rejectionReason'] as String?,
      );
}

/// Full detail of one of the driver's own tasks (GET api/deliveries/mine/{id}): the task, the order it
/// fulfils (status, schedule, items, instructions, what to collect), the order's other legs and history.
class DriverTaskDetail {
  DriverTaskDetail({
    required this.task,
    required this.orderNumber,
    required this.orderStatus,
    required this.orderType,
    required this.speed,
    this.customerName,
    this.contactPhone,
    this.pickupAddress,
    this.deliveryAddress,
    this.pickupAt,
    this.readyByAt,
    this.deliveryAt,
    this.orderNotes,
    this.taskNotes,
    required this.items,
    required this.itemCount,
    required this.currency,
    required this.orderTotal,
    required this.amountPaid,
    required this.balanceDue,
    required this.paymentStatus,
    this.paymentMethod,
    required this.legs,
    required this.history,
    required this.orderPlacedAt,
    required this.collectOnDelivery,
  });

  final DeliveryTask task;
  final String orderNumber;
  final OrderStatus orderStatus;
  final OrderType orderType;
  final ServiceSpeed speed;
  final String? customerName;
  final String? contactPhone;
  final String? pickupAddress;
  final String? deliveryAddress;
  final DateTime? pickupAt;
  final DateTime? readyByAt;
  final DateTime? deliveryAt;
  final String? orderNotes;
  final String? taskNotes;
  final List<DriverTaskItem> items;
  final int itemCount;
  final String currency;
  final double orderTotal;
  final double amountPaid;
  final double balanceDue;
  final PaymentStatus paymentStatus;
  final PaymentMethod? paymentMethod;
  final List<DriverTaskLeg> legs;
  final List<DriverTaskAttempt> history;
  final DateTime orderPlacedAt;
  final bool collectOnDelivery;

  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  factory DriverTaskDetail.fromJson(Map<String, dynamic> j) => DriverTaskDetail(
        task: DeliveryTask.fromJson(j['task'] as Map<String, dynamic>),
        orderNumber: j['orderNumber'] as String? ?? '',
        orderStatus: OrderStatus.from((j['orderStatus'] as num?)?.toInt()),
        orderType: OrderType.from((j['orderType'] as num?)?.toInt()),
        speed: ServiceSpeed.from((j['speed'] as num?)?.toInt()),
        customerName: j['customerName'] as String?,
        contactPhone: j['contactPhone'] as String?,
        pickupAddress: j['pickupAddress'] as String?,
        deliveryAddress: j['deliveryAddress'] as String?,
        pickupAt: _dt(j['pickupAt']),
        readyByAt: _dt(j['readyByAt']),
        deliveryAt: _dt(j['deliveryAt']),
        orderNotes: j['orderNotes'] as String?,
        taskNotes: j['taskNotes'] as String?,
        items: (j['items'] as List? ?? const []).map((e) => DriverTaskItem.fromJson(e as Map<String, dynamic>)).toList(),
        itemCount: (j['itemCount'] as num?)?.toInt() ?? 0,
        currency: j['currency'] as String? ?? 'SAR',
        orderTotal: _d(j['orderTotal']),
        amountPaid: _d(j['amountPaid']),
        balanceDue: _d(j['balanceDue']),
        paymentStatus: PaymentStatus.from((j['paymentStatus'] as num?)?.toInt()),
        paymentMethod: j['paymentMethod'] == null ? null : PaymentMethod.from((j['paymentMethod'] as num?)?.toInt()),
        legs: (j['legs'] as List? ?? const []).map((e) => DriverTaskLeg.fromJson(e as Map<String, dynamic>)).toList(),
        history: (j['history'] as List? ?? const []).map((e) => DriverTaskAttempt.fromJson(e as Map<String, dynamic>)).toList(),
        orderPlacedAt: _dt(j['orderPlacedAt']) ?? DateTime.now(),
        collectOnDelivery: j['collectOnDelivery'] as bool? ?? false,
      );
}
