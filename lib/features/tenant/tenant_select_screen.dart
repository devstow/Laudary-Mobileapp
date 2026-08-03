import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/tenant.dart';
import '../../services/api_exception.dart';
import '../../services/tenant_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// DEVELOPMENT flow: pick your laundry (tenant) → stored → sent as X-Tenant-Id from then on.
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

  Future<void> _select(TenantDirectoryItem item) async {
    await context.read<AppState>().selectTenant(item);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Column(
        children: [
          BrandHero(
            padding: EdgeInsets.fromLTRB(20, topInset + 22, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: const Icon(Icons.local_laundry_service_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t('Find your laundry'),
                            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            context.t('Select a laundry to continue'),
                            style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _load(q: v)),
                  decoration: InputDecoration(
                    hintText: context.t('Search laundries'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    fillColor: Colors.white,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
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
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _LaundryTile(item: items[i], onTap: () => _select(items[i])),
                );
              },
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.control),
              image: hasLogo ? DecorationImage(image: NetworkImage(item.logoUrl!), fit: BoxFit.cover) : null,
            ),
            alignment: Alignment.center,
            child: hasLogo
                ? null
                : Text(initials, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                if (item.address != null && item.address!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 14, color: AppColors.faint),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(item.address!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 20),
          ),
        ],
      ),
    );
  }
}
