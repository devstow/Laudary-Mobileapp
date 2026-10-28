// End-to-end test of the app's REAL live-tracking client (ApiClient + TrackingService) against a RUNNING
// SmartWash.Api. Uses SIMULATED GPS fixes (marked isMocked) — the device GPS / foreground service is not
// exercised here (needs a phone or emulator).
//
// Run:  flutter test test/tracking_e2e_test.dart --dart-define=API_BASE_URL=http://localhost:5014
// (the API must be running; seed driver shahid.mehmood@alnoorlaundry.pk / AlNoor@2026, Lahore Main Branch).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/api_client.dart';
import 'package:mobileapp/core/token_store.dart';
import 'package:mobileapp/services/auth_service.dart';
import 'package:mobileapp/services/tracking_service.dart';

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
  final tracking = TrackingService(api);

  test('Driver tracking client: config → batched fixes → geofence → stop', () async {
    final res = await auth.login('shahid.mehmood@alnoorlaundry.pk', 'AlNoor@2026');
    expect(res.user.isDriver, isTrue);
    await store.setTokens(res.accessToken, res.refreshToken);

    // 1. Config: branch geofences + the send policy.
    final cfg = await tracking.config();
    expect(cfg, isNotNull);
    expect(cfg!.geofences, isNotEmpty);
    final lahore = cfg.geofences.firstWhere((g) => g.name.contains('Lahore'));
    // ignore: avoid_print
    print('✓ config: ${cfg.geofences.length} geofences, send every ${cfg.sendDistanceMeters} m / ${cfg.sendIntervalSeconds}s, keep-alive ${cfg.heartbeatSeconds}s');

    // 2. An offline-buffer style batch approaching the branch, oldest → newest, ending inside the geofence.
    final now = DateTime.now().toUtc();
    final fixes = List.generate(5, (i) {
      final metresSouth = 2000 - i * 500; // 2000, 1500, 1000, 500, 0
      return LocationFix(
        lat: lahore.lat - metresSouth / 111320, lng: lahore.lng,
        recordedAt: now.subtract(Duration(seconds: (4 - i) * 10)),
        accuracy: 8, speed: 9, heading: 0, isMocked: true,
      );
    });
    final sent = await tracking.send(fixes);
    expect(sent.ok, isTrue);
    expect(sent.insideBranchId, lahore.branchId, reason: 'the newest fix is at the branch → inside its geofence');
    // ignore: avoid_print
    print('✓ batch of ${fixes.length} accepted; inside ${lahore.name}');

    // 3. An invalid-only batch is dropped (400 → ok=false), not retried forever.
    final bad = await tracking.send([LocationFix(lat: 95, lng: 10, recordedAt: DateTime.now())]);
    expect(bad.ok, isFalse);
    expect(bad.notADriver, isFalse);

    // 4. Sign-out path.
    await tracking.stop();
    // ignore: avoid_print
    print('✓ stop sent');
  });
}
