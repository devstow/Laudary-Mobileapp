import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/api_exception.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_layout.dart';
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
      await context.read<AuthService>().requestPasswordOtp(email: email);
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
      await context.read<AuthService>().verifyOtp(email: _email.text.trim(), code: code);
      if (!mounted) return;
      setState(() => _step = _Step.password);
    });
  }

  Future<void> _resend() async {
    await _run(() async {
      await context.read<AuthService>().requestPasswordOtp(email: _email.text.trim());
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
    return AuthLayout(
      showBack: true,
      headerIcon: switch (_step) {
        _Step.email => Icons.lock_reset_rounded,
        _Step.otp => Icons.mark_email_read_rounded,
        _Step.password => Icons.password_rounded,
      },
      title: context.t('Reset password'),
      subtitle: _subtitle(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _stepper(context),
        const SizedBox(height: 22),
        ..._stepFields(context),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _banner(_error!),
        ],
        const SizedBox(height: 22),
        _primaryButton(context),
      ]),
    );
  }

  String _subtitle(BuildContext context) => switch (_step) {
        _Step.email => context.t("Enter your account email and we'll send you a verification code."),
        _Step.otp => context.t('Enter the 6-digit code we sent to your email.'),
        _Step.password => context.t('Choose a new password for your account.'),
      };

  Widget _stepper(BuildContext context) {
    // Three segmented progress capsules with labels — compact, Claundry-style.
    Widget seg(int i, String label) {
      final active = _step.index == i;
      final done = _step.index > i;
      return Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 6,
            decoration: BoxDecoration(
              gradient: (done || active) ? AppColors.brandGradient : null,
              color: (done || active) ? null : AppColors.line,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 7),
          Row(children: [
            if (done) ...[const Icon(Icons.check_circle_rounded, size: 13, color: AppColors.primary), const SizedBox(width: 4)],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: (done || active) ? AppColors.ink : AppColors.faint)),
            ),
          ]),
        ]),
      );
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      seg(0, context.t('Email')),
      const SizedBox(width: 8),
      seg(1, context.t('Verify')),
      const SizedBox(width: 8),
      seg(2, context.t('New password')),
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
    return PrimaryButton(label: label, busy: _busy, onPressed: action);
  }

  Widget _banner(String msg) => ErrorBanner(msg);
}
