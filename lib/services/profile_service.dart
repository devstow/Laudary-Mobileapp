import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/profile.dart';
import 'api_exception.dart';

class ProfileService {
  ProfileService(this._api);
  final ApiClient _api;

  Future<CustomerProfile> get() async {
    final res = await _api.dio.get('/api/portal/profile');
    if (!isOk(res)) throw ApiException.from(res);
    return CustomerProfile.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> update(CustomerProfile profile) async {
    final res = await _api.dio.put('/api/portal/profile', data: profile.toJson());
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// Upload a new avatar (multipart, field "photo"). Returns the absolute photo URL.
  Future<String> uploadPhoto(String filePath) async {
    final form = FormData.fromMap({
      'photo': await MultipartFile.fromFile(filePath, filename: 'photo.jpg'),
    });
    final res = await _api.dio.post('/api/portal/profile/photo', data: form);
    if (!isOk(res)) throw ApiException.from(res);
    return (res.data as Map<String, dynamic>)['photoUrl'] as String;
  }

  /// Remove the current avatar.
  Future<void> removePhoto() async {
    final res = await _api.dio.delete('/api/portal/profile/photo');
    if (!isOk(res)) throw ApiException.from(res);
  }

  /// Change the account password.
  Future<void> changePassword(String current, String next) async {
    final res = await _api.dio.post('/api/portal/profile/change-password',
        data: {'currentPassword': current, 'newPassword': next});
    if (!isOk(res)) throw ApiException.from(res);
  }
}
