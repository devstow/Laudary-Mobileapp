import '../core/api_client.dart';
import '../models/notification.dart';
import 'api_exception.dart';

class NotificationService {
  NotificationService(this._api);
  final ApiClient _api;

  Future<List<AppNotification>> all({int take = 100}) async {
    final res = await _api.dio.get('/api/notifications/all', queryParameters: {'take': take});
    if (!isOk(res)) throw ApiException.from(res);
    return (res.data as List).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<int> unreadCount() async {
    final res = await _api.dio.get('/api/notifications/unread-count');
    if (!isOk(res)) return 0;
    return ((res.data as Map)['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String id) async {
    await _api.dio.post('/api/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    await _api.dio.post('/api/notifications/read-all');
  }

  Future<void> clearAll() async {
    await _api.dio.post('/api/notifications/clear-all');
  }
}
