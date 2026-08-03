import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/l10n.dart';
import '../../models/delivery.dart';
import '../../models/enums.dart';
import '../../services/api_exception.dart';
import '../../services/delivery_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/driver_task_card.dart';
import '../../widgets/ui.dart';

/// Runs a driver action end-to-end (reason prompt for reject/fail, proof photo for
/// complete, direct otherwise). Returns true if the task changed (caller reloads).
Future<bool> runDriverAction(BuildContext context, DeliveryService svc, DeliveryTask task, DriverAction action) async {
  switch (action) {
    case DriverAction.accept:
      return _run(context, () => svc.accept(task.id), context.t('Task accepted'));
    case DriverAction.start:
      return _run(context, () => svc.setStatus(task.id, DeliveryStatus.inTransit), context.t('Trip started'));
    case DriverAction.arrived:
      return _run(context, () => svc.setStatus(task.id, DeliveryStatus.arrived), context.t('Marked as arrived'));
    case DriverAction.reject:
      final reason = await _promptReason(context,
          title: context.t('Reject this task?'),
          label: context.t('Why are you rejecting this task?'),
          hint: context.t('e.g. Vehicle breakdown, address too far, unsafe area…'),
          confirm: context.t('Reject'));
      if (reason == null || !context.mounted) return false;
      return _run(context, () => svc.reject(task.id, reason), context.t('Task rejected'));
    case DriverAction.fail:
      final reason = await _promptReason(context,
          title: context.t('Fail this task?'),
          label: context.t("Why couldn't you complete it?"),
          hint: context.t('e.g. Customer unavailable, wrong address, access denied…'),
          confirm: context.t('Fail'));
      if (reason == null || !context.mounted) return false;
      return _run(context, () => svc.fail(task.id, reason), context.t('Task marked as failed'));
    case DriverAction.complete:
      final proof = await _promptProof(context, task);
      if (proof == null || !context.mounted) return false; // cancelled
      return _run(context, () => svc.complete(task.id, proofImagePath: proof.path), context.t('Task completed'));
  }
}

Future<bool> _run(BuildContext context, Future<void> Function() action, String okMsg) async {
  try {
    await action();
    if (context.mounted) showToast(context, okMsg);
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, ApiException.from(e).message, error: true);
    return false;
  }
}

/// Mandatory-reason dialog (reject/fail). Returns the trimmed reason, or null if cancelled/empty.
Future<String?> _promptReason(BuildContext context, {required String title, required String label, required String hint, required String confirm}) {
  final ctrl = TextEditingController();
  var showError = false;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(hintText: hint, counterText: '', errorText: showError ? ctx.t('A reason is required.') : null),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.t('Cancel'))),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isEmpty) {
                setState(() => showError = true);
                return;
              }
              Navigator.of(ctx).pop(v);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size(0, 44)),
            child: Text(confirm),
          ),
        ],
      ),
    ),
  );
}

/// Result of the proof sheet: a chosen photo path (nullable = complete without photo).
class _Proof {
  const _Proof(this.path);
  final String? path;
}

/// Complete sheet — optional proof photo (camera/gallery), like the web complete modal.
Future<_Proof?> _promptProof(BuildContext context, DeliveryTask task) {
  return showModalBottomSheet<_Proof>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(width: 42, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4))),
          ),
          Text(ctx.t(task.isPickup ? 'Complete pickup' : 'Complete delivery'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 4),
          Text(ctx.t('Attach a proof photo (optional), then confirm.'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ctx, ImageSource.camera), icon: const Icon(Icons.photo_camera_rounded, size: 20), label: Text(ctx.t('Camera')), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ctx, ImageSource.gallery), icon: const Icon(Icons.photo_library_rounded, size: 20), label: Text(ctx.t('Gallery')), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)))),
          ]),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(const _Proof(null)),
            icon: const Icon(Icons.check_rounded),
            label: Text(ctx.t('Complete without photo')),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 8),
          Center(child: TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.t('Cancel')))),
        ]),
      ),
    ),
  );
}

Future<void> _pick(BuildContext ctx, ImageSource source) async {
  try {
    final x = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1600);
    if (x != null && ctx.mounted) Navigator.of(ctx).pop(_Proof(x.path));
  } catch (_) {
    if (ctx.mounted) showToast(ctx, ctx.t('Could not open the camera.'), error: true);
  }
}
