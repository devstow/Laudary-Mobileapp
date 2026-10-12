// End-to-end test of the app's REAL driver networking layer (ApiClient + DeliveryService +
// DriverProfileService + models) against a RUNNING SmartWash.Api.
//
// Run:  flutter test test/driver_e2e_test.dart --dart-define=API_BASE_URL=http://localhost:5014
// (the API must be running; driver seed account driver@nimbus.local / Nimbus@123).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/api_client.dart';
import 'package:mobileapp/core/token_store.dart';
import 'package:mobileapp/models/enums.dart';
import 'package:mobileapp/services/auth_service.dart';
import 'package:mobileapp/services/delivery_service.dart';
import 'package:mobileapp/services/driver_profile_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

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
  final auth = AuthService(api);
  final deliveries = DeliveryService(api);
  final profile = DriverProfileService(api);

  test('Driver journey end-to-end against the live API', () async {
    // 1. Driver login → roleKinds contains 5 (Driver).
    final res = await auth.login('driver@nimbus.local', 'Nimbus@123');
    expect(res.user.isDriver, isTrue, reason: 'driver login carries RoleKind.Driver (5)');
    await store.setTokens(res.accessToken, res.refreshToken);
    // ignore: avoid_print
    print('✓ driver login: ${res.user.fullName} (roleKinds=${res.user.roleKinds})');

    // 2. Driver self-profile.
    final me = await profile.get();
    expect(me.fullName, isNotEmpty);
    // ignore: avoid_print
    print('✓ profile: ${me.fullName} · ${me.vehiclePlate ?? '—'}/${me.vehicleType ?? '—'} · status=${me.status.label}');

    // 3. Dashboard summary.
    final dash = await deliveries.dashboard();
    expect(dash.activeCount, greaterThanOrEqualTo(0));
    // ignore: avoid_print
    print('✓ dashboard: active=${dash.activeCount} pickups=${dash.pendingPickups} deliveries=${dash.pendingDeliveries} completedTotal=${dash.completedTotal} activeItems=${dash.active.length}');

    // 4. My tasks (All group) + per-group counts.
    final page = await deliveries.myTasks(group: TaskGroup.all, pageSize: 50);
    expect(page.allCount, greaterThanOrEqualTo(0));
    expect(page.items.length, lessThanOrEqualTo(50));
    // ignore: avoid_print
    print('✓ my tasks: all=${page.allCount} todo=${page.todoCount} active=${page.activeCount} completed=${page.completedCount} issues=${page.issuesCount}');

    // 5. Each task parses its core fields (type/status/order).
    for (final t in page.items) {
      expect(t.id, isNotEmpty);
      expect(DeliveryStatus.values.contains(t.status), isTrue);
      expect(DeliveryType.values.contains(t.type), isTrue);
    }

    // 6. Group filter narrows the set (Completed ⊆ All).
    final done = await deliveries.myTasks(group: TaskGroup.completed, pageSize: 50);
    expect(done.totalFiltered, lessThanOrEqualTo(page.allCount));
    // ignore: avoid_print
    print('✓ group filter: completed totalFiltered=${done.totalFiltered} (≤ all=${page.allCount})');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
