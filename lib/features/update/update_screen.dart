import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'update_controller.dart';

/// Root navigator, so a release found while the app is in use can be announced from anywhere.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Full-screen update page. Used as the start-up gate (before login / normal use) and pushed from the in-app
/// prompt. Mandatory updates have no Later and can't be closed with Back. Shows the real stage of the update as a
/// step list — Download → Verify → Install (Android's confirmation) → Restart — with the current and new versions,
/// a progress bar while downloading, and a clear message + retry for every failure. "Installed" is only ever said
/// after Android reports it (and confirmed again when the new version starts).
class UpdateScreen extends StatelessWidget {
  const UpdateScreen({super.key, this.asRoute = false});
  final bool asRoute;

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateController>();
    final r = u.release;
    final lang = Localizations.localeOf(context).languageCode;
    final notes = r?.notesFor(lang);
    final offline = u.offer == UpdateOffer.mandatoryOffline;
    final started = u.phase != UpdatePhase.idle;

    return PopScope(
      canPop: asRoute && !u.mandatory && !u.busy,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle, boxShadow: AppShadows.glow(AppColors.primary)),
                      child: Icon(_icon(u.phase), color: Colors.white, size: 40),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(context.t(_title(u)), textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 14),
                  if (r != null && !offline) _Versions(current: u.currentLabel, next: r.label()),
                  if (u.mandatory && !started) ...[
                    const SizedBox(height: 14),
                    Text(context.t(offline
                            ? 'This version is no longer supported. Connect to the internet to download the update.'
                            : 'This version is no longer supported. Please update to continue.'),
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkSoft, height: 1.4)),
                  ],
                  if (!started && notes != null && notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SoftCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.t("What's new"), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                        const SizedBox(height: 6),
                        Text(notes.trim(), style: TextStyle(color: AppColors.inkSoft, height: 1.4)),
                      ]),
                    ),
                  ],
                  if (!started && r != null && r.sizeBytes > 0 && !offline) ...[
                    const SizedBox(height: 10),
                    Text('${context.t('Download size')}: ${(r.sizeBytes / 1048576).toStringAsFixed(1)} MB',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ],
                  if (started) ...[const SizedBox(height: 18), _Steps(u)],
                  const SizedBox(height: 16),
                  _Progress(u),
                  const SizedBox(height: 18),
                  ..._actions(context, u, offline),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _icon(UpdatePhase p) => switch (p) {
        UpdatePhase.downloading => Icons.downloading_rounded,
        UpdatePhase.verifying => Icons.verified_user_outlined,
        UpdatePhase.installing || UpdatePhase.waitingConfirm => Icons.install_mobile_rounded,
        UpdatePhase.completing => Icons.restart_alt_rounded,
        UpdatePhase.failed || UpdatePhase.notInstalled || UpdatePhase.cancelled => Icons.error_outline_rounded,
        _ => Icons.system_update_rounded,
      };

  static String _title(UpdateController u) => switch (u.phase) {
        UpdatePhase.downloading => 'Downloading update',
        UpdatePhase.verifying => 'Verifying download',
        UpdatePhase.installing => 'Starting installation',
        UpdatePhase.waitingConfirm => 'Confirm the installation',
        UpdatePhase.completing => 'Completing update',
        UpdatePhase.notInstalled => 'Update not installed',
        UpdatePhase.cancelled => 'Download cancelled',
        UpdatePhase.failed => 'Update failed',
        UpdatePhase.needsPermission => 'Permission needed',
        UpdatePhase.idle => u.mandatory ? 'Update required' : 'A new version is available',
      };

  List<Widget> _actions(BuildContext context, UpdateController u, bool offline) {
    final app = context.read<AppState>();
    Widget later(String label) => TextButton(
          onPressed: () {
            u.later();
            if (asRoute) Navigator.of(context).maybePop();
          },
          child: Text(context.t(label)),
        );
    Widget systemInstaller() => TextButton.icon(
          onPressed: u.installWithSystemInstaller,
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(context.t('Use the Android installer')),
        );
    if (offline) return [PrimaryButton(label: context.t('Retry'), icon: Icons.refresh_rounded, onPressed: u.checkNow)];
    if (u.errorCode == 'signature') return [if (!u.mandatory) later('Later')];
    switch (u.phase) {
      case UpdatePhase.idle:
        return [
          PrimaryButton(label: context.t('Update Now'), icon: Icons.download_rounded, onPressed: () => u.updateNow(userId: app.user?.id)),
          if (!u.mandatory) ...[const SizedBox(height: 6), later('Later')],
        ];
      case UpdatePhase.needsPermission:
        return [
          PrimaryButton(label: context.t('Open settings'), icon: Icons.settings_rounded, onPressed: u.openInstallSettings),
          if (!u.mandatory) ...[const SizedBox(height: 6), later('Later')],
        ];
      case UpdatePhase.downloading:
        return [OutlinedButton(onPressed: u.cancelDownload, child: Text(context.t('Cancel')))];
      case UpdatePhase.verifying:
      case UpdatePhase.installing:
      case UpdatePhase.completing:
        return const [];
      case UpdatePhase.waitingConfirm:
        return [
          OutlinedButton.icon(
            onPressed: u.usingSystemInstaller ? u.installWithSystemInstaller : u.retry,
            icon: const Icon(Icons.install_mobile_rounded, size: 18),
            label: Text(context.t('Open the installer again')),
          ),
          if (!u.usingSystemInstaller) systemInstaller(),
        ];
      case UpdatePhase.notInstalled:
        return [
          PrimaryButton(label: context.t('Install update'), icon: Icons.install_mobile_rounded,
              onPressed: u.downloadReady ? u.installWithSystemInstaller : u.retry),
          if (!u.mandatory) ...[const SizedBox(height: 6), later('Continue with this version')],
        ];
      case UpdatePhase.cancelled:
      case UpdatePhase.failed:
        return [
          PrimaryButton(label: context.t('Try again'), icon: Icons.refresh_rounded, onPressed: u.retry),
          if (u.downloadReady && u.errorCode != 'signature') systemInstaller(),
          if (!u.mandatory) ...[const SizedBox(height: 6), later('Continue with this version')],
        ];
    }
  }
}

/// "1.0.3 (2012) → 1.0.4 (2013)".
class _Versions extends StatelessWidget {
  const _Versions({required this.current, required this.next});
  final String current;
  final String next;

  @override
  Widget build(BuildContext context) {
    Widget box(String label, String v, bool highlight) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: highlight ? AppColors.primarySoft : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: highlight ? AppColors.primary.withValues(alpha: .35) : AppColors.line),
            ),
            child: Column(children: [
              Text(context.t(label), style: TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 2),
              Text(ltr(v), style: TextStyle(fontWeight: FontWeight.w800, color: highlight ? AppColors.primary : AppColors.ink)),
            ]),
          ),
        );
    return Row(children: [
      box('Installed', current, false),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Directionality.of(context) == TextDirection.rtl ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded, color: AppColors.faint)),
      box('New version', next, true),
    ]);
  }
}

/// Download → Verify → Install → Restart, each done / current / pending.
class _Steps extends StatelessWidget {
  const _Steps(this.u);
  final UpdateController u;

  int get _current => switch (u.phase) {
        UpdatePhase.downloading || UpdatePhase.cancelled || UpdatePhase.needsPermission => 0,
        UpdatePhase.verifying => 1,
        UpdatePhase.installing || UpdatePhase.waitingConfirm || UpdatePhase.notInstalled => 2,
        UpdatePhase.completing => 3,
        UpdatePhase.failed => u.downloadReady ? 2 : 0,
        UpdatePhase.idle => -1,
      };

  @override
  Widget build(BuildContext context) {
    final failed = u.phase == UpdatePhase.failed || u.phase == UpdatePhase.notInstalled || u.phase == UpdatePhase.cancelled;
    const labels = ['Download', 'Verify', 'Install', 'Restart'];
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              _dot(i < _current ? 'done' : i == _current ? (failed ? 'error' : 'active') : 'todo'),
              const SizedBox(width: 12),
              Expanded(
                child: Text(context.t(labels[i]),
                    style: TextStyle(fontWeight: i == _current ? FontWeight.w800 : FontWeight.w600, color: i <= _current ? AppColors.ink : AppColors.faint)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _dot(String state) {
    final (Color c, Widget child) = switch (state) {
      'done' => (AppColors.success, const Icon(Icons.check_rounded, size: 15, color: Colors.white)),
      'active' => (AppColors.primary, const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
      'error' => (AppColors.danger, const Icon(Icons.close_rounded, size: 15, color: Colors.white)),
      _ => (AppColors.line, const SizedBox.shrink()),
    };
    return Container(width: 24, height: 24, alignment: Alignment.center, decoration: BoxDecoration(color: c, shape: BoxShape.circle), child: child);
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.u);
  final UpdateController u;

  @override
  Widget build(BuildContext context) {
    String? text;
    Color color = AppColors.inkSoft;
    var bar = false;
    double? value;
    switch (u.phase) {
      case UpdatePhase.idle:
        if (u.lastAttemptNotInstalled) text = context.t('The previous update was not installed. You can try again.');
      case UpdatePhase.needsPermission:
        text = context.t('To update, allow Smart Wash to install apps: tap Open settings, turn on "Allow from this source", then come back. Android will still ask you to confirm the update.');
      case UpdatePhase.downloading:
        bar = true;
        value = u.progress;
        final mb = (u.received / 1048576).toStringAsFixed(1);
        final total = (u.release?.sizeBytes ?? 0) / 1048576;
        text = u.progress == null
            ? '${context.t('Downloading…')} $mb MB'
            : '${(u.progress! * 100).round()}%  ·  $mb / ${total.toStringAsFixed(1)} MB';
      case UpdatePhase.verifying:
        bar = true;
        text = context.t('Checking that the file is complete, genuine and made for this app…');
      case UpdatePhase.installing:
        bar = true;
        text = context.t('Opening the Android installer…');
      case UpdatePhase.waitingConfirm:
        text = context.t('Android is asking you to confirm. Tap "Update" (or "Install") in the Android window. Your data and sign-in are kept.');
      case UpdatePhase.completing:
        bar = true;
        text = context.t('Android is installing the new version and will close Smart Wash. If the installer shows "Open", tap it — otherwise open Smart Wash again.');
      case UpdatePhase.notInstalled:
        color = AppColors.warning;
        text = context.t('The installation was cancelled or did not finish. Your current version and data are unchanged. The verified update is still on the phone — no new download needed.');
      case UpdatePhase.cancelled:
        color = AppColors.warning;
        text = context.t('Download cancelled. Nothing was changed.');
      case UpdatePhase.failed:
        color = AppColors.danger;
        text = _failure(context, u.errorCode, u.errorDetail);
    }
    if (text == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (bar) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: value, minHeight: 10, backgroundColor: AppColors.primarySoft),
        ),
        const SizedBox(height: 10),
      ],
      Text(text, textAlign: TextAlign.center, style: TextStyle(color: color, fontWeight: FontWeight.w600, height: 1.4)),
    ]);
  }

  static String _failure(BuildContext context, String? code, String? detail) {
    final msg = switch (code) {
      'network' => 'The download was interrupted. Check your internet connection and try again.',
      'server' => 'The update server did not return the file. Try again in a few minutes.',
      'storage' => 'Not enough free storage on the phone to download the update. Free up some space and try again.',
      'checksum' || 'missing' => 'The downloaded file is incomplete or damaged. It was deleted — try again.',
      'invalid' => 'The downloaded file is not a valid app package. It was deleted — try again.',
      'package' => 'The download is not a Smart Wash update. It was rejected.',
      'version' => 'The download is not newer than the installed app. It was rejected.',
      'signature' || 'conflict' => 'This copy of Smart Wash was signed differently from the update, so Android cannot install it over it. Contact support.',
      'incompatible' => 'This update is not compatible with this phone.',
      'blocked' => 'Android blocked the installation (device policy or Play Protect).',
      'metadata' => 'The release information is incomplete, so the update cannot be verified. Try again later.',
      _ => 'The update could not be installed. Smart Wash was not changed — try again.',
    };
    final t = context.t(msg);
    return code == 'storage' && detail != null ? '$t (${context.t('needed')}: $detail)' : t;
  }
}

/// Watches for a release found while the app is in use and announces it ONCE per build with a dialog:
/// Update Now opens [UpdateScreen]; Later (optional only) dismisses it until the next launch.
class UpdatePromptHost extends StatefulWidget {
  const UpdatePromptHost({super.key, required this.child});
  final Widget child;
  @override
  State<UpdatePromptHost> createState() => _UpdatePromptHostState();
}

class _UpdatePromptHostState extends State<UpdatePromptHost> {
  UpdateController? _u;
  bool _showing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final u = context.read<UpdateController>();
    if (!identical(u, _u)) {
      _u?.removeListener(_onChange);
      _u = u..addListener(_onChange);
    }
  }

  @override
  void dispose() {
    _u?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final u = _u!;
    final r = u.prompt;
    if (r == null || _showing || u.gate) return;
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    u.promptShown();
    _showing = true;
    final app = context.read<AppState>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = rootNavigatorKey.currentContext!;
      final lang = Localizations.localeOf(ctx).languageCode;
      final notes = r.notesFor(lang);
      final go = await showDialog<bool>(
        context: ctx,
        barrierDismissible: !u.mandatory,
        builder: (d) => PopScope(
          canPop: !u.mandatory,
          child: AlertDialog(
            icon: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 36),
            title: Text(d.t(u.mandatory ? 'Update required' : 'A new version is available')),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d.t('Version')} ${r.label()}', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (notes != null && notes.trim().isNotEmpty) ...[const SizedBox(height: 10), Text(notes.trim())],
            ]),
            actions: [
              if (!u.mandatory) TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(d.t('Later'))),
              FilledButton(onPressed: () => Navigator.of(d).pop(true), child: Text(d.t('Update Now'))),
            ],
          ),
        ),
      );
      _showing = false;
      if (go == true) {
        rootNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const UpdateScreen(asRoute: true)));
        await u.updateNow(userId: app.user?.id);
      } else {
        u.later();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
