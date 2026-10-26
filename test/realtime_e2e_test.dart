// End-to-end test of the app's REAL-TIME layer (RealtimeClient over SignalR) against a RUNNING
// SmartWash.Api — the same hub the app connects to after login.
//
// Run:  flutter test test/realtime_e2e_test.dart --dart-define=API_BASE_URL=https://smartwash-staging-api.20-203-96-110.nip.io
//
// Signs in as a seeded Al Noor customer, connects to /hubs/realtime with the JWT, books a pickup through
// the API and expects an `order.*` push plus the "Order placed" notification for it (then cancels the order). Proves: JWT via access_token, group membership for the signed-in
// user, event capture after commit, and delivery to the mobile client.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/api_client.dart';
import 'package:mobileapp/core/realtime.dart';
import 'package:mobileapp/core/token_store.dart';
import 'package:mobileapp/services/auth_service.dart';
import 'package:mobileapp/services/order_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // real network

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
  final orders = OrderService(api);

  test('Customer receives a live order.updated push for their own order', () async {
    await store.clearAll();
    final login = await auth.login('ayesha.malik@inbox.com.pk', 'AlNoor@2026');
    await store.setTokens(login.accessToken, login.refreshToken);

    // Connect first, then create an order of my own: the hub must push order.* for it.
    final realtime = RealtimeClient(store);
    final received = <RealtimeEvent>[];
    final sub = realtime.events.listen(received.add);
    await realtime.connect();
    for (var i = 0; i < 40 && !realtime.connected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(realtime.connected, isTrue, reason: 'hub connection should be established with the JWT');

    final services = await orders.services();
    expect(services, isNotEmpty, reason: 'the laundry needs at least one service to book');
    String? orderId;
    try {
      orderId = await orders.bookPickup(
        pickupAt: DateTime.now().add(const Duration(hours: 5)),
        pickupAddress: 'Realtime e2e — Gulberg, Lahore',
        contactPhone: '+923001234567',
        notes: 'realtime e2e (auto-cancelled)',
        items: [(serviceId: services.first.id, quantity: 1, notes: null)],
      );

      RealtimeEvent? hit;
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (hit == null && DateTime.now().isBefore(deadline)) {
        hit = received.cast<RealtimeEvent?>().firstWhere((e) => e!.isOrder && e.orderId?.toLowerCase() == orderId!.toLowerCase(), orElse: () => null);
        if (hit == null) await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(hit, isNotNull, reason: 'expected an order.* push for $orderId; got ${received.map((e) => e.kind).toList()}');
      // ignore: avoid_print
      print('✓ live push: ${hit!.kind} ${hit.orderNumber} status=${hit.status}');
      // The "Order placed" in-app notification is pushed to the same user too.
      final noteDeadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(noteDeadline) && !received.any((e) => e.isNotification)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(received.any((e) => e.isNotification), isTrue, reason: 'expected a notification push');
    } finally {
      if (orderId != null) {
        try { await orders.cancelOrder(orderId, reason: 'realtime e2e cleanup'); } catch (_) {}
      }
      await sub.cancel();
      await realtime.disconnect();
    }
  });
}
