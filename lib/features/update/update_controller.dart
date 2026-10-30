import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_release.dart';
import 'native_updater.dart';
import 'resume_point.dart';

enum UpdateOffer { none, optional, mandatory, mandatoryOffline }

/// Pure decision used at start-up and by the periodic check (unit-tested in test/update_policy_test.dart).
///  - release newer than the installed build → optional, or mandatory when the server says so;
///  - the check failed (offline / server down) → carry on, UNLESS an earlier successful check already said this
///    build must update ([knownRequiredBuild] > installed): a transient error never unlocks a known mandatory update;
///  - an optional release the user already postponed this session ([postponedBuild]) is not offered again until the
///    next launch.
UpdateOffer decideUpdate({required int installedBuild, AppRelease? release, bool checkFailed = false, int? knownRequiredBuild, int? postponedBuild}) {
  if (checkFailed || release == null) {
    return checkFailed && knownRequiredBuild != null && knownRequiredBuild > installedBuild ? UpdateOffer.mandatoryOffline : UpdateOffer.none;
  }
  if (!release.updateAvailable || release.versionCode <= installedBuild || release.problem != null) return UpdateOffer.none;
  if (release.mandatory) return UpdateOffer.mandatory;
  return postponedBuild == release.versionCode ? UpdateOffer.none : UpdateOffer.optional;
}

/// What the user sees, in order: downloading → verifying → installing (handing the file to Android) → waitingConfirm
/// (Android's own "Update this app?" screen is open) → completing (Android reported success; it now replaces and
/// restarts the app). notInstalled = the installer closed and this (old) version is still running.
enum UpdatePhase { idle, needsPermission, downloading, verifying, installing, waitingConfirm, completing, notInstalled, cancelled, failed }

/// In-app updates for the sideloaded Android APK. Owns the start-up check (before login / normal use), the periodic
/// check while the app is open, and the Update Now flow: install permission → download (progress) → verify
/// (SHA-256, package, version, signing certificate) → Android's installer. Nothing is reported as installed until
/// the app actually runs the new build (checked on the next launch).
class UpdateController extends ChangeNotifier with WidgetsBindingObserver {
  UpdateController({NativeUpdater? native, AppReleaseService? releases, FlutterSecureStorage? storage})
      : _native = native ?? NativeUpdater(),
        _releases = releases ?? AppReleaseService(),
        _storage = storage ?? const FlutterSecureStorage();

  final NativeUpdater _native;
  final AppReleaseService _releases;
  final FlutterSecureStorage _storage;

  static const _kRequired = 'upd_required_build';
  static const _kPending = 'upd_pending';
  static const _kResume = 'upd_resume';
  static const startupTimeout = Duration(seconds: 8);
  static const periodicInterval = Duration(minutes: 30);
  static const resumeRecheckAfter = Duration(minutes: 15);

  InstalledApp? installed;
  AppRelease? release;
  UpdateOffer offer = UpdateOffer.none;

  /// Start-up check finished (or not applicable) — the app may leave the splash.
  bool startupResolved = false;
  /// Shown full-screen instead of login / home until the user updates or (optional only) taps Later.
  bool gate = false;
  /// A release found while the app was in use, waiting to be shown as a prompt (once per build).
  AppRelease? prompt;

  UpdatePhase phase = UpdatePhase.idle;
  double? progress;
  int received = 0;
  String? errorCode;
  String? errorDetail;
  /// The verified file of this release is on the phone — Retry goes straight to the installer, no re-download.
  bool get downloadReady => _verifiedFor != null && _verifiedFor == release?.versionCode;
  int? _verifiedFor;
  String? _verifiedPath;
  /// Android's own installer screen is being used (fallback / Android ≤ 11).
  bool usingSystemInstaller = false;

  /// Set on the first launch after a successful update: the version now running + the screen to reopen.
  String? updatedTo;
  ResumePoint? _resume;
  /// Set when an update was started but the app still runs the old build (cancelled / failed install).
  bool lastAttemptNotInstalled = false;

  int? _postponed;
  int? _prompted;
  DateTime? _lastCheck;
  Timer? _timer;
  CancelToken? _cancel;
  StreamSubscription<InstallStatus>? _statusSub;
  bool _started = false;

  bool get supported => NativeUpdater.supported;
  bool get mandatory => offer == UpdateOffer.mandatory || offer == UpdateOffer.mandatoryOffline;
  bool get busy => phase == UpdatePhase.downloading || phase == UpdatePhase.verifying || phase == UpdatePhase.installing || phase == UpdatePhase.completing;
  String get currentLabel => installed == null ? '' : '${installed!.versionName} (${installed!.versionCode})';

  void _log(String m) => debugPrint('[update] $m');

  // ── start-up ────────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> startup() async {
    if (_started) return;
    _started = true;
    if (!supported) {
      startupResolved = true;
      notifyListeners();
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _statusSub = _native.statuses.listen(_onInstallStatus);
    try {
      installed = await _native.info();
      _log('installed ${installed!.packageName} ${installed!.versionName} (${installed!.versionCode}), canInstall=${installed!.canInstall}');
      await _afterUpdateCheck();
      await _check(startup: true).timeout(startupTimeout + const Duration(seconds: 2), onTimeout: () {});
    } catch (e) {
      _log('start-up check skipped: $e');
    }
    startupResolved = true;
    notifyListeners();
    _timer = Timer.periodic(periodicInterval, (_) => unawaited(_check()));
  }

  /// First launch after Update Now: did the new build actually install?
  Future<void> _afterUpdateCheck() async {
    final pending = await _read(_kPending);
    if (pending == null) return;
    await _storage.delete(key: _kPending);
    final m = jsonDecode(pending) as Map<String, dynamic>;
    final target = (m['target'] as num).toInt();
    if (installed!.versionCode >= target) {
      updatedTo = installed!.versionName;
      unawaited(_releases.report({'fromBuild': m['from'], 'toBuild': target, 'stage': 'runningNewVersion', 'sdk': installed!.sdk}));
      _resume = ResumePoint.fromJson(await _read(_kResume));
      _log('updated to ${installed!.versionCode}; resume=${_resume?.kind}');
      _cleanupDownloads();
    } else {
      lastAttemptNotInstalled = true;
      unawaited(_releases.report({'fromBuild': installed!.versionCode, 'toBuild': target, 'stage': 'notInstalledAfterRestart', 'sdk': installed!.sdk}));
      _log('update to $target was not installed (still ${installed!.versionCode})');
    }
    await _storage.delete(key: _kResume);
  }

  /// The screen to reopen after an update — handed out once, only to the same user, only while fresh.
  ResumePoint? takeResume(String userId) {
    final r = _resume;
    _resume = null;
    if (r == null || r.userId != userId || DateTime.now().difference(r.savedAt) > ResumePoint.maxAge) return null;
    return r;
  }

  String? takeUpdatedTo() {
    final v = updatedTo;
    updatedTo = null;
    return v;
  }

  // ── checks ──────────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> _check({bool startup = false}) async {
    if (installed == null || busy) return;
    _lastCheck = DateTime.now();
    AppRelease? r;
    var failed = false;
    try {
      r = await _releases.latest(installed!.versionCode).timeout(startupTimeout);
    } catch (e) {
      failed = true;
      _log('check failed: $e');
    }
    final known = int.tryParse(await _read(_kRequired) ?? '');
    final decision = decideUpdate(installedBuild: installed!.versionCode, release: r, checkFailed: failed, knownRequiredBuild: known, postponedBuild: _postponed);
    if (!failed) {
      // Remember a mandatory requirement so an offline launch cannot skip it; forget it once satisfied/withdrawn.
      if (decision == UpdateOffer.mandatory) {
        await _storage.write(key: _kRequired, value: '${r!.versionCode}');
      } else {
        await _storage.delete(key: _kRequired);
      }
    }
    if (r != null && r.problem != null) _log('release metadata problem: ${r.problem}');
    if (r != null && _certMismatch(r)) {
      // e.g. a developer build signed with another key: Android would reject the update, so don't offer it.
      _log('installed certificate ${installed!.certSha256} != release ${r.certSha256}: in-place update impossible');
      if (decision != UpdateOffer.none) {
        release = r;
        offer = decision;
        errorCode = 'signature';
        phase = UpdatePhase.failed;
        gate = startup || gate;
        notifyListeners();
        return;
      }
    }
    _log('check: installed ${installed!.versionCode}, latest ${r?.versionCode}, decision $decision');
    if (decision == UpdateOffer.none) {
      if (!busy && (gate || offer != UpdateOffer.none)) {
        offer = UpdateOffer.none;
        gate = false;
        notifyListeners();
      }
      return;
    }
    if (r != null) release = r;
    offer = decision;
    if (startup) {
      gate = true;
    } else if (_prompted != release?.versionCode || mandatory) {
      _prompted = release?.versionCode;
      prompt = release;
    }
    notifyListeners();
  }

  /// Manual / retry check (e.g. the mandatory-offline screen's Retry).
  Future<void> checkNow() async {
    phase = UpdatePhase.idle;
    errorCode = null;
    notifyListeners();
    await _check(startup: gate);
  }

  void promptShown() => prompt = null;

  /// Optional update postponed: carry on; asked again on the next launch (or when an even newer build appears).
  void later() {
    if (mandatory) return;
    _postponed = release?.versionCode;
    gate = false;
    prompt = null;
    if (!busy) phase = UpdatePhase.idle;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_onResumed());
  }

  Future<void> _onResumed() async {
    if (installed == null) return;
    if (phase == UpdatePhase.needsPermission) {
      installed = await _native.info();
      if (installed!.canInstall) {
        _log('install permission granted — continuing');
        unawaited(_run());
      }
      return;
    }
    if (_lastCheck == null || DateTime.now().difference(_lastCheck!) > resumeRecheckAfter) unawaited(_check());
  }

  // ── Update Now ──────────────────────────────────────────────────────────────────────────────────────────────

  /// Starts the update. [userId] (signed-in user) lets the new build reopen the current screen afterwards.
  Future<void> updateNow({String? userId}) async {
    if (release == null || busy) return;
    if (userId != null) await _storage.write(key: _kResume, value: ScreenTracker.snapshot(userId).toJson());
    await _storage.write(key: _kPending, value: jsonEncode({'target': release!.versionCode, 'from': installed?.versionCode, 'at': DateTime.now().toUtc().toIso8601String()}));
    await _run();
  }

  Future<void> retry() => _run();

  /// Hand the already verified file to the standard Android installer screen (works on every ROM).
  Future<void> installWithSystemInstaller() async {
    if (_verifiedPath == null || busy) return;
    await _install(_verifiedPath!, mode: 'installer');
  }

  Future<void> openInstallSettings() => _native.openInstallSettings();

  void cancelDownload() => _cancel?.cancel('user');

  Future<void> _run() async {
    final r = release;
    if (r == null || installed == null) return;
    // Signed with another key than the installed app (e.g. a developer build): Android would refuse it.
    if (_certMismatch(r)) return _fail('signature');
    errorCode = null;
    errorDetail = null;
    if (r.sha256 == null || r.sha256!.isEmpty) return _fail('metadata');
    if (kReleaseMode && !r.downloadUrl.startsWith('https://')) return _fail('metadata', 'Download URL is not HTTPS');

    installed = await _native.info();
    if (!installed!.canInstall) {
      _set(UpdatePhase.needsPermission);
      return;
    }
    // Room for the download + Android's copy while installing.
    final needed = r.sizeBytes * 2 + 50 * 1024 * 1024;
    if (r.sizeBytes > 0 && installed!.freeBytes < needed) return _fail('storage', '${(needed / 1048576).ceil()} MB');

    final dir = Directory(installed!.cacheDir);
    final file = File('${dir.path}/smartwash-${r.versionCode}.apk');
    final part = File('${file.path}.part');
    try {
      // A file already downloaded (and verified) for this build is reused on retry.
      if (!await file.exists()) {
        _set(UpdatePhase.downloading);
        progress = 0;
        received = 0;
        _cancel = CancelToken();
        if (await part.exists()) await part.delete();
        await Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 60))).download(
          r.downloadUrl,
          part.path,
          cancelToken: _cancel,
          onReceiveProgress: (got, total) {
            received = got;
            final t = total > 0 ? total : r.sizeBytes;
            progress = t > 0 ? (got / t).clamp(0, 1).toDouble() : null;
            notifyListeners();
          },
        );
        await part.rename(file.path);
      }
      _set(UpdatePhase.verifying);
      final check = await _native.verify(file.path, r.sha256!, r.versionCode);
      if (!check.ok) {
        _log('verify failed: ${check.code} ${check.message}');
        await _deleteQuietly(file);
        _verifiedFor = null;
        _verifiedPath = null;
        return _fail(check.code ?? 'invalid', check.message);
      }
      _verifiedFor = r.versionCode;
      _verifiedPath = file.path;
      unawaited(_report('verified'));
      await _install(file.path);
    } on DioException catch (e) {
      await _deleteQuietly(part);
      if (CancelToken.isCancel(e)) {
        _set(UpdatePhase.cancelled);
        errorCode = 'downloadCancelled';
        notifyListeners();
        return;
      }
      _fail(e.type == DioExceptionType.badResponse ? 'server' : 'network', e.message);
    } on FileSystemException catch (e) {
      await _deleteQuietly(part);
      _fail('storage', e.message);
    } catch (e) {
      _fail('failure', '$e');
    }
  }

  bool _certMismatch(AppRelease r) =>
      installed?.certSha256 != null && r.certSha256 != null && r.certSha256 != installed!.certSha256!.toLowerCase();

  // Straight on to Android's installer after a verified download — the user never looks for the file.
  Future<void> _install(String path, {String? mode}) async {
    errorCode = null;
    errorDetail = null;
    _set(UpdatePhase.installing);
    try {
      final used = await _native.install(path, mode: mode);
      usingSystemInstaller = used == 'installer';
      _log('installer started ($used) for ${release?.versionCode}');
      unawaited(_report('installer:$used'));
    } catch (e) {
      _fail('failure', '$e');
    }
  }

  void _onInstallStatus(InstallStatus s) {
    _log('installer: ${s.status} ${s.message ?? ''}');
    unawaited(_report(s.status, detail: s.message));
    switch (s.status) {
      case 'installerOpened':
      case 'pendingUserAction':
        _set(UpdatePhase.waitingConfirm);
      case 'fallbackInstaller':
        usingSystemInstaller = true;
        _set(UpdatePhase.waitingConfirm);
      case 'success':
        // Android replaces the app and stops this process; "updated" is confirmed by the next launch.
        _set(UpdatePhase.completing);
      case 'aborted':
      case 'installerClosed':
        // The installer closed and we are still the OLD version: cancelled (or failed inside the installer).
        errorCode = 'installCancelled';
        _set(UpdatePhase.notInstalled);
      default:
        _fail(s.status, s.message);
    }
  }

  Future<void> _report(String stage, {String? detail}) => _releases.report({
        'fromBuild': installed?.versionCode,
        'toBuild': release?.versionCode,
        'stage': stage,
        'detail': detail,
        'sdk': installed?.sdk,
        'phase': phase.name,
      });

  void _fail(String code, [String? detail]) {
    errorCode = code;
    errorDetail = detail;
    phase = UpdatePhase.failed;
    _log('failed: $code ${detail ?? ''}');
    unawaited(_report('failed:$code', detail: detail));
    notifyListeners();
  }

  void _set(UpdatePhase p) {
    phase = p;
    notifyListeners();
  }

  void _cleanupDownloads() {
    try {
      final dir = Directory(installed!.cacheDir);
      if (dir.existsSync()) {
        for (final f in dir.listSync().whereType<File>()) {
          f.deleteSync();
        }
      }
    } catch (_) {/* cache only */}
  }

  Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statusSub?.cancel();
    if (_started && supported) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
