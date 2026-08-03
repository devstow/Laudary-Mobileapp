import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/api_exception.dart';
import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

enum _Step { email, otp, password }

/// OTP-based password reset: enter email → receive a code → verify → set a new password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});
  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) _email.text = widget.initialEmail!;
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _tenant => context.read<AppState>().tenantIdentifier ?? '';

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _fieldError = context.t('Enter a valid email.'));
      return;
    }
    await _run(() async {
      await context.read<AuthService>().requestPasswordOtp(tenantIdentifier: _tenant, email: email);
      if (!mounted) return;
      setState(() => _step = _Step.otp);
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 4) {
      setState(() => _fieldError = context.t('Enter the code from your email.'));
      return;
    }
    await _run(() async {
      await context.read<AuthService>().verifyOtp(tenantIdentifier: _tenant, email: _email.text.trim(), code: code);
      if (!mounted) return;
      setState(() => _step = _Step.password);
    });
  }

  Future<void> _resend() async {
    await _run(() async {
      await context.read<AuthService>().requestPasswordOtp(tenantIdentifier: _tenant, email: _email.text.trim());
      if (mounted) showToast(context, context.t('A new code has been sent.'));
    });
  }

  Future<void> _reset() async {
    final pw = _password.text;
    if (pw.length < 8) {
      setState(() => _fieldError = context.t('Password must be at least 8 characters.'));
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _fieldError = context.t('Passwords do not match.'));
      return;
    }
    await _run(() async {
      await context.read<AuthService>().resetPasswordWithOtp(
            tenantIdentifier: _tenant,
            email: _email.text.trim(),
            code: _code.text.trim(),
            newPassword: pw,
          );
      if (!mounted) return;
      showToast(context, context.t('Password changed. Please sign in.'));
      Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Column(
        children: [
          BrandHero(
            padding: EdgeInsets.fromLTRB(8, topInset + 8, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  Text(context.t('Reset password'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 6),
                  child: Text(_subtitle(context),
                      style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.35)),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              child: SoftCard(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _stepper(context),
                  const SizedBox(height: 18),
                  ..._stepFields(context),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _banner(_error!),
                  ],
                  const SizedBox(height: 22),
                  _primaryButton(context),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(BuildContext context) => switch (_step) {
        _Step.email => context.t("Enter your account email and we'll send you a verification code."),
        _Step.otp => context.t('Enter the 6-digit code we sent to your email.'),
        _Step.password => context.t('Choose a new password for your account.'),
      };

  Widget _stepper(BuildContext context) {
    Widget dot(int i, String label) {
      final active = _step.index == i;
      final done = _step.index > i;
      final c = done || active ? AppColors.primary : AppColors.line;
      return Expanded(
        child: Column(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            child: Icon(done ? Icons.check_rounded : Icons.circle, size: done ? 16 : 8, color: done ? Colors.white : (active ? Colors.white : AppColors.faint)),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: active ? FontWeight.w800 : FontWeight.w500, color: (done || active) ? AppColors.ink : AppColors.faint)),
        ]),
      );
    }

    Widget bar(int i) => Container(width: 22, height: 2, margin: const EdgeInsets.only(bottom: 18), color: _step.index > i ? AppColors.primary : AppColors.line);

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      dot(0, context.t('Email')),
      bar(0),
      dot(1, context.t('Verify')),
      bar(1),
      dot(2, context.t('New password')),
    ]);
  }

  List<Widget> _stepFields(BuildContext context) {
    switch (_step) {
      case _Step.email:
        return [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: context.t('Email'),
              prefixIcon: const Icon(Icons.mail_outline_rounded),
              errorText: _fieldError,
            ),
          ),
        ];
      case _Step.otp:
        return [
          Text('${context.t('Code sent to')} ${_email.text.trim()}', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            enabled: !_busy,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 8),
            decoration: InputDecoration(hintText: '••••••', counterText: '', errorText: _fieldError),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _busy ? null : _resend,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.t('Resend code')),
            ),
          ),
        ];
      case _Step.password:
        return [
          TextField(
            controller: _password,
            obscureText: _obscure,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: context.t('New password'),
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirm,
            obscureText: _obscure,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: context.t('Confirm password'),
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              errorText: _fieldError,
            ),
          ),
        ];
    }
  }

  Widget _primaryButton(BuildContext context) {
    final (label, action) = switch (_step) {
      _Step.email => (context.t('Send code'), _sendCode),
      _Step.otp => (context.t('Verify'), _verify),
      _Step.password => (context.t('Reset password'), _reset),
    };
    return ElevatedButton(
      onPressed: _busy ? null : action,
      child: _busy
          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
          : Text(label),
    );
  }

  Widget _banner(String msg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600))),
        ]),
      );
}
