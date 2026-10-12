import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/tenant.dart';
import '../../services/api_exception.dart';
import '../../services/tenant_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import '../auth/register_screen.dart';

/// Registration step 1: choose the laundry you're joining from the public directory, then
/// continue to the sign-up form for it. (Login never needs this — the tenant comes from the JWT.)
class TenantSelectScreen extends StatefulWidget {
  const TenantSelectScreen({super.key});
  @override
  State<TenantSelectScreen> createState() => _TenantSelectScreenState();
}

class _TenantSelectScreenState extends State<TenantSelectScreen> {
  late Future<List<TenantDirectoryItem>> _future;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load({String? q}) {
    _future = context.read<TenantService>().list(query: q);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _select(TenantDirectoryItem item) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => RegisterScreen(tenant: item)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                SquareIconButton(
                  icon: Directionality.of(context) == TextDirection.rtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(13), boxShadow: AppShadows.soft),
                  child: Image.asset('assets/brand/smartwash-mark.png', fit: BoxFit.contain),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('Choose your laundry'),
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.6, color: AppColors.ink)),
                const SizedBox(height: 4),
                Text(context.t('Select the laundry you want to join'),
                    style: TextStyle(fontSize: 14, color: AppColors.muted)),
                const SizedBox(height: 18),
                DecoratedBox(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.control), boxShadow: AppShadows.soft),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _load(q: v)),
                    decoration: InputDecoration(
                      hintText: context.t('Search laundries'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      fillColor: AppColors.surface,
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: FutureBuilder<List<TenantDirectoryItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 0), child: SkeletonList());
                  }
                  if (snap.hasError) {
                    return ErrorView(
                      ApiException.from(snap.error!).message,
                      onRetry: () => setState(() => _load(q: _searchCtrl.text)),
                    );
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return EmptyView(context.t('No laundries found'), icon: Icons.storefront_rounded);
                  }
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.paddingOf(context).bottom),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _LaundryTile(item: items[i], onTap: () => _select(items[i])),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LaundryTile extends StatelessWidget {
  const _LaundryTile({required this.item, required this.onTap});
  final TenantDirectoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasLogo = item.logoUrl != null && item.logoUrl!.isNotEmpty;
    final initials = item.name.isNotEmpty ? item.name.trim().substring(0, 1).toUpperCase() : '?';
    return SoftCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: hasLogo ? null : AppColors.brandGradient,
              color: hasLogo ? AppColors.primarySoft : null,
              borderRadius: BorderRadius.circular(AppRadius.tile),
              image: hasLogo ? DecorationImage(image: NetworkImage(item.logoUrl!), fit: BoxFit.cover) : null,
            ),
            alignment: Alignment.center,
            child: hasLogo
                ? null
                : Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.ink)),
                if (item.address != null && item.address!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(item.address!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(11)),
            child: Icon(Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                color: AppColors.goldDark, size: 22),
          ),
        ],
      ),
    );
  }
}
