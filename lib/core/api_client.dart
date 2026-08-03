import 'package:dio/dio.dart';

import 'config.dart';
import 'token_store.dart';

/// Thin wrapper around Dio that:
///  - attaches `X-Tenant-Id` (selected laundry) + `Authorization: Bearer` + `Accept-Language`,
///  - transparently refreshes the access token on a 401 and retries once,
///  - signals the app to sign out when the refresh token is also dead.
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
        final tenant = await _store.tenant;
        if (tenant != null) options.headers['X-Tenant-Id'] = tenant;
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
          final replayed = await _tryRefreshAndReplay(response.requestOptions);
          if (replayed != null) return handler.resolve(replayed);
          _onSessionExpired?.call();
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

  Future<Response?> _tryRefreshAndReplay(RequestOptions original) async {
    final refresh = await _store.refreshToken;
    final tenant = await _store.tenant;
    if (refresh == null || tenant == null) return null;

    // Bare Dio (no interceptors) to avoid recursion.
    final bare = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, validateStatus: (s) => s != null && s < 500));
    final res = await bare.post(
      '/api/auth/refresh',
      data: {'refreshToken': refresh},
      options: Options(headers: {'X-Tenant-Id': tenant}),
    );
    if (res.statusCode != 200 || res.data is! Map) return null;

    final data = res.data as Map;
    await _store.setTokens(data['accessToken'] as String, data['refreshToken'] as String);

    // Replay the original request with the fresh token.
    original.headers['Authorization'] = 'Bearer ${data['accessToken']}';
    try {
      return await dio.fetch(original);
    } catch (_) {
      return null;
    }
  }
}
