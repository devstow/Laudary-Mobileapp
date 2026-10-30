import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The installed app as Android reports it (package, build, signing certificate, install permission).
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.versionCode,
    required this.versionName,
    required this.certSha256,
    required this.sdk,
    required this.canInstall,
    required this.cacheDir,
    required this.freeBytes,
  });
  final String packageName;
  final int versionCode;
  final String versionName;
  final String? certSha256;
  final int sdk;
  final bool canInstall;
  final String cacheDir;
  final int freeBytes;
}

/// Result of checking a downloaded APK before it is handed to Android's installer.
class ApkCheck {
  const ApkCheck(this.ok, {this.code, this.message});
  final bool ok;
  /// missing / checksum / invalid / package / version / incompatible / signature
  final String? code;
  final String? message;
}

/// What Android's PackageInstaller reported: pendingUserAction, success, aborted (the user cancelled),
/// blocked, conflict (signature / version), incompatible, invalid, storage, failure.
class InstallStatus {
  const InstallStatus(this.status, this.message);
  final String status;
  final String? message;
}

/// Dart side of `AppUpdater.kt` (channel `smartwash/updater`). Android only — elsewhere [supported] is false
/// and the app never offers an in-app update (iOS / web builds are not distributed as APKs).
class NativeUpdater {
  NativeUpdater() {
    if (supported) _channel.setMethodCallHandler(_onCall);
  }

  static const MethodChannel _channel = MethodChannel('smartwash/updater');
  static bool get supported => !kIsWeb && Platform.isAndroid;

  final _statuses = StreamController<InstallStatus>.broadcast();
  Stream<InstallStatus> get statuses => _statuses.stream;

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'installStatus') {
      final m = Map<String, dynamic>.from(call.arguments as Map);
      _statuses.add(InstallStatus(m['status'] as String? ?? 'failure', m['message'] as String?));
    }
  }

  Future<InstalledApp> info() async {
    final m = Map<String, dynamic>.from((await _channel.invokeMethod<Map>('info'))!);
    return InstalledApp(
      packageName: m['packageName'] as String,
      versionCode: (m['versionCode'] as num).toInt(),
      versionName: m['versionName'] as String? ?? '',
      certSha256: m['certSha256'] as String?,
      sdk: (m['sdk'] as num).toInt(),
      canInstall: m['canInstall'] as bool? ?? false,
      cacheDir: m['cacheDir'] as String,
      freeBytes: (m['freeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  Future<bool> openInstallSettings() async => await _channel.invokeMethod<bool>('openInstallSettings') ?? false;

  Future<ApkCheck> verify(String path, String sha256, int versionCode) async {
    final m = Map<String, dynamic>.from((await _channel.invokeMethod<Map>('verify', {'path': path, 'sha256': sha256, 'versionCode': versionCode}))!);
    return ApkCheck(m['ok'] as bool? ?? false, code: m['code'] as String?, message: m['message'] as String?);
  }

  /// Hands the verified file to Android's installer and returns the mechanism used ("installer" = the system
  /// installer screen, "session" = PackageInstaller session). [mode] null = best for this Android version. The
  /// outcome arrives on [statuses].
  Future<String> install(String path, {String? mode}) async =>
      await _channel.invokeMethod<String>('install', {'path': path, 'mode': mode}) ?? 'installer';
}
