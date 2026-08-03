// End-to-end test of the app's REAL networking layer (ApiClient + services + models) against a
// RUNNING SmartWash.Api. Not a mock — it hits http://localhost:5014.
//
// Run:  flutter test test/api_e2e_test.dart --dart-define=API_BASE_URL=http://localhost:5014
// (the API must be running first).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/api_client.dart';
import 'package:mobileapp/core/token_store.dart';
import 'package:mobileapp/models/profile.dart';
import 'package:mobileapp/services/auth_service.dart';
import 'package:mobileapp/services/notification_service.dart';
import 'package:mobileapp/services/order_service.dart';
import 'package:mobileapp/services/profile_service.dart';
import 'package:mobileapp/services/tenant_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 1) Let real network through (flutter_test blocks HttpClient by default).
  HttpOverrides.global = null;

  // 2) Back flutter_secure_storage with an in-memory map (no plugin in the test VM).
  final mem = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    final args = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'write': mem[args['key'] as String] = args['value'] as String; return null;
      case 'read': return mem[args['key'] as String];
      case 'delete': mem.remove(args['key'] as String); return null;
      case 'readAll': return Map<String, String>.from(mem);
      case 'deleteAll': mem.clear(); return null;
      case 'containsKey': return mem.containsKey(args['key'] as String);
    }
    return null;
  });

  final store = TokenStore(const FlutterSecureStorage());
  final api = ApiClient(store);
  final tenants = TenantService(api);
  final auth = AuthService(api);
  final orders = OrderService(api);
  final profile = ProfileService(api);
  final notifications = NotificationService(api);

  test('Customer journey end-to-end against the live API', () async {
    // --- 1. Public tenant directory (anonymous) ---
    final list = await tenants.list();
    expect(list, isNotEmpty, reason: 'tenant directory should return laundries');
    final nimbus = list.firstWhere((t) => t.identifier == 'nimbus');
    expect(nimbus.name, isNotEmpty);
    await store.setTenant(nimbus.identifier, nimbus.name);
    // ignore: avoid_print
    print('✓ directory: ${list.length} laundries; selected ${nimbus.identifier}');

    // --- 2. Register a fresh customer (tenant-scoped) ---
    final ts = DateTime.now().millisecondsSinceEpoch;
    final email = 'e2e$ts@nimbus.local';
    final phone = '+9665${(ts % 100000000).toString().padLeft(8, '0')}';
    final reg = await auth.register(fullName: 'E2E Tester', email: email, password: 'Passw0rd!', phone: phone);
    expect(reg.user.isCustomer, isTrue, reason: 'self-registered user is a Customer');
    await store.setTokens(reg.accessToken, reg.refreshToken);
    // ignore: avoid_print
    print('✓ register+login: $email (roleKinds=${reg.user.roleKinds})');

    // --- 3. Services catalog for the booking screen ---
    final services = await orders.services();
    expect(services, isNotEmpty, reason: 'services list drives "book a pickup"');
    // ignore: avoid_print
    print('✓ services: ${services.length} (${services.first.name} @ ${services.first.basePrice} ${services.first.currency})');

    // --- 4. Book a pickup ---
    final pickupAt = DateTime.now().add(const Duration(hours: 3));
    final orderId = await orders.bookPickup(
      pickupAt: pickupAt,
      pickupAddress: 'King Fahd Rd, Riyadh',
      contactPhone: '+966500000000',
      notes: 'Please handle with care',
      items: [(serviceId: services.first.id, quantity: 2, notes: null)],
    );
    expect(orderId, isNotEmpty);
    // ignore: avoid_print
    print('✓ book pickup: order $orderId');

    // --- 5. My orders now shows it ---
    final page = await orders.myOrders();
    expect(page.allCount, greaterThanOrEqualTo(1));
    expect(page.items.any((o) => o.id == orderId), isTrue);
    // ignore: avoid_print
    print('✓ my orders: allCount=${page.allCount}');

    // --- 6. Order detail + timeline (self-scoped) ---
    final detail = await orders.detail(orderId);
    expect(detail.orderNumber, isNotEmpty);
    expect(detail.items, isNotEmpty);
    expect(detail.canReschedule, isTrue, reason: 'a just-placed order can be rescheduled');
    final timeline = await orders.timeline(orderId);
    expect(timeline, isNotEmpty, reason: 'placing an order seeds a timeline entry');
    // ignore: avoid_print
    print('✓ detail ${detail.orderNumber}: ${detail.items.length} items, total ${detail.total} ${detail.currency}; timeline=${timeline.length}');

    // --- 7. Reschedule the pickup ---
    await orders.reschedulePickup(orderId, DateTime.now().add(const Duration(days: 1)));
    // ignore: avoid_print
    print('✓ reschedule pickup: ok');

    // --- 8. Profile get + update round-trip ---
    final p0 = await profile.get();
    expect(p0.fullName, isNotEmpty);
    await profile.update(CustomerProfile(
      fullName: p0.fullName, phone: p0.phone, email: p0.email, address: p0.address, city: 'Jeddah',
    ));
    final p1 = await profile.get();
    expect(p1.city, 'Jeddah');
    // ignore: avoid_print
    print('✓ profile: "${p0.fullName}" -> city=${p1.city}');

    // --- 9. Notifications feed reachable ---
    final unread = await notifications.unreadCount();
    final all = await notifications.all();
    expect(unread, greaterThanOrEqualTo(0));
    // ignore: avoid_print
    print('✓ notifications: unread=$unread, total=${all.length}');

    // --- 10. Public tracking by order number ---
    final tracked = await orders.track(tenant: nimbus.identifier, number: detail.orderNumber);
    expect(tracked, isNotNull);
    expect(tracked!.orderNumber, detail.orderNumber);
    // ignore: avoid_print
    print('✓ track ${tracked.orderNumber}: status=${tracked.status.label}, timeline=${tracked.timeline.length}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
