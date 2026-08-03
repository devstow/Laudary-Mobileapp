import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/api_exception.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Shared change-password dialog for both customer & driver roles. [onSubmit] posts
/// { currentPassword, newPassword } to the role's endpoint. Shows a success/error toast.
Future<void> showChangePasswordDialog(
  BuildContext context,
  Future<void> Function(String current, String next) onSubmit,
) {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var busy = false;
  var obscure = true;

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> submit() async {
          if (!(formKey.currentState?.validate() ?? false)) return;
          setState(() => busy = true);
          try {
            await onSubmit(current.text, next.text);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              showToast(ctx, ctx.t('Password updated'));
            }
          } catch (e) {
            if (ctx.mounted) {
              setState(() => busy = false);
              showToast(ctx, ApiException.from(e).message, error: true);
            }
          }
        }

        InputDecoration deco(String label) => InputDecoration(
              labelText: label,
              counterText: '',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
            );

        return AlertDialog(
          title: Text(ctx.t('Change password')),
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: current,
                obscureText: obscure,
                maxLength: 100,
                decoration: deco(ctx.t('Current password')).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                    onPressed: () => setState(() => obscure = !obscure),
                  ),
                ),
                validator: (v) => (v ?? '').isEmpty ? ctx.t('Enter your current password.') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: next,
                obscureText: obscure,
                maxLength: 100,
                decoration: deco(ctx.t('New password')),
                validator: (v) => (v ?? '').length < 8 ? ctx.t('Password must be at least 8 characters.') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirm,
                obscureText: obscure,
                maxLength: 100,
                decoration: deco(ctx.t('Confirm password')),
                validator: (v) => v != next.text ? ctx.t('Passwords do not match.') : null,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.of(ctx).pop(), child: Text(ctx.t('Cancel'))),
            ElevatedButton(
              onPressed: busy ? null : submit,
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
              child: busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(ctx.t('Update password')),
            ),
          ],
        );
      },
    ),
  ).whenComplete(() {
    current.dispose();
    next.dispose();
    confirm.dispose();
  });
}

/// Shared avatar action sheet: pick a new photo from the gallery, or remove the
/// current one. [hasPhoto] toggles the remove option. Returns the chosen action.
enum AvatarAction { upload, remove }

Future<AvatarAction?> showAvatarActionSheet(BuildContext context, {required bool hasPhoto}) {
  return showModalBottomSheet<AvatarAction>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
          title: Text(ctx.t('Upload photo')),
          onTap: () => Navigator.of(ctx).pop(AvatarAction.upload),
        ),
        if (hasPhoto)
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            title: Text(ctx.t('Remove photo'), style: const TextStyle(color: AppColors.danger)),
            onTap: () => Navigator.of(ctx).pop(AvatarAction.remove),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}
