import '../core/api_client.dart';
import '../models/tenant.dart';
import 'api_exception.dart';

/// Public laundry directory (anonymous). Used by the registration flow ("choose your laundry")
/// and to load the signed-in user's branding.
class TenantService {
  TenantService(this._api);
  final ApiClient _api;

  Future<List<TenantDirectoryItem>> list({String? query}) async {
    final res = await _api.dio.get('/api/public/tenants', queryParameters: {
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'take': 100,
    });
    if (!isOk(res)) throw ApiException.from(res);
    return (res.data as List).map((e) => TenantDirectoryItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// One operational laundry by id; null when not found / not operational (404).
  Future<TenantDirectoryItem?> get(String id) async {
    final res = await _api.dio.get('/api/public/tenants/$id');
    if (res.statusCode == 404) return null;
    if (!isOk(res)) throw ApiException.from(res);
    return TenantDirectoryItem.fromJson(res.data as Map<String, dynamic>);
  }
}
