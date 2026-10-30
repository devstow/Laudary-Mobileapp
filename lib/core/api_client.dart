import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'config.dart';
import 'token_store.dart';

/// Thin wrapper around Dio that:
///  - attaches `Authorization: Bearer` + `Accept-Language` (the tenant comes from the JWT),
///  - transparently refreshes the access token on a 401 and retries once,
///  - signals the app to sign out when the refresh token is also dead.
///
/// Refresh is SINGLE-FLIGHT: the server rotates refresh tokens and rejects a token that was already used, so when
/// several requests hit an expired access token at once (dashboards load in parallel) only ONE refresh call is made
/// and every waiting request reuses its result. Before, each request refreshed with the same token, all but the first
/// were rejected as "revoked" and the app signed the user out — the "logged out for no reason" bug.
class ApiClient {
  ApiClient(this._store) {
    dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      // Treat non-2xx as responses (not throws) so services can map ProblemDetails cleanly.
      validateStatus: (s) => s != null && s < 500,
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _store.accessToken;
        if (token != null && options.headers['Authorization'] == null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        final locale = await _store.locale;
        options.headers['Accept-Language'] = locale ?? 'en';
        handler.next(options);
      },
      onResponse: (response, handler) async {
        // 401 on an authenticated call → try one silent refresh + replay.
        if (response.statusCode == 401 && !_isAuthCall(response.requestOptions.path)) {
          _expired = false;
          final replayed = await _tryRefreshAndReplay(response.requestOptions);
          if (replayed != null) return handler.resolve(replayed);
          if (_expired) _onSessionExpired?.call();
        }
        handler.next(response);
      },
    ));
  }

  final TokenStore _store;
  late final Dio dio;

  void Function()? _onSessionExpired;
  set onSessionExpired(void Function() cb) => _onSessionExpired = cb;

  bool _isAuthCall(String path) => path.contains('/api/auth/');

  Future<String?>? _refreshing;

  /// One refresh at a time; concurrent callers share it. Returns the new access token, or null when the session is
  /// really over (refresh token expired / revoked). Network errors throw (the session is kept, the call just fails).
  Future<String?> refreshSession() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<String?> _doRefresh() async {
    final refresh = await _store.refreshToken;
    if (refresh == null) return null;
    // Bare Dio (no interceptors) to avoid recursion.
    final bare = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: AppConfig.connectTimeout, validateStatus: (s) => s != null && s < 500));
    final res = await bare.post('/api/auth/refresh', data: {'refreshToken': refresh});
    if (res.statusCode != 200 || res.data is! Map) return null;
    final data = res.data as Map;
    await _store.setTokens(data['accessToken'] as String, data['refreshToken'] as String);
    return data['accessToken'] as String;
  }

  /// A usable access token for non-Dio clients (SignalR): refreshed first when it expires within a minute.
  Future<String?> freshAccessToken() async {
    final token = await _store.accessToken;
    if (token == null) return null;
    final exp = _expiry(token);
    if (exp != null && exp.isAfter(DateTime.now().add(const Duration(seconds: 60)))) return token;
    try {
      return await refreshSession() ?? token;
    } catch (_) {
      return token; // offline: let the hub fail and retry later
    }
  }

  static DateTime? _expiry(String jwt) {
    try {
      final parts = jwt.split('.');
      final map = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
      final exp = (map['exp'] as num?)?.toInt();
      return exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (_) {
      return null;
    }
  }

  Future<Response?> _tryRefreshAndReplay(RequestOptions original) async {
    final String? access;
    try {
      access = await refreshSession();
    } catch (_) {
      return null; // no network: not a sign-out, the request just fails
    }
    if (access == null) {
      _expired = true;
      return null;
    }
    // Replay the original request with the fresh token.
    original.headers['Authorization'] = 'Bearer $access';
    try {
      return await dio.fetch(original);
    } catch (_) {
      return null;
    }
  }

  // Set when the refresh token itself was rejected — only then is the session really over.
  bool _expired = false;
}
