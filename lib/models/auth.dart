import 'dart:convert';

/// The signed-in user summary returned by /api/auth/*.
class AuthUser {
  AuthUser({required this.id, required this.tenantId, required this.fullName, required this.email, required this.roleKinds});
  final String id;
  final String tenantId;
  final String fullName;
  final String email;
  final List<int> roleKinds;

  bool get isCustomer => roleKinds.contains(6);
  bool get isDriver => roleKinds.contains(5);

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as String,
        tenantId: j['tenantId'] as String? ?? '',
        fullName: j['fullName'] as String? ?? '',
        email: j['email'] as String? ?? '',
        roleKinds: (j['roleKinds'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const [],
      );

  /// Reconstruct the user from a stored JWT access token (claims: sub, tid, name,
  /// email, rolekind). Used on app resume so the session — and the greeting/name —
  /// survives a restart without a fresh login. Returns null if the token is unreadable.
  static AuthUser? fromJwt(String? token) {
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final map = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
      final rk = map['rolekind'];
      final roleKinds = <int>[];
      if (rk is List) {
        for (final e in rk) {
          final v = int.tryParse('$e');
          if (v != null) roleKinds.add(v);
        }
      } else {
        final v = int.tryParse('$rk');
        if (v != null) roleKinds.add(v);
      }
      return AuthUser(
        id: (map['sub'] as String?) ?? '',
        tenantId: (map['tid'] as String?) ?? '',
        fullName: (map['name'] as String?) ?? '',
        email: (map['email'] as String?) ?? '',
        roleKinds: roleKinds,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Full auth response (access + refresh tokens + user).
class AuthResult {
  AuthResult({required this.accessToken, required this.refreshToken, required this.user});
  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        user: AuthUser.fromJson(j['user'] as Map<String, dynamic>),
      );
}
