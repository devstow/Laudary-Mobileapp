import 'enums.dart';

/// A driver's delivery task (DeliveryListDto) — this is both the list card AND the
/// detail; it carries everything the driver needs (coords, phone, address, schedule,
/// proof, rejection/failure info).
class DeliveryTask {
  DeliveryTask({
    required this.id,
    required this.orderId,
    this.orderNumber,
    this.customerName,
    required this.type,
    required this.status,
    this.scheduledAt,
    this.completedAt,
    this.address,
    this.contactPhone,
    this.proofPhotoUrl,
    this.failureReason,
    this.rejectionReason,
    this.rejectedByName,
    required this.attemptNumber,
    required this.createdAt,
    this.lat,
    this.lng,
    this.awaitingCustomerSlot = false,
    this.collectedAt,
    this.droppedOffAt,
    this.receivedAt,
    this.branchName,
    this.branchLat,
    this.branchLng,
    this.pickupMethod = PickupMethod.driverPickup,
  });

  final String id;
  final String orderId;
  final String? orderNumber;
  final String? customerName;
  final DeliveryType type;
  final DeliveryStatus status;
  final DateTime? scheduledAt;
  final DateTime? completedAt;
  final String? address;
  final String? contactPhone;
  final String? proofPhotoUrl;
  final String? failureReason;
  final String? rejectionReason;
  final String? rejectedByName;
  final int attemptNumber;
  final DateTime createdAt;
  final double? lat;
  final double? lng;
  final bool awaitingCustomerSlot;
  final DateTime? collectedAt;
  final DateTime? droppedOffAt;
  final DateTime? receivedAt;

  /// The branch the laundry goes to (the destination once a pickup is collected).
  final String? branchName;
  final double? branchLat;
  final double? branchLng;
  final PickupMethod pickupMethod;

  bool get hasLocation => lat != null && lng != null;
  bool get isPickup => type == DeliveryType.pickup;
  bool get hasBranchLocation => branchLat != null && branchLng != null;

  /// After collecting a pickup the next stop is the branch, not the customer.
  bool get headingToBranch => isPickup && status == DeliveryStatus.collected && hasBranchLocation;

  static double? _dn(dynamic v) => v == null ? null : (v as num).toDouble();
  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  factory DeliveryTask.fromJson(Map<String, dynamic> j) => DeliveryTask(
        id: j['id'] as String,
        orderId: j['orderId'] as String? ?? '',
        orderNumber: j['orderNumber'] as String?,
        customerName: j['customerName'] as String?,
        type: DeliveryType.from((j['type'] as num?)?.toInt()),
        status: DeliveryStatus.from((j['status'] as num?)?.toInt()),
        scheduledAt: _dt(j['scheduledAt']),
        completedAt: _dt(j['completedAt']),
        address: j['address'] as String?,
        contactPhone: j['contactPhone'] as String?,
        proofPhotoUrl: j['proofPhotoUrl'] as String?,
        failureReason: j['failureReason'] as String?,
        rejectionReason: j['rejectionReason'] as String?,
        rejectedByName: j['rejectedByName'] as String?,
        attemptNumber: (j['attemptNumber'] as num?)?.toInt() ?? 1,
        createdAt: _dt(j['createdAt']) ?? DateTime.now(),
        lat: _dn(j['latitude']),
        lng: _dn(j['longitude']),
        awaitingCustomerSlot: j['awaitingCustomerSlot'] as bool? ?? false,
        collectedAt: _dt(j['collectedAt']),
        droppedOffAt: _dt(j['droppedOffAt']),
        receivedAt: _dt(j['receivedAt']),
        branchName: j['branchName'] as String?,
        branchLat: _dn(j['branchLatitude']),
        branchLng: _dn(j['branchLongitude']),
        pickupMethod: PickupMethod.from((j['pickupMethod'] as num?)?.toInt()),
      );
}

/// Paged "my tasks" result (DriverTaskListResult) — includes the per-group counts for the tabs.
class DriverTaskPage {
  DriverTaskPage({
    required this.items,
    required this.page,
    required this.totalFiltered,
    required this.allCount,
    required this.todoCount,
    required this.activeCount,
    required this.completedCount,
    required this.issuesCount,
  });

  final List<DeliveryTask> items;
  final int page;
  final int totalFiltered;
  final int allCount;
  final int todoCount;
  final int activeCount;
  final int completedCount;
  final int issuesCount;

  int countFor(TaskGroup g) => switch (g) {
        TaskGroup.all => allCount,
        TaskGroup.todo => todoCount,
        TaskGroup.active => activeCount,
        TaskGroup.completed => completedCount,
        TaskGroup.issues => issuesCount,
      };

  factory DriverTaskPage.fromJson(Map<String, dynamic> j) => DriverTaskPage(
        items: (j['items'] as List? ?? const [])
            .map((e) => DeliveryTask.fromJson(e as Map<String, dynamic>))
            .toList(),
        page: (j['page'] as num?)?.toInt() ?? 1,
        totalFiltered: (j['totalFiltered'] as num?)?.toInt() ?? 0,
        allCount: (j['allCount'] as num?)?.toInt() ?? 0,
        todoCount: (j['todoCount'] as num?)?.toInt() ?? 0,
        activeCount: (j['activeCount'] as num?)?.toInt() ?? 0,
        completedCount: (j['completedCount'] as num?)?.toInt() ?? 0,
        issuesCount: (j['issuesCount'] as num?)?.toInt() ?? 0,
      );
}

/// Driver dashboard summary (DriverDashboardDto).
class DriverDashboard {
  DriverDashboard({
    required this.active,
    required this.recentCompleted,
    required this.activeCount,
    required this.pendingPickups,
    required this.pendingDeliveries,
    required this.inProgress,
    required this.todayCount,
    required this.upcomingCount,
    required this.completedTotal,
    this.upcoming = const [],
    this.todayPickups = 0,
    this.todayDeliveries = 0,
    this.completedToday = 0,
    this.completedThisWeek = 0,
    this.issuesCount = 0,
    this.failedCount = 0,
    this.successRate,
    this.unscheduledCount = 0,
  });

  final List<DeliveryTask> active;
  final List<DeliveryTask> recentCompleted;
  final int activeCount;
  final int pendingPickups;
  final int pendingDeliveries;
  final int inProgress;
  final int todayCount;
  final int upcomingCount;
  final int completedTotal;
  /// Next scheduled open tasks (soonest first, ≤ 5) — "Up next".
  final List<DeliveryTask> upcoming;
  final int todayPickups;
  final int todayDeliveries;
  final int completedToday;
  final int completedThisWeek;
  final int issuesCount;
  final int failedCount;
  /// Completed ÷ (completed + failed) in %, null until something has finished.
  final int? successRate;
  final int unscheduledCount;

  static List<DeliveryTask> _list(dynamic v) =>
      (v as List? ?? const []).map((e) => DeliveryTask.fromJson(e as Map<String, dynamic>)).toList();
  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  factory DriverDashboard.fromJson(Map<String, dynamic> j) => DriverDashboard(
        active: _list(j['active']),
        recentCompleted: _list(j['recentCompleted']),
        activeCount: _i(j['activeCount']),
        pendingPickups: _i(j['pendingPickups']),
        pendingDeliveries: _i(j['pendingDeliveries']),
        inProgress: _i(j['inProgress']),
        todayCount: _i(j['todayCount']),
        upcomingCount: _i(j['upcomingCount']),
        completedTotal: _i(j['completedTotal']),
        upcoming: _list(j['upcoming']),
        todayPickups: _i(j['todayPickups']),
        todayDeliveries: _i(j['todayDeliveries']),
        completedToday: _i(j['completedToday']),
        completedThisWeek: _i(j['completedThisWeek']),
        issuesCount: _i(j['issuesCount']),
        failedCount: _i(j['failedCount']),
        successRate: j['successRate'] == null ? null : _i(j['successRate']),
        unscheduledCount: _i(j['unscheduledCount']),
      );
}

/// The driver's editable profile + read-only status (DriverProfileModel + extras).
class DriverProfile {
  DriverProfile({
    required this.fullName,
    this.phone,
    this.email,
    this.vehiclePlate,
    this.vehicleType,
    this.status = DriverStatus.available,
    this.photoUrl,
  });

  final String fullName;
  final String? phone;
  final String? email;
  final String? vehiclePlate;
  final String? vehicleType;
  final DriverStatus status;
  final String? photoUrl;

  factory DriverProfile.fromJson(Map<String, dynamic> j) => DriverProfile(
        fullName: j['fullName'] as String? ?? '',
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        vehiclePlate: j['vehiclePlate'] as String?,
        vehicleType: j['vehicleType'] as String?,
        status: DriverStatus.from((j['status'] as num?)?.toInt()),
        photoUrl: j['photoUrl'] as String?,
      );

  /// Editable fields only (DriverProfileModel) for PUT.
  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        if (phone != null) 'phone': phone,
        if (vehiclePlate != null) 'vehiclePlate': vehiclePlate,
        if (vehicleType != null) 'vehicleType': vehicleType,
      };
}
