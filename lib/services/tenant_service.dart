import '../core/api_client.dart';
import '../models/tenant.dart';
import 'api_exception.dart';

/// Public "find your laundry" directory (anonymous — no tenant/token needed).
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
}
