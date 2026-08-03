import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/delivery.dart';
import 'api_exception.dart';

/// Driver self-profile API (api/drivers/me).
class DriverProfileService {
  DriverProfileService(this._api);
  final ApiClient _api;

  Future<DriverProfile> get() async {
    final res = await _api.dio.get('/api/drivers/me');
    if (!isOk(res)) throw ApiException.from(res);
    return DriverProfile.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> update(DriverProfile p) async {
    final res = await _api.dio.put('/api/drivers/me', data: p.toJson());
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// Upload a new avatar (multipart, field "photo"). Returns the absolute photo URL.
  Future<String> uploadPhoto(String filePath) async {
    final form = FormData.fromMap({
      'photo': await MultipartFile.fromFile(filePath, filename: 'photo.jpg'),
    });
    final res = await _api.dio.post('/api/drivers/me/photo', data: form);
    if (!isOk(res)) throw ApiException.from(res);
    return (res.data as Map<String, dynamic>)['photoUrl'] as String;
  }

  /// Remove the current avatar.
  Future<void> removePhoto() async {
    final res = await _api.dio.delete('/api/drivers/me/photo');
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// Change the account password.
  Future<void> changePassword(String current, String next) async {
    final res = await _api.dio.post('/api/drivers/me/change-password',
        data: {'currentPassword': current, 'newPassword': next});
    if (!isOk(res)) throw ApiException.from(res);
  }
}
