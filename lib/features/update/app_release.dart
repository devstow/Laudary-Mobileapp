import 'package:dio/dio.dart';

import '../../core/config.dart';

/// The published Android release as `GET api/public/app-release/android?build=<installed>` describes it. The server
/// reads the same release manifest the landing page uses (written by tool/publish_apk.ps1) — the app never hardcodes
/// a "latest version".
class AppRelease {
  const AppRelease({
    required this.applicationId,
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.sha256,
    required this.certSha256,
    required this.releasedAt,
    required this.notes,
    required this.notesAr,
    required this.minSupportedVersionCode,
    required this.updateAvailable,
    required this.mandatory,
    required this.problem,
  });

  final String? applicationId;
  final String versionName;
  final int versionCode;
  final String downloadUrl;
  final int sizeBytes;
  final String? sha256;
  final String? certSha256;
  final DateTime? releasedAt;
  final String? notes;
  final String? notesAr;
  final int minSupportedVersionCode;
  final bool updateAvailable;
  final bool mandatory;
  final String? problem;

  String label() => '$versionName ($versionCode)';
  String? notesFor(String lang) => lang == 'ar' && (notesAr ?? '').trim().isNotEmpty ? notesAr : notes;

  /// Null when the payload is unusable (missing version code / URL) — treated like "no release".
  static AppRelease? fromJson(Map<String, dynamic> j) {
    final code = (j['versionCode'] as num?)?.toInt();
    final url = j['downloadUrl'] as String?;
    if (code == null || url == null || url.isEmpty) return null;
    return AppRelease(
      applicationId: j['applicationId'] as String?,
      versionName: (j['versionName'] as String?) ?? '$code',
      versionCode: code,
      downloadUrl: url,
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: (j['sha256'] as String?)?.toLowerCase(),
      certSha256: (j['certSha256'] as String?)?.toLowerCase(),
      releasedAt: DateTime.tryParse(j['releasedAtUtc'] as String? ?? ''),
      notes: j['releaseNotes'] as String?,
      notesAr: j['releaseNotesAr'] as String?,
      minSupportedVersionCode: (j['minSupportedVersionCode'] as num?)?.toInt() ?? 0,
      updateAvailable: j['updateAvailable'] as bool? ?? false,
      mandatory: j['mandatory'] as bool? ?? false,
      problem: j['problem'] as String?,
    );
  }
}

/// Thrown when the release could not be checked (offline, server down, bad payload).
class ReleaseCheckFailed implements Exception {
  const ReleaseCheckFailed(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

class AppReleaseService {
  /// Best-effort diagnostics: tells the server how an in-app update went on this device (stage + outcome), so a
  /// failure like "downloaded, then nothing" is visible in the server log. Never throws.
  Future<void> report(Map<String, Object?> data) async {
    try {
      await _dio.post('/api/public/app-release/android/report', data: data, options: Options(validateStatus: (_) => true));
    } catch (_) {}
  }

  AppReleaseService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ));

  // Bare client: anonymous endpoint, no auth headers / refresh / session-expiry handling.
  final Dio _dio;

  /// The latest release compared with [installedBuild]; null when nothing is published (404).
  Future<AppRelease?> latest(int installedBuild) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/api/public/app-release/android',
          queryParameters: {'build': installedBuild}, options: Options(validateStatus: (s) => s == 200 || s == 404));
      if (res.statusCode == 404 || res.data == null) return null;
      final r = AppRelease.fromJson(res.data!);
      if (r == null) throw const ReleaseCheckFailed('invalid release metadata');
      return r;
    } on DioException catch (e) {
      throw ReleaseCheckFailed(e.type.name);
    }
  }
}
