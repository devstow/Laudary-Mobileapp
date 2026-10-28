import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/delivery.dart';
import '../models/driver_task_detail.dart';
import '../models/enums.dart';
import 'api_exception.dart';

/// Driver delivery-task API (api/deliveries/*). Self-scoped server-side to the signed-in driver.
class DeliveryService {
  DeliveryService(this._api);
  final ApiClient _api;

  static String _d(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  /// GET /api/deliveries/mine — the driver's own tasks, filtered + paged.
  Future<DriverTaskPage> myTasks({
    String? q,
    TaskGroup group = TaskGroup.all,
    int? type,
    int? priority,
    DateTime? scheduledOn,
    DateTime? assignedOn,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String, dynamic>{'group': group.value, 'page': page, 'pageSize': pageSize};
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    if (type != null) params['type'] = type;
    if (priority != null) params['priority'] = priority;
    if (scheduledOn != null) params['scheduledOn'] = _d(scheduledOn);
    if (assignedOn != null) params['assignedOn'] = _d(assignedOn);

    final res = await _api.dio.get('/api/deliveries/mine', queryParameters: params);
    if (!isOk(res)) throw ApiException.from(res);
    return DriverTaskPage.fromJson(res.data as Map<String, dynamic>);
  }

  /// GET /api/deliveries/mine/{id} — one of my tasks in full (order summary, items, instructions,
  /// amount to collect, the order's other legs, attempt history). 404 for a task that isn't mine.
  Future<DriverTaskDetail> taskDetail(String id) async {
    final res = await _api.dio.get('/api/deliveries/mine/$id');
    if (!isOk(res)) throw ApiException.from(res);
    return DriverTaskDetail.fromJson(res.data as Map<String, dynamic>);
  }

  /// GET /api/deliveries/my-dashboard — KPIs + active + recent completed.
  Future<DriverDashboard> dashboard() async {
    final res = await _api.dio.get('/api/deliveries/my-dashboard');
    if (!isOk(res)) throw ApiException.from(res);
    return DriverDashboard.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> accept(String id) async {
    final res = await _api.dio.post('/api/deliveries/$id/accept');
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// Reject a task before accepting it — reason is mandatory (server 400s otherwise).
  Future<void> reject(String id, String reason) async {
    final res = await _api.dio.post('/api/deliveries/$id/reject', data: {'reason': reason});
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// Fail a task in progress — reason is mandatory.
  Future<void> fail(String id, String reason) async {
    final res = await _api.dio.post('/api/deliveries/$id/fail', data: {'reason': reason});
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// Generic status change (Start → InTransit(2), Arrived(8)). App enforces the order.
  Future<void> setStatus(String id, DeliveryStatus status) async {
    final res = await _api.dio.post('/api/deliveries/$id/status', data: {'status': status.value});
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// Complete a task, optionally attaching a proof-of-delivery photo (multipart).
  Future<void> complete(String id, {String? proofImagePath}) async {
    if (proofImagePath == null) {
      // No photo → the plain status change to Completed(3).
      final res = await _api.dio.post('/api/deliveries/$id/complete');
      if (!isOk(res)) throw ApiException.from(res);
      return;
    }
    final form = FormData.fromMap({
      'proof': await MultipartFile.fromFile(proofImagePath, filename: 'proof.jpg'),
    });
    final res = await _api.dio.post('/api/deliveries/$id/complete', data: form);
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// Pickup leg: the collected laundry was handed over at the branch (Collected → Dropped off).
  /// The branch then confirms receipt. Idempotent server-side.
  Future<void> dropOff(String id) async {
    final res = await _api.dio.post('/api/deliveries/$id/dropoff');
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// POST /api/deliveries/location — geofence heartbeat. Returns order numbers that auto-arrived.
  Future<List<String>> location(double lat, double lng) async {
    try {
      final res = await _api.dio.post('/api/deliveries/location', data: {'lat': lat, 'lng': lng});
      if (!isOk(res) || res.data is! Map) return const [];
      final arrived = (res.data as Map)['arrived'];
      if (arrived is List) return arrived.map((e) => e.toString()).toList();
      return const [];
    } catch (_) {
      return const []; // heartbeat is best-effort
    }
  }
}
