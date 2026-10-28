/// Order lifecycle (matches SmartWash OrderStatus int values).
enum OrderStatus {
  draft(0, 'Draft'),
  placed(1, 'Placed'),
  inProcess(2, 'In process'),
  ready(3, 'Ready'),
  outForDelivery(4, 'Out for delivery'),
  delivered(5, 'Delivered'),
  cancelled(6, 'Cancelled'),
  pickupScheduled(7, 'Pickup scheduled'),
  pickedUp(8, 'Picked up'),
  atFacility(9, 'At facility'),
  onHold(10, 'On hold');

  const OrderStatus(this.value, this.label);
  final int value;
  final String label;

  static OrderStatus from(int? v) =>
      OrderStatus.values.firstWhere((e) => e.value == v, orElse: () => OrderStatus.placed);

  /// Resolve a status from an API map-key that may be an integer ("5") OR the
  /// server enum name ("Delivered", "InProcess", "PickupScheduled"). The API
  /// serialises `statusCounts` with PascalCase enum-name keys, so int-only
  /// parsing silently loses them.
  static OrderStatus? fromKey(Object? key) {
    if (key == null) return null;
    final s = key.toString();
    final asInt = int.tryParse(s);
    if (asInt != null) return from(asInt);
    final n = s.toLowerCase();
    for (final e in values) {
      if (e.name.toLowerCase() == n) return e;
    }
    return null;
  }
}

enum OrderType {
  walkIn(0, 'Walk-in'),
  pickupAndDelivery(1, 'Pickup & Delivery');

  const OrderType(this.value, this.label);
  final int value;
  final String label;
  static OrderType from(int? v) =>
      OrderType.values.firstWhere((e) => e.value == v, orElse: () => OrderType.pickupAndDelivery);
}

enum PaymentStatus {
  unpaid(0, 'Unpaid'),
  partial(1, 'Partly paid'),
  paid(2, 'Paid');

  const PaymentStatus(this.value, this.label);
  final int value;
  final String label;
  static PaymentStatus from(int? v) =>
      PaymentStatus.values.firstWhere((e) => e.value == v, orElse: () => PaymentStatus.unpaid);
}

/// Invoice lifecycle (matches SmartWash OrderInvoiceStatus int values).
enum OrderInvoiceStatus {
  draft(0, 'Draft'),
  pending(1, 'Pending'),
  pendingPayment(2, 'Pending payment'),
  paid(3, 'Paid'),
  voided(4, 'Void');

  const OrderInvoiceStatus(this.value, this.label);
  final int value;
  final String label;
  static OrderInvoiceStatus from(int? v) =>
      OrderInvoiceStatus.values.firstWhere((e) => e.value == v, orElse: () => OrderInvoiceStatus.draft);
}

/// Receipt lifecycle (matches SmartWash OrderReceiptStatus int values).
enum OrderReceiptStatus {
  pending(0, 'Pending'),
  issued(1, 'Issued'),
  paid(2, 'Paid'),
  voided(3, 'Void');

  const OrderReceiptStatus(this.value, this.label);
  final int value;
  final String label;
  static OrderReceiptStatus from(int? v) =>
      OrderReceiptStatus.values.firstWhere((e) => e.value == v, orElse: () => OrderReceiptStatus.pending);
}

enum PaymentMethod {
  cash(0, 'Cash'),
  card(1, 'Card'),
  transfer(2, 'Bank transfer'),
  online(3, 'Online'),
  wallet(4, 'Wallet');

  const PaymentMethod(this.value, this.label);
  final int value;
  final String label;
  static PaymentMethod? from(int? v) {
    if (v == null) return null;
    for (final e in values) {
      if (e.value == v) return e;
    }
    return null;
  }
}

/// Turnaround speed (ServiceSpeed). Express carries a surcharge.
enum ServiceSpeed {
  standard(0, 'Standard'),
  express(1, 'Express');

  const ServiceSpeed(this.value, this.label);
  final int value;
  final String label;
  static ServiceSpeed from(int? v) =>
      ServiceSpeed.values.firstWhere((e) => e.value == v, orElse: () => ServiceSpeed.standard);
}

/// How a service is priced (ServiceUnit) — drives the "/ piece", "/ kg" suffix.
enum ServiceUnit {
  perPiece(0, 'piece'),
  perKg(1, 'kg'),
  perOrder(2, 'order'),
  perPair(3, 'pair'),
  perSquareMeter(4, 'm²');

  const ServiceUnit(this.value, this.label);
  final int value;
  final String label;
  static ServiceUnit from(int? v) =>
      ServiceUnit.values.firstWhere((e) => e.value == v, orElse: () => ServiceUnit.perPiece);
}

/// Who/what triggered a timeline event (matches SmartWash EventSource).
enum EventSource {
  system(0, 'System'),
  staff(1, 'Staff'),
  driver(2, 'Driver'),
  customer(3, 'Customer');

  const EventSource(this.value, this.label);
  final int value;
  final String label;
  static EventSource from(int? v) =>
      EventSource.values.firstWhere((e) => e.value == v, orElse: () => EventSource.system);
}

// ─────────────────────────────────────────────────────────────────────────────
// Driver / delivery-task enums (mirror SmartWash.Domain.Deliveries + DriverUi)
// ─────────────────────────────────────────────────────────────────────────────

/// Delivery task lifecycle (int-persisted, matches DeliveryStatus).
/// Labels are the DRIVER-facing labels from the web `DriverUi`.
enum DeliveryStatus {
  pending(0, 'Unassigned'),
  assigned(1, 'Pending acceptance'),
  inTransit(2, 'In transit'),
  completed(3, 'Completed'),
  failed(4, 'Failed'),
  cancelled(5, 'Cancelled'),
  accepted(6, 'Accepted'),
  rejected(7, 'Rejected'),
  arrived(8, 'Arrived'),
  // Pickup leg only: the driver collected the laundry, then handed it over at the branch;
  // the branch confirming receipt completes the leg.
  collected(9, 'Collected'),
  droppedOff(10, 'Handed over at branch');

  const DeliveryStatus(this.value, this.label);
  final int value;
  final String label;
  static DeliveryStatus from(int? v) =>
      DeliveryStatus.values.firstWhere((e) => e.value == v, orElse: () => DeliveryStatus.pending);
}

/// A delivery task is either a pickup (collect from customer) or a delivery (to customer).
enum DeliveryType {
  pickup(0, 'Pickup'),
  delivery(1, 'Delivery');

  const DeliveryType(this.value, this.label);
  final int value;
  final String label;
  static DeliveryType from(int? v) =>
      DeliveryType.values.firstWhere((e) => e.value == v, orElse: () => DeliveryType.pickup);
}

/// How a pickup-and-delivery order reaches the branch (matches PickupMethod).
enum PickupMethod {
  driverPickup(0, 'Driver pickup'),
  customerDropOff(1, 'Customer drop-off');

  const PickupMethod(this.value, this.label);
  final int value;
  final String label;
  static PickupMethod from(int? v) =>
      PickupMethod.values.firstWhere((e) => e.value == v, orElse: () => PickupMethod.driverPickup);
}

/// Driver availability (DriverStatus).
enum DriverStatus {
  available(0, 'Available'),
  onTrip(1, 'On trip'),
  offline(2, 'Offline');

  const DriverStatus(this.value, this.label);
  final int value;
  final String label;
  static DriverStatus from(int? v) =>
      DriverStatus.values.firstWhere((e) => e.value == v, orElse: () => DriverStatus.available);
}

/// Task list status-group tabs (matches TaskStatusGroup). `value` is the API `group` param.
enum TaskGroup {
  all(0, 'All'),
  todo(1, 'To-do'),
  active(2, 'In progress'),
  completed(3, 'Completed'),
  issues(4, 'Issues');

  const TaskGroup(this.value, this.label);
  final int value;
  final String label;
}

/// Task priority filter (matches TaskUrgency: 0 Overdue · 1 Today · 2 Upcoming).
/// `.index` == the API `priority` int.
enum TaskUrgency { overdue, today, upcoming }

/// Which point in the driver journey a status maps to (New→Accepted→InTransit→Arrived→Done).
/// -1 = off-track (Failed/Rejected/Cancelled).
extension DeliveryStatusX on DeliveryStatus {
  int get journeyIndex {
    switch (this) {
      case DeliveryStatus.pending:
      case DeliveryStatus.assigned:
        return 0;
      case DeliveryStatus.accepted:
        return 1;
      case DeliveryStatus.inTransit:
        return 2;
      case DeliveryStatus.arrived:
        return 3;
      case DeliveryStatus.completed:
        return 4;
      default:
        return -1;
    }
  }

  /// Journey index for a specific leg. A pickup continues past "Arrived":
  /// New → Accepted → In transit → Arrived → Collected → At branch → Received.
  int journeyIndexFor(DeliveryType type) {
    if (type != DeliveryType.pickup) return journeyIndex;
    switch (this) {
      case DeliveryStatus.collected:
        return 4;
      case DeliveryStatus.droppedOff:
        return 5;
      case DeliveryStatus.completed:
        return 6;
      default:
        return journeyIndex;
    }
  }

  bool get isActionable =>
      this == DeliveryStatus.assigned ||
      this == DeliveryStatus.accepted ||
      this == DeliveryStatus.inTransit ||
      this == DeliveryStatus.arrived ||
      this == DeliveryStatus.collected;

  bool get isClosed =>
      this == DeliveryStatus.failed || this == DeliveryStatus.rejected || this == DeliveryStatus.cancelled;
}

/// A coarse phase for coloring/progress in the UI.
enum OrderPhase { pending, active, ready, done, cancelled }

extension OrderStatusX on OrderStatus {
  OrderPhase get phase {
    switch (this) {
      case OrderStatus.delivered:
        return OrderPhase.done;
      case OrderStatus.cancelled:
        return OrderPhase.cancelled;
      case OrderStatus.ready:
        return OrderPhase.ready;
      case OrderStatus.placed:
      case OrderStatus.draft:
      case OrderStatus.pickupScheduled:
        return OrderPhase.pending;
      default:
        return OrderPhase.active;
    }
  }
}
