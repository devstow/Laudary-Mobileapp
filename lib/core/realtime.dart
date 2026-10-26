import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';

import 'config.dart';
import 'token_store.dart';

/// One real-time push from the API (RealtimeDispatcher payload). `kind` is `order.created`,
/// `order.updated`, `task.created`, `task.updated` or `notification`.
class RealtimeEvent {
  RealtimeEvent({
    required this.id,
    required this.kind,
    this.orderId,
    this.orderNumber,
    this.status,
    this.paymentStatus,
    this.taskId,
    this.taskStatus,
    this.notification,
  });

  final String id;
  final String kind;
  final String? orderId;
  final String? orderNumber;
  final String? status;
  final String? paymentStatus;
  final String? taskId;
  final String? taskStatus;
  final RealtimeNotification? notification;

  bool get isOrder => kind.startsWith('order.');
  bool get isTask => kind.startsWith('task.');
  bool get isNotification => kind == 'notification';
  /// Anything that changes what an order/task screen shows.
  bool get touchesOrders => isOrder || isTask;

  factory RealtimeEvent.fromJson(Map<String, dynamic> j) => RealtimeEvent(
        id: (j['id'] ?? '').toString(),
        kind: (j['kind'] ?? '').toString(),
        orderId: j['orderId']?.toString(),
        orderNumber: j['orderNumber']?.toString(),
        status: j['status']?.toString(),
        paymentStatus: j['paymentStatus']?.toString(),
        taskId: j['taskId']?.toString(),
        taskStatus: j['taskStatus']?.toString(),
        notification: j['notification'] is Map ? RealtimeNotification.fromJson(Map<String, dynamic>.from(j['notification'] as Map)) : null,
      );
}

class RealtimeNotification {
  RealtimeNotification({required this.title, this.body, this.url, this.icon, this.color});
  final String title;
  final String? body;
  final String? url;
  final String? icon;
  final String? color;

  factory RealtimeNotification.fromJson(Map<String, dynamic> j) => RealtimeNotification(
        title: (j['title'] ?? '').toString(),
        body: j['body']?.toString(),
        url: j['url']?.toString(),
        icon: j['icon']?.toString(),
        color: j['color']?.toString(),
      );
}

/// SignalR connection to `{API}/hubs/realtime` (JWT via `access_token`). Lives for the signed-in
/// session: [connect] after login / session restore, [disconnect] on logout. Screens subscribe to
/// [events] and reload what they show; the 20-second polls stay as a fallback for when the socket
/// is down. Membership (tenant / branch / own user) is decided by the server from the token.
class RealtimeClient extends ChangeNotifier {
  RealtimeClient(this._store);

  final TokenStore _store;
  HubConnection? _conn;
  Timer? _retry;
  bool _wanted = false;
  final StreamController<RealtimeEvent> _events = StreamController<RealtimeEvent>.broadcast();
  final List<String> _seen = <String>[];

  Stream<RealtimeEvent> get events => _events.stream;
  RealtimeEvent? last;
  bool get connected => _conn?.state == HubConnectionState.Connected;

  Future<void> connect() async {
    _wanted = true;
    if (_conn != null) return;
    final conn = HubConnectionBuilder()
        .withUrl(
          '${AppConfig.apiBaseUrl}/hubs/realtime',
          options: HttpConnectionOptions(
            accessTokenFactory: () async => (await _store.accessToken) ?? '',
            transport: HttpTransportType.WebSockets,
          ),
        )
        .withAutomaticReconnect(retryDelays: const [0, 2000, 5000, 10000, 20000, 30000])
        .build();
    conn.on('event', _onEvent);
    conn.onreconnected(({connectionId}) => notifyListeners());
    conn.onclose(({error}) {
      notifyListeners();
      _scheduleRetry(); // automatic reconnect gave up (or the token expired) → start over later
    });
    _conn = conn;
    await _start();
  }

  Future<void> _start() async {
    final conn = _conn;
    if (conn == null || !_wanted) return;
    try {
      await conn.start();
      notifyListeners();
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (!_wanted) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 10), () {
      if (_wanted && _conn != null && _conn!.state == HubConnectionState.Disconnected) _start();
    });
  }

  Future<void> disconnect() async {
    _wanted = false;
    _retry?.cancel();
    final conn = _conn;
    _conn = null;
    if (conn != null) {
      try { await conn.stop(); } catch (_) {}
    }
    notifyListeners();
  }

  void _onEvent(List<Object?>? args) {
    if (args == null || args.isEmpty || args.first is! Map) return;
    final e = RealtimeEvent.fromJson(Map<String, dynamic>.from(args.first as Map));
    if (e.id.isNotEmpty) {
      if (_seen.contains(e.id)) return; // the server may hit this user through several groups
      _seen.add(e.id);
      if (_seen.length > 300) _seen.removeAt(0);
    }
    last = e;
    _events.add(e);
    notifyListeners();
  }

  @override
  void dispose() {
    _wanted = false;
    _retry?.cancel();
    _events.close();
    _conn?.stop();
    super.dispose();
  }
}
