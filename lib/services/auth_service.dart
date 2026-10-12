import '../core/api_client.dart';
import '../models/auth.dart';
import '../models/tenant.dart';
import 'api_exception.dart';

/// Thrown by [AuthService.login] when the same email+password belong to accounts in several
/// businesses (409 TenantSelectionRequired). Show [tenants] and call [AuthService.selectTenant].
class TenantSelectionRequired implements Exception {
  TenantSelectionRequired({required this.selectionToken, required this.tenants, this.message});
  final String selectionToken;
  final List<TenantChoice> tenants;
  final String? message;

  @override
  String toString() => message ?? 'TenantSelectionRequired';
}

class AuthService {
  AuthService(this._api);
  final ApiClient _api;

  /// POST /api/auth/login — credentials only; the tenant comes back inside the JWT.
  /// Throws [TenantSelectionRequired] when the user must choose a business first.
  Future<AuthResult> login(String email, String password) async {
    final res = await _api.dio.post('/api/auth/login', data: {'email': email, 'password': password});
    if (res.statusCode == 409 && res.data is Map) {
      final d = res.data as Map;
      final token = d['selectionToken'];
      final list = d['tenants'];
      if (token is String && list is List) {
        throw TenantSelectionRequired(
          selectionToken: token,
          tenants: list.map((e) => TenantChoice.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
          message: d['detail'] as String?,
        );
      }
    }
    if (!isOk(res)) throw ApiException.from(res);
    return AuthResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// POST /api/auth/login/select-tenant — completes a multi-business login.
  /// A 401 with title "TenantSelectionInvalid" means the selection token expired (5 min).
  Future<AuthResult> selectTenant({required String selectionToken, required String tenantId}) async {
    final res = await _api.dio.post('/api/auth/login/select-tenant',
        data: {'selectionToken': selectionToken, 'tenantId': tenantId});
    if (!isOk(res)) throw ApiException.from(res);
    return AuthResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// POST /api/auth/register — customer sign-up into the chosen laundry ([tenantId] = directory `id`).
  Future<AuthResult> register({
    required String tenantId,
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    final res = await _api.dio.post('/api/auth/register', data: {
      'fullName': fullName,
      'email': email,
      'password': password,
      if (phone != null && phone.isNotEmpty) 'phoneNumber': phone,
      'tenantId': tenantId,
    });
    if (!isOk(res)) throw ApiException.from(res);
    return AuthResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _api.dio.post('/api/auth/logout', data: {'refreshToken': refreshToken});
    } catch (_) {/* best effort */}
  }

  Future<void> forgotPassword(String email) async {
    await _api.dio.post('/api/auth/forgot-password', data: {'email': email});
  }

  /// Request a password-reset OTP. Returns a `devCode` when the server is in Development
  /// (no live SMTP) so the flow is testable; null in production (the code arrives by email).
  Future<String?> requestPasswordOtp({required String email}) async {
    final res = await _api.dio.post('/api/auth/forgot-password-otp', data: {'email': email});
    if (!isOk(res)) throw ApiException.from(res);
    if (res.data is Map) return (res.data as Map)['devCode']?.toString();
    return null;
  }

  /// Verify an OTP (does not consume it) — gates the new-password step.
  Future<void> verifyOtp({required String email, required String code}) async {
    final res = await _api.dio.post('/api/auth/verify-otp', data: {'email': email, 'code': code});
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// Set a new password using a verified OTP.
  Future<void> resetPasswordWithOtp({required String email, required String code, required String newPassword}) async {
    final res = await _api.dio.post('/api/auth/reset-password-otp',
        data: {'email': email, 'code': code, 'newPassword': newPassword});
    if (!isOk(res)) throw ApiException.from(res);
  }
}
