import '../core/api_client.dart';
import '../models/auth.dart';
import 'api_exception.dart';

class AuthService {
  AuthService(this._api);
  final ApiClient _api;

  Future<AuthResult> login(String email, String password) async {
    final res = await _api.dio.post('/api/auth/login', data: {'email': email, 'password': password});
    if (!isOk(res)) throw ApiException.from(res);
    return AuthResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AuthResult> register({required String fullName, required String email, required String password, String? phone}) async {
    final res = await _api.dio.post('/api/auth/register', data: {
      'fullName': fullName,
      'email': email,
      'password': password,
      if (phone != null && phone.isNotEmpty) 'phoneNumber': phone,
    });
    if (!isOk(res)) throw ApiException.from(res);
    return AuthResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _api.dio.post('/api/auth/logout', data: {'refreshToken': refreshToken});
    } catch (_) {/* best effort */}
  }

  Future<void> forgotPassword(String tenantIdentifier, String email) async {
    await _api.dio.post('/api/auth/forgot-password', data: {'tenantIdentifier': tenantIdentifier, 'email': email});
  }

  /// Request a password-reset OTP. Returns a `devCode` when the server is in Development
  /// (no live SMTP) so the flow is testable; null in production (the code arrives by email).
  Future<String?> requestPasswordOtp({required String tenantIdentifier, required String email}) async {
    final res = await _api.dio.post('/api/auth/forgot-password-otp',
        data: {'tenantIdentifier': tenantIdentifier, 'email': email});
    if (!isOk(res)) throw ApiException.from(res);
    if (res.data is Map) return (res.data as Map)['devCode']?.toString();
    return null;
  }

  /// Verify an OTP (does not consume it) — gates the new-password step.
  Future<void> verifyOtp({required String tenantIdentifier, required String email, required String code}) async {
    final res = await _api.dio.post('/api/auth/verify-otp',
        data: {'tenantIdentifier': tenantIdentifier, 'email': email, 'code': code});
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// Set a new password using a verified OTP.
  Future<void> resetPasswordWithOtp({
    required String tenantIdentifier,
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final res = await _api.dio.post('/api/auth/reset-password-otp',
        data: {'tenantIdentifier': tenantIdentifier, 'email': email, 'code': code, 'newPassword': newPassword});
    if (!isOk(res)) throw ApiException.from(res);
  }
}
