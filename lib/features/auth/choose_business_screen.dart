import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../l10n/l10n.dart';
import '../../models/auth.dart';
import '../../models/tenant.dart';
import '../../services/api_exception.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_layout.dart';
import '../../widgets/ui.dart';

/// What [ChooseBusinessScreen] pops with: the signed-in [result], or an [error] to show back on
/// the login screen (e.g. the 5-minute selection token expired).
class ChooseBusinessOutcome {
  const ChooseBusinessOutcome.success(AuthResult this.result) : error = null;
  const ChooseBusinessOutcome.failed(String this.error) : result = null;
  final AuthResult? result;
  final String? error;
}

/// Shown after a 409 TenantSelectionRequired login: the same email + password belong to accounts
/// in several businesses, so the user picks which one to sign in to (POST /login/select-tenant).
class ChooseBusinessScreen extends StatefulWidget {
  const ChooseBusinessScreen({super.key, required this.choice});
  final TenantSelectionRequired choice;

  @override
  State<ChooseBusinessScreen> createState() => _ChooseBusinessScreenState();
}

class _ChooseBusinessScreenState extends State<ChooseBusinessScreen> {
  String? _busyId;
  String? _error;

  Future<void> _select(TenantChoice t) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = t.tenantId;
      _error = null;
    });
    try {
      final res = await context.read<AuthService>().selectTenant(
            selectionToken: widget.choice.selectionToken,
            tenantId: t.tenantId,
          );
      if (!mounted) return;
      Navigator.of(context).pop(ChooseBusinessOutcome.success(res));
    } catch (e) {
      if (!mounted) return;
      final ex = ApiException.from(e);
      if (ex.statusCode == 401 || ex.title == 'TenantSelectionInvalid') {
        // Selection token expired (5 min) / invalid → back to the login form with the message.
        final msg = (ex.message.isEmpty || ex.message == ex.title)
            ? context.t('Your sign-in session expired. Please sign in again.')
            : ex.message;
        Navigator.of(context).pop(ChooseBusinessOutcome.failed(msg));
        return;
      }
      setState(() {
        _busyId = null;
        _error = ex.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenants = widget.choice.tenants;
    return AuthLayout(
      showBack: true,
      backEnabled: _busyId == null,
      headerIcon: Icons.storefront_rounded,
      title: context.t('Choose your business'),
      subtitle: context.t('Your account belongs to more than one business. Choose which one to sign in to.'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 14)],
        for (final t in tenants) ...[
          _BusinessTile(
            choice: t,
            busy: _busyId == t.tenantId,
            enabled: _busyId == null,
            onTap: () => _select(t),
          ),
          const SizedBox(height: 12),
        ],
      ]),
    );
  }
}

class _BusinessTile extends StatelessWidget {
  const _BusinessTile({required this.choice, required this.busy, required this.enabled, required this.onTap});
  final TenantChoice choice;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final logo = AppConfig.mediaUrl(choice.logoUrl);
    final name = choice.name.trim();
    final initials = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
    final fallback =
        Text(initials, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 20));
    return SoftCard(
      padding: const EdgeInsets.all(14),
      onTap: enabled ? onTap : null,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.control)),
            alignment: Alignment.center,
            child: logo == null
                ? fallback
                : Image.network(logo, fit: BoxFit.cover, width: 52, height: 52, errorBuilder: (_, _, _) => fallback),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
          const SizedBox(width: 8),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
            child: busy
                ? const Padding(padding: EdgeInsets.all(7), child: CircularProgressIndicator(strokeWidth: 2.2))
                : const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 20),
          ),
        ],
      ),
    );
  }
}
