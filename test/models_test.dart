import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/models/enums.dart';
import 'package:mobileapp/models/order.dart';
import 'package:mobileapp/models/order_detail.dart';
import 'package:mobileapp/models/tenant.dart';
import 'package:mobileapp/widgets/ui.dart';

void main() {
  group('enum mapping (ints from the API)', () {
    test('OrderStatus.from', () {
      expect(OrderStatus.from(3), OrderStatus.ready);
      expect(OrderStatus.from(5), OrderStatus.delivered);
      expect(OrderStatus.from(null), OrderStatus.placed); // safe default
    });
    test('OrderType / PaymentStatus', () {
      expect(OrderType.from(1), OrderType.pickupAndDelivery);
      expect(PaymentStatus.from(2), PaymentStatus.paid);
    });
    test('status phase', () {
      expect(OrderStatus.delivered.phase, OrderPhase.done);
      expect(OrderStatus.cancelled.phase, OrderPhase.cancelled);
      expect(OrderStatus.ready.phase, OrderPhase.ready);
    });
  });

  test('OrderListItem.fromJson parses enums/money/dates', () {
    final o = OrderListItem.fromJson({
      'id': 'abc',
      'orderNumber': 'ORD-000125',
      'customerName': 'Sara',
      'status': 3,
      'type': 1,
      'paymentStatus': 2,
      'itemCount': 4,
      'total': 150.5,
      'amountPaid': 150.5,
      'balanceDue': 0,
      'currency': 'SAR',
      'createdAt': '2026-07-22T09:00:00Z',
    });
    expect(o.orderNumber, 'ORD-000125');
    expect(o.status, OrderStatus.ready);
    expect(o.type, OrderType.pickupAndDelivery);
    expect(o.paymentStatus, PaymentStatus.paid);
    expect(o.total, 150.5);
    expect(o.createdAt.isUtc, isFalse); // converted to local
  });

  test('CustomerOrderPage.fromJson maps statusCounts keys (int OR enum-name) to OrderStatus', () {
    // The live API serialises statusCounts with PascalCase enum-NAME keys
    // (e.g. "Delivered"), not ints — this is the bug that broke the dashboard.
    final p = CustomerOrderPage.fromJson({
      'items': const [],
      'page': 1,
      'totalFiltered': 0,
      'allCount': 12,
      'statusCounts': {'Ready': 2, 'Delivered': 30, 'PickupScheduled': 1},
      'totalBilled': 100.0,
      'totalPaid': 70.0,
      'outstanding': 30.0,
      'currency': 'SAR',
    });
    expect(p.allCount, 12);
    expect(p.statusCounts[OrderStatus.ready], 2);
    expect(p.statusCounts[OrderStatus.delivered], 30);
    expect(p.statusCounts[OrderStatus.pickupScheduled], 1);
    expect(p.outstanding, 30.0);

    // Integer keys must still work too.
    final p2 = CustomerOrderPage.fromJson({
      'items': const [],
      'allCount': 3,
      'statusCounts': {'3': 2, '5': 1},
      'currency': 'SAR',
    });
    expect(p2.statusCounts[OrderStatus.ready], 2);
    expect(p2.statusCounts[OrderStatus.delivered], 1);
  });

  test('TenantDirectoryItem.fromJson (id, no identifier)', () {
    final t = TenantDirectoryItem.fromJson({
      'id': '3804a8bb-a646-4185-89ff-f1097412152f',
      'name': 'Nimbus Cleaners',
      'logoUrl': null,
      'defaultLanguage': 'ar',
      'defaultCurrency': 'SAR',
      'appName': 'Nimbus',
    });
    expect(t.id, '3804a8bb-a646-4185-89ff-f1097412152f');
    expect(t.name, 'Nimbus Cleaners');
    expect(t.displayName, 'Nimbus');
    expect(t.defaultLanguage, 'ar');
    expect(t.defaultCurrency, 'SAR');
  });

  test('TenantChoice.fromJson (409 TenantSelectionRequired item)', () {
    final c = TenantChoice.fromJson({'tenantId': 'abc', 'name': 'Bravo Cleaners', 'logoUrl': '/uploads/x.png'});
    expect(c.tenantId, 'abc');
    expect(c.name, 'Bravo Cleaners');
    expect(c.logoUrl, '/uploads/x.png');
  });

  group('OrderDetail action gating', () {
    OrderDetail make(int status) => OrderDetail.fromJson({
          'id': 'x', 'orderNumber': 'O', 'status': status, 'type': 1, 'currency': 'SAR',
          'subtotal': 0, 'discountAmount': 0, 'expressSurcharge': 0, 'deliveryFee': 0,
          'taxAmount': 0, 'total': 0, 'amountPaid': 0, 'balanceDue': 0, 'paymentStatus': 0,
          'items': const [],
        });
    test('canReschedule before pickup only', () {
      expect(make(1).canReschedule, isTrue);  // Placed
      expect(make(8).canReschedule, isFalse); // PickedUp
    });
    test('canChooseDelivery only when Ready', () {
      expect(make(3).canChooseDelivery, isTrue);  // Ready
      expect(make(1).canChooseDelivery, isFalse);
    });
  });

  test('money() formats with the currency code', () {
    final s = money(150, 'SAR', 'en');
    expect(s.contains('SAR'), isTrue);
    expect(s.contains('150'), isTrue);
  });
}
