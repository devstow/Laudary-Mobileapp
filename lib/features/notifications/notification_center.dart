import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/realtime.dart';

/// The signed-in user's unread notification count — ONE source for the in-app bells and the launcher badge.
///
/// The number is always the server's (`GET api/notifications/unread-count`, scoped to the JWT user); it is never
/// incremented locally, so duplicate / replayed realtime events, reconnects or a second device can't skew it.
/// Re-read on: sign-in / session restore, every realtime `notification` (new) and `notifications.changed` (read or
/// cleared, here or elsewhere), hub reconnect, app resume, and after the user reads notifications. Reads are
/// coalesced (a burst of events = one request).
///
/// Android (native AppNotifications.kt): the count drives the launcher badge; while the app is in the background
/// new notifications also become system notifications; a device token lets a WorkManager job keep the badge in
/// sync every ~15 min after the app is closed. Sign-out revokes the device token and clears badge + notifications.
class NotificationCenter extends ChangeNotifier with WidgetsBindingObserver {
  NotificationCenter(this._api, this._realtime, {required this.lang}) {
    _rtSub = _realtime.events.listen(_onEvent);
    _realtime.addListener(_onConnection);
    if (_native) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'open') _open.add(call.arguments as String);
      });
    }
  }

  static const MethodChannel _channel = MethodChannel('smartwash/notify');
  static bool get _native => !kIsWeb && Platform.isAndroid;

  final ApiClient _api;
  final RealtimeClient _realtime;
  final String Function() lang;
  StreamSubscription<RealtimeEvent>? _rtSub;

  int unread = 0;
  String? _userId;
  bool _foreground = true;
  bool _wasConnected = false;
  Timer? _debounce;
  Future<void>? _inFlight;
  bool _again = false;
  bool _newArrived = false;

  final _open = StreamController<String>.broadcast();
  /// Notification taps: "notifications" (the summary) or "notification:ID".
  Stream<String> get opens => _open.stream;

  void _log(String m) => debugPrint('[notify] $m');

  /// Signed in (login or restored session): register this install for background sync and read the count.
  Future<void> start(String userId) async {
    _userId = userId;
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
    if (_native) {
      try {
        final s = Map<String, dynamic>.from(await _channel.invokeMethod<Map>('session') ?? {});
        if (s['deviceToken'] == null || s['userId'] != userId) {
          final res = await _api.dio.post('/api/notifications/devices', data: {'platform': 'android', 'appVersion': AppConfig.appVersion});
          final token = (res.data is Map) ? (res.data as Map)['deviceToken'] as String? : null;
          if (token != null) {
            await _channel.invokeMethod('configure', {'deviceToken': token, 'userId': userId, 'apiBase': AppConfig.apiBaseUrl, 'lang': lang()});
            _log('device registered');
          }
        } else {
          await _channel.invokeMethod('setLanguage', {'lang': lang()});
        }
        await _channel.invokeMethod('requestPermission');
      } catch (e) {
        _log('device registration failed: $e'); // in-app count still works
      }
    }
    await refresh();
  }

  /// Signed out: revoke the device token (works even if the session already expired), clear badge + notifications.
  Future<void> stop() async {
    _userId = null;
    _debounce?.cancel();
    unread = 0;
    notifyListeners();
    if (!_native) return;
    try {
      final s = Map<String, dynamic>.from(await _channel.invokeMethod<Map>('session') ?? {});
      final token = s['deviceToken'] as String?;
      await _channel.invokeMethod('clearSession');
      if (token != null) {
        await Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 8)))
            .post('/api/notifications/devices/revoke', options: Options(headers: {'X-Device-Token': token}, validateStatus: (_) => true));
      }
    } catch (e) {
      _log('sign-out cleanup: $e'); // the server also drops the token once the session is gone
    }
  }

  Future<void> languageChanged() async {
    if (_native) await _channel.invokeMethod('setLanguage', {'lang': lang()});
  }

  /// Any taps that opened the app before Dart was listening (cold start from a notification).
  Future<String?> launchTarget() async => _native ? await _channel.invokeMethod<String>('launchTarget') : null;

  void _onEvent(RealtimeEvent e) {
    if (e.isNotification) _newArrived = true;
    if (e.isNotification || e.isNotificationsChanged) _schedule();
  }

  void _onConnection() {
    final c = _realtime.connected;
    if (c && !_wasConnected) _schedule(); // (re)connected: events missed meanwhile are not replayed → re-read
    _wasConnected = c;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _schedule();
  }

  void _schedule() {
    if (_userId == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => unawaited(refresh()));
  }

  /// Re-reads the authoritative count (serialized: a call during a read queues one more read). Returns the count,
  /// or null when it could not be read (offline) — the last known value is kept then.
  Future<int?> refresh() async {
    if (_userId == null) return null;
    if (_inFlight != null) {
      _again = true;
      await _inFlight;
      return unread;
    }
    final f = _read();
    _inFlight = f;
    try {
      await f;
    } finally {
      _inFlight = null;
    }
    if (_again) {
      _again = false;
      return refresh();
    }
    return unread;
  }

  Future<void> _read() async {
    try {
      final res = await _api.dio.get('/api/notifications/unread-count');
      if (res.statusCode != 200 || res.data is! Map) return;
      final n = ((res.data as Map)['count'] as num?)?.toInt() ?? 0;
      if (_userId == null) return; // signed out meanwhile
      final arrived = _newArrived;
      _newArrived = false;
      if (n != unread) {
        unread = n;
        notifyListeners();
      }
      if (_native) {
        await _channel.invokeMethod('setBadge', {'count': n});
        if (arrived) await _surface();
      }
    } catch (e) {
      _log('count not refreshed: $e');
    }
  }

  // New notification: in the background → system notification (localized list from the API); in the foreground the
  // app shows it itself, so its ids are only marked as seen (the background job must not pop them later).
  Future<void> _surface() async {
    try {
      final res = await _api.dio.get('/api/notifications/all', queryParameters: {'take': 5});
      if (res.statusCode != 200 || res.data is! List) return;
      final unreadItems = (res.data as List).whereType<Map>().where((m) => m['isRead'] != true).toList();
      if (_foreground) {
        await _channel.invokeMethod('markSeen', {'ids': unreadItems.map((m) => '${m['id']}').toList()});
      } else {
        await _channel.invokeMethod('showItems', {'items': jsonEncode(unreadItems)});
      }
    } catch (e) {
      _log('surface failed: $e');
    }
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _realtime.removeListener(_onConnection);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
