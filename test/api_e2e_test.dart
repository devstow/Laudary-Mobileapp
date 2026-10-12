// End-to-end test of the app's REAL networking layer (ApiClient + services + models) against a
// RUNNING SmartWash.Api. Not a mock — it hits http://localhost:5014.
//
// Run:  flutter test test/api_e2e_test.dart --dart-define=API_BASE_URL=http://localhost:5014
// (the API must be running first).
//
// Contract under test (no X-Tenant-Id anywhere — the tenant comes from the JWT after login):
//   directory (id) → register { …, tenantId } → login { email, password } → … →
//   public track ?number=&phone= ; plus the 409 TenantSelectionRequired → select-tenant path.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/api_client.dart';
import 'package:mobileapp/core/token_store.dart';
import 'package:mobileapp/models/profile.dart';
import 'package:mobileapp/services/api_exception.dart';
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
    await store.clearAll();

    // --- 1. Public tenant directory (anonymous) — items carry `id`, no identifier ---
    final list = await tenants.list();
    expect(list, isNotEmpty, reason: 'tenant directory should return laundries');
    // Prefer the Nimbus demo laundry; fall back to the first operational one if it isn't listed.
    final nimbus = list.firstWhere((t) => t.name == 'Nimbus Cleaners', orElse: () => list.first);
    expect(nimbus.id, isNotEmpty);
    final one = await tenants.get(nimbus.id);
    expect(one?.id, nimbus.id);
    // ignore: avoid_print
    print('✓ directory: ${list.length} laundries; chose ${nimbus.name} (${nimbus.id})');

    // --- 2. Register a fresh customer into the chosen laundry (tenantId in the body) ---
    final ts = DateTime.now().millisecondsSinceEpoch;
    final email = 'e2e$ts@e2e.local';
    final phone = '+9665${(ts % 100000000).toString().padLeft(8, '0')}';
    final reg = await auth.register(
        tenantId: nimbus.id, fullName: 'E2E Tester', email: email, password: 'Passw0rd!', phone: phone);
    expect(reg.user.isCustomer, isTrue, reason: 'self-registered user is a Customer');
    expect(reg.user.tenantId, nimbus.id, reason: 'registered into the chosen laundry');
    // ignore: avoid_print
    print('✓ register: $email (roleKinds=${reg.user.roleKinds})');

    // --- 3. Login with credentials ONLY (no tenant) ---
    final login = await auth.login(email, 'Passw0rd!');
    expect(login.user.tenantId, nimbus.id, reason: 'tenant resolved server-side from the account');
    expect(login.user.isCustomer, isTrue);
    await store.setTokens(login.accessToken, login.refreshToken);
    // Branding for the signed-in laundry comes from the directory by user.tenantId.
    final brand = await tenants.get(login.user.tenantId);
    expect(brand?.name, nimbus.name);
    // ignore: avoid_print
    print('✓ login (credentials only): tenantId=${login.user.tenantId}; branding=${brand?.displayName}');

    // --- 4. Services catalog for the booking screen ---
    final services = await orders.services();
    expect(services, isNotEmpty, reason: 'services list drives "book a pickup"');
    // ignore: avoid_print
    print('✓ services: ${services.length} (${services.first.name} @ ${services.first.basePrice} ${services.first.currency})');

    // --- 5. Book a pickup ---
    const contactPhone = '+966500000000';
    final pickupAt = DateTime.now().add(const Duration(hours: 3));
    final orderId = await orders.bookPickup(
      pickupAt: pickupAt,
      pickupAddress: 'King Fahd Rd, Riyadh',
      contactPhone: contactPhone,
      notes: 'Please handle with care',
      items: [(serviceId: services.first.id, quantity: 2, notes: null)],
    );
    expect(orderId, isNotEmpty);
    // ignore: avoid_print
    print('✓ book pickup: order $orderId');

    // --- 6. My orders now shows it ---
    final page = await orders.myOrders();
    expect(page.allCount, greaterThanOrEqualTo(1));
    expect(page.items.any((o) => o.id == orderId), isTrue);
    // ignore: avoid_print
    print('✓ my orders: allCount=${page.allCount}');

    // --- 7. Order detail + timeline (self-scoped) ---
    final detail = await orders.detail(orderId);
    expect(detail.orderNumber, isNotEmpty);
    expect(detail.items, isNotEmpty);
    expect(detail.canReschedule, isTrue, reason: 'a just-placed order can be rescheduled');
    final timeline = await orders.timeline(orderId);
    expect(timeline, isNotEmpty, reason: 'placing an order seeds a timeline entry');
    // ignore: avoid_print
    print('✓ detail ${detail.orderNumber}: ${detail.items.length} items, total ${detail.total} ${detail.currency}; timeline=${timeline.length}');

    // --- 8. Reschedule the pickup ---
    await orders.reschedulePickup(orderId, DateTime.now().add(const Duration(days: 1)));
    // ignore: avoid_print
    print('✓ reschedule pickup: ok');

    // --- 9. Profile get + update round-trip ---
    final p0 = await profile.get();
    expect(p0.fullName, isNotEmpty);
    await profile.update(CustomerProfile(
      fullName: p0.fullName, phone: p0.phone, email: p0.email, address: p0.address, city: 'Jeddah',
    ));
    final p1 = await profile.get();
    expect(p1.city, 'Jeddah');
    // ignore: avoid_print
    print('✓ profile: "${p0.fullName}" -> city=${p1.city}');

    // --- 10. Notifications feed reachable ---
    final unread = await notifications.unreadCount();
    final all = await notifications.all();
    expect(unread, greaterThanOrEqualTo(0));
    // ignore: avoid_print
    print('✓ notifications: unread=$unread, total=${all.length}');

    // --- 11. Public tracking: order number + phone (both required, no tenant) ---
    final tracked = await orders.track(number: detail.orderNumber, phone: contactPhone);
    expect(tracked, isNotNull);
    expect(tracked!.orderNumber, detail.orderNumber);
    final wrongPhone = await orders.track(number: detail.orderNumber, phone: '+966511111111');
    expect(wrongPhone, isNull, reason: 'a non-matching phone must not reveal the order');
    // ignore: avoid_print
    print('✓ track ${tracked.orderNumber}: status=${tracked.status.label}, timeline=${tracked.timeline.length}; wrong phone → not found');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Same credentials in two laundries → 409 choose business → select-tenant', () async {
    await store.clearAll();

    final list = await tenants.list();
    expect(list.length, greaterThanOrEqualTo(2), reason: 'needs two operational laundries in the directory');
    final a = list[0];
    final b = list[1];

    final ts = DateTime.now().millisecondsSinceEpoch;
    final email = 'multi$ts@e2e.local';
    const password = 'Passw0rd!';
    await auth.register(tenantId: a.id, fullName: 'Multi Tenant', email: email, password: password);
    await auth.register(tenantId: b.id, fullName: 'Multi Tenant', email: email, password: password);
    // ignore: avoid_print
    print('✓ registered $email into "${a.name}" and "${b.name}"');

    // Login → the server can't pick for us → TenantSelectionRequired with both businesses.
    TenantSelectionRequired? choice;
    try {
      await auth.login(email, password);
    } on TenantSelectionRequired catch (e) {
      choice = e;
    }
    expect(choice, isNotNull, reason: 'login must answer 409 TenantSelectionRequired');
    expect(choice!.selectionToken, isNotEmpty);
    final offered = choice.tenants.map((t) => t.tenantId).toSet();
    expect(offered, containsAll([a.id, b.id]));
    expect(choice.tenants.every((t) => t.name.isNotEmpty), isTrue);
    // ignore: avoid_print
    print('✓ login → 409: ${choice.tenants.map((t) => t.name).join(' | ')}');

    // Choose the second laundry → AuthResponse for exactly that tenant.
    final res = await auth.selectTenant(selectionToken: choice.selectionToken, tenantId: b.id);
    expect(res.user.tenantId, b.id);
    expect(res.accessToken, isNotEmpty);
    // ignore: avoid_print
    print('✓ select-tenant → signed in to "${b.name}" (tenantId=${res.user.tenantId})');

    // A bogus selection token is rejected with 401 TenantSelectionInvalid.
    try {
      await auth.selectTenant(selectionToken: 'not-a-valid-token', tenantId: b.id);
      fail('select-tenant with a bad token must fail');
    } on ApiException catch (e) {
      expect(e.statusCode, 401);
      expect(e.title, 'TenantSelectionInvalid');
      // ignore: avoid_print
      print('✓ bad selection token → 401 ${e.title}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Password reset by OTP — email only, no tenant field', () async {
    await store.clearAll();
    final list = await tenants.list();
    final t = list.first;
    final email = 'otp${DateTime.now().millisecondsSinceEpoch}@e2e.local';
    await auth.register(tenantId: t.id, fullName: 'OTP Tester', email: email, password: 'Passw0rd!');

    final devCode = await auth.requestPasswordOtp(email: email);
    if (devCode == null) {
      // ignore: avoid_print
      print('• OTP reset: requested (no devCode — server not in Development)');
      return;
    }
    await auth.verifyOtp(email: email, code: devCode);
    await auth.resetPasswordWithOtp(email: email, code: devCode, newPassword: 'N3wPassw0rd!');
    final again = await auth.login(email, 'N3wPassw0rd!');
    expect(again.user.tenantId, t.id);
    // ignore: avoid_print
    print('✓ OTP reset: request → verify → reset → login with new password');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
