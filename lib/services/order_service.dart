import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/map_settings.dart';
import '../models/order.dart';
import '../models/order_detail.dart';
import '../models/order_invoice.dart';
import '../models/order_receipt.dart';
import '../models/service_item.dart';
import 'api_exception.dart';

class OrderService {
  OrderService(this._api);
  final ApiClient _api;

  /// GET /api/portal/orders — my orders (filters + paging + payment aggregates).
  Future<CustomerOrderPage> myOrders({
    String? q,
    int? status,
    int? type,
    int? payment,
    int page = 1,
    int pageSize = 25,
  }) async {
    final params = <String, dynamic>{'page': page, 'pageSize': pageSize};
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    if (status != null) params['status'] = status;
    if (type != null) params['type'] = type;
    if (payment != null) params['payment'] = payment;

    final res = await _api.dio.get('/api/portal/orders', queryParameters: params);
    if (!isOk(res)) throw ApiException.from(res);
    return CustomerOrderPage.fromJson(res.data as Map<String, dynamic>);
  }

  /// GET /api/portal/map-settings — tenant map centre/country for the pickup picker.
  /// Falls back to a KSA default if the endpoint is unavailable.
  Future<MapSettings> mapSettings() async {
    try {
      final res = await _api.dio.get('/api/portal/map-settings');
      if (!isOk(res) || res.data is! Map) return MapSettings.fallback;
      return MapSettings.fromJson(res.data as Map<String, dynamic>);
    } catch (_) {
      return MapSettings.fallback;
    }
  }

  /// POST /api/portal/orders — book a pickup (Pickup & Delivery request).
  Future<String> bookPickup({
    required DateTime pickupAt,
    String? pickupAddress,
    double? lat,
    double? lng,
    String? contactPhone,
    String? notes,
    required List<({String serviceId, int quantity, String? notes})> items,
  }) async {
    final data = <String, dynamic>{
      'pickupAt': pickupAt.toUtc().toIso8601String(),
      'items': items.map((i) {
        final m = <String, dynamic>{'serviceId': i.serviceId, 'quantity': i.quantity};
        if (i.notes != null) m['notes'] = i.notes;
        return m;
      }).toList(),
    };
    if (pickupAddress != null) data['pickupAddress'] = pickupAddress;
    if (lat != null) data['pickupLatitude'] = lat;
    if (lng != null) data['pickupLongitude'] = lng;
    if (contactPhone != null) data['contactPhone'] = contactPhone;
    if (notes != null) data['notes'] = notes;

    final res = await _api.dio.post('/api/portal/orders', data: data);
    if (!isOk(res)) throw ApiException.from(res);
    return (res.data as Map)['id'] as String;
  }

  /// PUT /api/portal/orders/{id} — edit my own order (only before collection; server-enforced).
  Future<void> updateOrder({
    required String orderId,
    required DateTime pickupAt,
    String? pickupAddress,
    double? lat,
    double? lng,
    String? contactPhone,
    String? notes,
    required List<({String serviceId, int quantity, String? notes})> items,
  }) async {
    final data = <String, dynamic>{
      'pickupAt': pickupAt.toUtc().toIso8601String(),
      'items': items.map((i) {
        final m = <String, dynamic>{'serviceId': i.serviceId, 'quantity': i.quantity};
        if (i.notes != null) m['notes'] = i.notes;
        return m;
      }).toList(),
    };
    if (pickupAddress != null) data['pickupAddress'] = pickupAddress;
    if (lat != null) data['pickupLatitude'] = lat;
    if (lng != null) data['pickupLongitude'] = lng;
    if (contactPhone != null) data['contactPhone'] = contactPhone;
    if (notes != null) data['notes'] = notes;

    final res = await _api.dio.put('/api/portal/orders/$orderId', data: data);
    if (!isOk(res)) throw ApiException.from(res);
  }

  Future<void> reschedulePickup(String orderId, DateTime pickupAt) async {
    final res = await _api.dio.post('/api/portal/orders/$orderId/pickup-time', data: {'pickupAt': pickupAt.toUtc().toIso8601String()});
    if (!isOk(res)) throw ApiException.from(res);
  }

  Future<void> setDeliveryTime(String orderId, DateTime deliveryAt) async {
    final res = await _api.dio.post('/api/portal/orders/$orderId/delivery-time', data: {'deliveryAt': deliveryAt.toUtc().toIso8601String()});
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// POST /api/portal/orders/{id}/cancel — cancel my own order (only before collection; server-enforced).
  Future<void> cancelOrder(String orderId, {String? reason}) async {
    final res = await _api.dio.post('/api/portal/orders/$orderId/cancel', data: {'reason': reason});
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// DELETE /api/portal/orders/{id} — soft-delete my own order (only before collection; server-enforced).
  Future<void> deleteOrder(String orderId) async {
    final res = await _api.dio.delete('/api/portal/orders/$orderId');
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// GET /api/portal/orders/{id}/invoice — the order's invoice (self-scoped).
  Future<OrderInvoice> invoice(String orderId) async {
    final res = await _api.dio.get('/api/portal/orders/$orderId/invoice');
    if (!isOk(res)) throw ApiException.from(res);
    return OrderInvoice.fromJson(res.data as Map<String, dynamic>);
  }

  /// GET /api/portal/orders/{id}/receipt — the order's payment receipt (self-scoped).
  Future<OrderReceipt> receipt(String orderId) async {
    final res = await _api.dio.get('/api/portal/orders/$orderId/receipt');
    if (!isOk(res)) throw ApiException.from(res);
    return OrderReceipt.fromJson(res.data as Map<String, dynamic>);
  }

  /// GET /api/portal/orders/{id}/receipt/pdf — the rendered receipt PDF bytes (authenticated).
  Future<List<int>> receiptPdfBytes(String orderId) async {
    final res = await _api.dio.get<List<int>>(
      '/api/portal/orders/$orderId/receipt/pdf',
      queryParameters: {'download': true},
      options: Options(responseType: ResponseType.bytes),
    );
    if (res.statusCode != 200 || res.data == null) throw ApiException.from(res);
    return res.data!;
  }

  /// GET /api/track — public tracking (anonymous). Order number + the phone on the order
  /// (contact or customer phone) are both required; null when no match (404).
  Future<OrderTracking?> track({required String number, required String phone}) async {
    final res = await _api.dio.get('/api/track', queryParameters: {'number': number, 'phone': phone});
    if (res.statusCode == 404) return null;
    if (!isOk(res)) throw ApiException.from(res);
    return OrderTracking.fromJson(res.data as Map<String, dynamic>);
  }

  /// GET /api/portal/orders/{id} — full order detail (self-scoped).
  Future<OrderDetail> detail(String id) async {
    final res = await _api.dio.get('/api/portal/orders/$id');
    if (!isOk(res)) throw ApiException.from(res);
    return OrderDetail.fromJson(res.data as Map<String, dynamic>);
  }

  /// GET /api/portal/orders/{id}/timeline — status history.
  Future<List<OrderEvent>> timeline(String id) async {
    final res = await _api.dio.get('/api/portal/orders/$id/timeline');
    if (!isOk(res)) throw ApiException.from(res);
    return (res.data as List).map((e) => OrderEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/portal/services — active services for the "book a pickup" screen.
  /// Server-side search + paging so the picker stays fast with large catalogs.
  Future<List<ServiceItem>> services({String? q, int page = 1, int pageSize = 20}) async {
    final params = <String, dynamic>{'page': page, 'pageSize': pageSize};
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    final res = await _api.dio.get('/api/portal/services', queryParameters: params);
    if (!isOk(res)) throw ApiException.from(res);
    return (res.data as List).map((e) => ServiceItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}

