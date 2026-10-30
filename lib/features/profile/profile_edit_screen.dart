import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/profile.dart';
import '../../services/api_exception.dart';
import '../../services/profile_service.dart';
import '../../widgets/ui.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final p = await context.read<ProfileService>().get();
      _name.text = p.fullName;
      _phone.text = p.phone ?? '';
      _email.text = p.email ?? '';
      _address.text = p.address ?? '';
      _city.text = p.city ?? '';
    } catch (e) {
      _loadError = ApiException.from(e).message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<ProfileService>().update(CustomerProfile(
            fullName: _name.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            address: _address.text.trim(),
            city: _city.text.trim(),
          ));
      if (!mounted) return;
      showToast(context, context.t('Profile updated'));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showToast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Edit profile'))),
      body: _loading
          ? const LoadingView()
          : _loadError != null
              ? ErrorView(_loadError!, onRetry: _load)
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    child: Form(
                      key: _form,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SoftCard(
                          child: Column(children: [
                            _field(
                              _name,
                              context.t('Full name'),
                              Icons.person_outline_rounded,
                              maxLength: 200,
                              validator: (v) => (v == null || v.trim().isEmpty) ? context.t('Full name is required') : null,
                              textInputAction: TextInputAction.next,
                            ),
                            _field(
                              _phone,
                              context.t('Phone'),
                              Icons.phone_outlined,
                              keyboard: TextInputType.phone,
                              maxLength: 50,
                              textInputAction: TextInputAction.next,
                            ),
                            _field(
                              _email,
                              context.t('Email'),
                              Icons.mail_outline_rounded,
                              keyboard: TextInputType.emailAddress,
                              maxLength: 256,
                              readOnly: true,
                              helperText: context.t("This is your login email and can't be changed here."),
                            ),
                            _field(
                              _address,
                              context.t('Default pickup address'),
                              Icons.location_on_outlined,
                              maxLength: 500,
                              maxLines: 3,
                              helperText: context.t('Used to pre-fill new pickup requests'),
                            ),
                            _field(
                              _city,
                              context.t('City'),
                              Icons.location_city_rounded,
                              maxLength: 100,
                              textInputAction: TextInputAction.done,
                              last: true,
                            ),
                          ]),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _save,
                          icon: _busy
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                              : const Icon(Icons.check_rounded, size: 20),
                          label: Text(context.t('Save')),
                        ),
                      ]),
                    ),
                  ),
                ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    int? maxLength,
    int maxLines = 1,
    String? helperText,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
    bool last = false,
    bool readOnly = false,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 14),
        child: TextFormField(
          controller: c,
          keyboardType: keyboard,
          // phone / e-mail stay left-to-right inside the Arabic layout
          textDirection: keyboard == TextInputType.phone || keyboard == TextInputType.emailAddress ? TextDirection.ltr : null,
          maxLength: maxLength,
          maxLines: maxLines,
          textInputAction: textInputAction,
          validator: validator,
          readOnly: readOnly,
          decoration: InputDecoration(
            labelText: label,
            helperText: helperText,
            prefixIcon: Icon(icon),
            suffixIcon: readOnly ? const Icon(Icons.lock_outline_rounded, size: 18) : null,
            counterText: '',
            alignLabelWithHint: maxLines > 1,
            filled: readOnly,
          ),
        ),
      );
}
