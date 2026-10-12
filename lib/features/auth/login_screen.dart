import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/api_exception.dart';
import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../widgets/auth_layout.dart';
import '../../widgets/ui.dart';
import '../tenant/tenant_select_screen.dart';
import 'choose_business_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final res = await context.read<AuthService>().login(_email.text.trim(), _password.text);
      if (!mounted) return;
      await context.read<AppState>().onAuthenticated(res);
    } on TenantSelectionRequired catch (choice) {
      // Same credentials in several businesses → let the user pick which one to sign in to.
      if (!mounted) return;
      setState(() => _busy = false);
      final outcome = await Navigator.of(context).push<ChooseBusinessOutcome>(
        MaterialPageRoute(builder: (_) => ChooseBusinessScreen(choice: choice)),
      );
      if (!mounted || outcome == null) return;
      if (outcome.result != null) {
        await context.read<AppState>().onAuthenticated(outcome.result!);
      } else if (outcome.error != null) {
        setState(() => _error = outcome.error);
      }
    } catch (e) {
      setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: context.t('Welcome back'),
      subtitle: context.t('Sign in to continue'),
      footer: AuthSwitchRow(
        question: context.t("Don't have an account?"),
        action: context.t('Create account'),
        onTap: _busy ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TenantSelectScreen())),
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: context.t('Email'), prefixIcon: const Icon(Icons.mail_outline_rounded)),
              validator: (v) => (v == null || !v.contains('@')) ? context.t('Email') : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              onFieldSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: context.t('Password'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? context.t('Password') : null,
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ForgotPasswordScreen(
                            initialEmail: _email.text.trim().isEmpty ? null : _email.text.trim(),
                          ),
                        )),
                child: Text(context.t('Forgot password?')),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              ErrorBanner(_error!),
            ],
            const SizedBox(height: 18),
            PrimaryButton(label: context.t('Sign in'), busy: _busy, onPressed: _submit, icon: Icons.login_rounded),
          ],
        ),
      ),
    );
  }
}
