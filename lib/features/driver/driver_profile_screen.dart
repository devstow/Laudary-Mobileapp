import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/delivery.dart';
import '../../services/api_exception.dart';
import '../../services/driver_profile_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/ui.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});
  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  late Future<DriverProfile> _future;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  final _vtype = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<DriverProfile> _load() async {
    final p = await context.read<DriverProfileService>().get();
    _name.text = p.fullName;
    _phone.text = p.phone ?? '';
    _plate.text = p.vehiclePlate ?? '';
    _vtype.text = p.vehicleType ?? '';
    return p;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _plate.dispose();
    _vtype.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await context.read<DriverProfileService>().update(DriverProfile(
            fullName: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            vehiclePlate: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
            vehicleType: _vtype.text.trim().isEmpty ? null : _vtype.text.trim(),
          ));
      if (mounted) showToast(context, context.t('Profile updated'));
    } catch (e) {
      if (mounted) showToast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onAvatarTap(DriverProfile p) async {
    final action = await showAvatarActionSheet(context, hasPhoto: p.photoUrl?.isNotEmpty ?? false);
    if (action == null || !mounted) return;
    if (action == AvatarAction.upload) {
      await _uploadPhoto();
    } else {
      await _removePhoto();
    }
  }

  Future<void> _uploadPhoto() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 800);
      if (x == null || !mounted) return;
      await context.read<DriverProfileService>().uploadPhoto(x.path);
      if (!mounted) return;
      setState(() => _future = _load());
      showToast(context, context.t('Photo updated'));
    } catch (e) {
      if (mounted) showToast(context, ApiException.from(e).message, error: true);
    }
  }

  Future<void> _removePhoto() async {
    try {
      await context.read<DriverProfileService>().removePhoto();
      if (!mounted) return;
      setState(() => _future = _load());
      showToast(context, context.t('Photo removed'));
    } catch (e) {
      if (mounted) showToast(context, ApiException.from(e).message, error: true);
    }
  }

  Future<void> _changePassword() =>
      showChangePasswordDialog(context, (c, n) => context.read<DriverProfileService>().changePassword(c, n));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Account'))),
      body: FutureBuilder<DriverProfile>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.all(20), child: SkeletonList(count: 3));
          }
          if (snap.hasError) return ErrorView(ApiException.from(snap.error!).message, onRetry: () => setState(() => _future = _load()));
          final p = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 116),
            children: [
              _headerCard(context, p),
              const SizedBox(height: 16),
              SoftCard(
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(11)),
                        child: const Icon(Icons.badge_rounded, color: AppColors.primary, size: 19),
                      ),
                      const SizedBox(width: 12),
                      Text(context.t('Contact & vehicle'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppColors.ink)),
                    ]),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _name,
                      maxLength: 200,
                      decoration: InputDecoration(labelText: context.t('Full name'), counterText: '', prefixIcon: const Icon(Icons.person_outline_rounded)),
                      validator: (v) => (v ?? '').trim().isEmpty ? context.t('Full name is required.') : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(controller: _phone, keyboardType: TextInputType.phone, maxLength: 50, decoration: InputDecoration(labelText: context.t('Phone'), counterText: '', prefixIcon: const Icon(Icons.phone_outlined))),
                    const SizedBox(height: 12),
                    TextFormField(controller: _plate, maxLength: 30, decoration: InputDecoration(labelText: context.t('Vehicle plate'), hintText: context.t('e.g. ABC 1234'), counterText: '', prefixIcon: const Icon(Icons.directions_car_outlined))),
                    const SizedBox(height: 12),
                    TextFormField(controller: _vtype, maxLength: 50, decoration: InputDecoration(labelText: context.t('Vehicle type'), hintText: context.t('e.g. Motorcycle, Van'), counterText: '', prefixIcon: const Icon(Icons.local_shipping_outlined))),
                    const SizedBox(height: 8),
                    Text(context.t('Contact your dispatcher to change your login email.'), style: TextStyle(color: AppColors.faint, fontSize: 12, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 14),
                    PrimaryButton(label: context.t('Save changes'), busy: _saving, onPressed: _save, icon: Icons.check_rounded),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              _actions(context, app),
            ],
          );
        },
      ),
    );
  }

  Widget _headerCard(BuildContext context, DriverProfile p) {
    final initials = p.fullName.trim().isEmpty
        ? 'D'
        : p.fullName.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    Color statusColor() {
      switch (p.status.value) {
        case 0:
          return AppColors.success;
        case 1:
          return AppColors.info;
        default:
          return AppColors.faint;
      }
    }

    final initialsCircle = Container(
      width: 62, height: 62,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: Text(initials, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 22)),
    );
    final url = p.photoUrl ?? '';
    final avatar = url.isEmpty
        ? initialsCircle
        : ClipOval(child: Image.network(url, width: 62, height: 62, fit: BoxFit.cover, errorBuilder: (_, _, _) => initialsCircle));

    // Claundry driver card: blue gradient, white-ringed avatar, glass status chip.
    return BrandHero(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(AppRadius.card + 2),
      child: Row(children: [
        GestureDetector(
          onTap: () => _onAvatarTap(p),
          child: Stack(children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.gold, width: 2.5)),
              child: avatar,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: AppColors.primary, width: 1.4)),
                child: const Icon(Icons.photo_camera_rounded, size: 13, color: AppColors.primary),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
            if ((p.email ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(p.email!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.chip)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor(), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(context.t(p.status.label), style: TextStyle(color: statusColor(), fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _actions(BuildContext context, AppState app) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: AppColors.line), boxShadow: AppShadows.soft),
      child: Column(children: [
        _tile(context, Icons.lock_outline, context.t('Change password'), onTap: _changePassword),
        const Divider(height: 1),
        _langTile(context, app),
        const Divider(height: 1),
        _appearanceTile(context, app),
        const Divider(height: 1),
        _tile(context, Icons.logout_rounded, context.t('Logout'), danger: true, onTap: () => context.read<AppState>().logout()),
      ]),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, {String? subtitle, VoidCallback? onTap, bool danger = false}) {
    final color = danger ? AppColors.danger : AppColors.ink;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: danger ? AppColors.danger : AppColors.primary),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: onTap == null ? null : Icon(Icons.chevron_right_rounded, color: AppColors.muted),
    );
  }

  Widget _langTile(BuildContext context, AppState app) {
    return ListTile(
      leading: const Icon(Icons.language_rounded, color: AppColors.primary),
      title: Text(context.t('Language'), style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'en', label: Text('EN')), ButtonSegment(value: 'ar', label: Text('ع'))],
        selected: {app.locale.code},
        showSelectedIcon: false,
        onSelectionChanged: (s) => context.read<AppState>().setLanguage(s.first),
      ),
    );
  }

  /// Light / Dark / Follow-system picker (full-width, below its label to fit three options).
  Widget _appearanceTile(BuildContext context, AppState app) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.brightness_medium_rounded, color: AppColors.primary),
          const SizedBox(width: 32),
          Text(context.t('Appearance'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_rounded, size: 16), label: Text(context.t('Light'))),
              ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_rounded, size: 16), label: Text(context.t('Dark'))),
              ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_rounded, size: 16), label: Text(context.t('System'))),
            ],
            selected: {app.theme.mode},
            showSelectedIcon: false,
            style: ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onSelectionChanged: (s) => context.read<AppState>().setThemeMode(s.first),
          ),
        ),
      ]),
    );
  }
}
