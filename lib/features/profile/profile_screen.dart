import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/profile.dart';
import '../../services/api_exception.dart';
import '../../services/profile_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/ui.dart';
import 'profile_edit_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<CustomerProfile> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = context.read<ProfileService>().get();

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Future<void> _openEdit() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileEditScreen()));
    if (mounted) setState(_reload);
  }

  Future<void> _onAvatarTap(CustomerProfile? p) async {
    final action = await showAvatarActionSheet(context, hasPhoto: p?.photoUrl?.isNotEmpty ?? false);
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
      await context.read<ProfileService>().uploadPhoto(x.path);
      if (!mounted) return;
      setState(_reload);
      showToast(context, context.t('Photo updated'));
    } catch (e) {
      if (mounted) showToast(context, ApiException.from(e).message, error: true);
    }
  }

  Future<void> _removePhoto() async {
    try {
      await context.read<ProfileService>().removePhoto();
      if (!mounted) return;
      setState(_reload);
      showToast(context, context.t('Photo removed'));
    } catch (e) {
      if (mounted) showToast(context, ApiException.from(e).message, error: true);
    }
  }

  Future<void> _changePassword() =>
      showChangePasswordDialog(context, (c, n) => context.read<ProfileService>().changePassword(c, n));

  Widget _avatar(CustomerProfile? p, String name) {
    final url = p?.photoUrl ?? '';
    final fallback = _initialsCircle(name);
    final Widget inner = url.isEmpty
        ? fallback
        : ClipOval(
            child: Image.network(url, width: 66, height: 66, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
          );
    return GestureDetector(
      onTap: () => _onAvatarTap(p),
      child: Stack(children: [
        inner,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 1.4),
            ),
            child: const Icon(Icons.photo_camera_rounded, size: 13, color: AppColors.primary),
          ),
        ),
      ]),
    );
  }

  Widget _initialsCircle(String name) {
    return Container(
      width: 66,
      height: 66,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.4),
      ),
      child: Text(
        _initials(name),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;
    final lang = app.locale.code;
    final topInset = MediaQuery.of(context).padding.top;
    final name = user?.fullName ?? '';
    final email = user?.email ?? '';

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          BrandHero(
            padding: EdgeInsets.fromLTRB(20, topInset + 18, 20, 28),
            child: FutureBuilder<CustomerProfile>(
              future: _future,
              builder: (context, snap) {
                final p = snap.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _avatar(p, name),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            name.isEmpty ? context.t('Profile') : name,
                            style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(email, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5)),
                          ],
                        ]),
                      ),
                    ]),
                    if (p != null && ((p.phone?.isNotEmpty ?? false) || (p.city?.isNotEmpty ?? false))) ...[
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (p.phone?.isNotEmpty ?? false) _HeroChip(icon: Icons.phone_rounded, label: p.phone!),
                        if (p.city?.isNotEmpty ?? false) _HeroChip(icon: Icons.location_city_rounded, label: p.city!),
                      ]),
                    ],
                  ],
                );
              },
            ),
          ),
          Padding(
            // Bottom inset clears the translucent bottom nav bar (HomeShell uses extendBody: true), so the
            // last tile — Logout — is never hidden behind it. Matches the dashboard/payments tabs (100).
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 100),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionHeader(context.t('Default pickup address')),
              const SizedBox(height: 12),
              FutureBuilder<CustomerProfile>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SoftCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SkeletonBox(height: 14, width: 180),
                        SizedBox(height: 10),
                        SkeletonBox(height: 12, width: 120),
                      ]),
                    );
                  }
                  final address = snap.data?.address?.trim() ?? '';
                  if (snap.hasError || address.isEmpty) {
                    return SoftCard(
                      onTap: _openEdit,
                      child: Row(children: [
                        _IconBadge(icon: Icons.add_location_alt_outlined, color: AppColors.primary),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(context.t('Add your default pickup address'),
                                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14.5)),
                            const SizedBox(height: 3),
                            Text(context.t('Used to pre-fill new pickup requests'),
                                style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                          ]),
                        ),
                        Icon(Icons.chevron_right_rounded, color: AppColors.faint),
                      ]),
                    );
                  }
                  return SoftCard(
                    onTap: _openEdit,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _IconBadge(icon: Icons.location_on_rounded, color: AppColors.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(address, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14.5, height: 1.35)),
                          const SizedBox(height: 4),
                          Text(context.t('Used to pre-fill new pickup requests'),
                              style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        ]),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit_outlined, color: AppColors.faint, size: 18),
                    ]),
                  );
                },
              ),
              const SizedBox(height: 24),
              SectionHeader(context.t('Account')),
              const SizedBox(height: 12),
              _Group(children: [
                _Tile(
                  icon: Icons.edit_outlined,
                  title: context.t('Edit profile'),
                  onTap: _openEdit,
                ),
                const _TileDivider(),
                _Tile(
                  icon: Icons.lock_outline,
                  title: context.t('Change password'),
                  onTap: _changePassword,
                ),
                const _TileDivider(),
                _Tile(
                  icon: Icons.storefront_rounded,
                  title: context.t('Change laundry'),
                  subtitle: app.tenantName,
                  onTap: () => context.read<AppState>().changeLaundry(),
                ),
                const _TileDivider(),
                _LangTile(current: lang, onChange: (c) => context.read<AppState>().setLanguage(c)),
                const _TileDivider(),
                _AppearanceTile(current: app.theme.mode, onChange: (m) => context.read<AppState>().setThemeMode(m)),
              ]),
              const SizedBox(height: 16),
              _Group(children: [
                _Tile(
                  icon: Icons.logout_rounded,
                  title: context.t('Logout'),
                  danger: true,
                  onTap: () => context.read<AppState>().logout(),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ]),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _TileDivider extends StatelessWidget {
  const _TileDivider();
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsetsDirectional.only(start: 68), child: Divider(height: 1));
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, this.subtitle, this.onTap, this.danger = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.ink;
    final accent = danger ? AppColors.danger : AppColors.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.control)),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 15)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(color: AppColors.muted, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: danger ? AppColors.danger.withValues(alpha: 0.6) : AppColors.faint),
          ]),
        ),
      ),
    );
  }
}

class _LangTile extends StatelessWidget {
  const _LangTile({required this.current, required this.onChange});
  final String current;
  final ValueChanged<String> onChange;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.control)),
          child: const Icon(Icons.language_rounded, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(context.t('Language'), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15))),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'en', label: Text('EN')),
            ButtonSegment(value: 'ar', label: Text('ع')),
          ],
          selected: {current},
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onSelectionChanged: (s) => onChange(s.first),
        ),
      ]),
    );
  }
}

/// Light / Dark / Follow-system picker, styled to match the language tile.
class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile({required this.current, required this.onChange});
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChange;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.control)),
            child: const Icon(Icons.brightness_medium_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(context.t('Appearance'), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15))),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_rounded, size: 16), label: Text(context.t('Light'))),
              ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_rounded, size: 16), label: Text(context.t('Dark'))),
              ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_rounded, size: 16), label: Text(context.t('System'))),
            ],
            selected: {current},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelectionChanged: (s) => onChange(s.first),
          ),
        ),
      ]),
    );
  }
}
