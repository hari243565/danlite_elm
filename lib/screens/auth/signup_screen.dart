import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../constants/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';

// Unified Telemetry Design System Palette — same values the dashboard,
// home and DTC screens declare locally.
class _C {
  static const Color bg = Color(0xFF07090E);
  static const Color surface = Color(0xFF0D1117);
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color text = Color(0xFFEEF2F8);
  static const Color muted = Color(0xFF607080);
  static const Color cyan = Color(0xFF00CAFF);
  static const Color green = Color(0xFF00E39C);
  static const Color red = Color(0xFFFF3D3D);
}

/// The countries offered at sign-up. `code` drives OTP routing: 'IN' takes the
/// SMS path, everything else takes email (Phase 6 finalises the providers).
class _Country {
  final String code;
  final String name;
  final String dial;
  const _Country(this.code, this.name, this.dial);
}

const List<_Country> _kCountries = [
  _Country('IN', 'India', '+91'),
  _Country('US', 'United States', '+1'),
  _Country('GB', 'United Kingdom', '+44'),
  _Country('AE', 'United Arab Emirates', '+971'),
  _Country('CA', 'Canada', '+1'),
  _Country('AU', 'Australia', '+61'),
  _Country('SG', 'Singapore', '+65'),
  _Country('DE', 'Germany', '+49'),
];

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  _Country _country = _kCountries.first;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _usesPhone => AuthProvider.usesPhoneOtp(_country.code);

  /// `context.tr()` watches SettingsProvider, which is only legal inside
  /// build. Validators run outside it too, so they resolve strings by reading
  /// the locale instead. MaterialApp's ValueKey still rebuilds everything on a
  /// language change, so nothing goes stale.
  String _t(String key) => AppStrings.get(
      key, context.read<SettingsProvider>().locale.languageCode);

  String? _validate(String? raw) {
    final value = (raw ?? '').trim();
    if (_usesPhone) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      // India is the only phone-OTP country today, and its subscriber numbers
      // are 10 digits starting 6-9.
      final ok = _country.code == 'IN'
          ? RegExp(r'^[6-9]\d{9}$').hasMatch(digits)
          : digits.length >= 6 && digits.length <= 14;
      return ok ? null : _t('auth_phone_invalid');
    }
    final ok = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(value);
    return ok ? null : _t('auth_email_invalid');
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final value = _controller.text.trim();

    final bool sent;
    if (_usesPhone) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      sent = await auth.startPhoneSignup('${_country.dial}$digits', _country.code);
    } else {
      auth.countryCode = _country.code;
      sent = await auth.startEmailSignup(value);
    }

    if (!mounted || !sent) return;
    Navigator.of(context).pushNamed('/otp');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.surface,
        elevation: 0,
        foregroundColor: _C.text,
        title: Text(context.tr('auth_signup_title'),
            style: const TextStyle(
                color: _C.text, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('auth_signup_subtitle'),
                  style: const TextStyle(
                      color: _C.muted, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 24),

                _label(context.tr('auth_country_label')),
                const SizedBox(height: 8),
                _countryField(),
                const SizedBox(height: 20),

                _label(_usesPhone
                    ? context.tr('auth_phone_hint')
                    : context.tr('auth_email_hint')),
                const SizedBox(height: 8),
                _identifierField(),
                const SizedBox(height: 20),

                if (auth.errorKey != null) ...[
                  _errorBanner(context.tr(auth.errorKey!)),
                  const SizedBox(height: 16),
                ],

                _primaryButton(
                  label: context.tr('auth_create_account_cta'),
                  busy: auth.busy,
                  onPressed: auth.busy ? null : _submit,
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        context.tr('auth_have_account'),
                        style: const TextStyle(color: _C.muted, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: auth.busy
                          ? null
                          : () => Navigator.of(context)
                              .pushReplacementNamed('/login'),
                      child: Text(
                        context.tr('auth_login_link'),
                        style: const TextStyle(
                            color: _C.cyan,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('auth_privacy_note'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _C.muted, fontSize: 11, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            color: _C.muted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1),
      );

  Widget _countryField() => Container(
        decoration: BoxDecoration(
          color: _C.card,
          border: Border.all(color: _C.border),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<_Country>(
            value: _country,
            isExpanded: true,
            dropdownColor: _C.card,
            iconEnabledColor: _C.muted,
            style: const TextStyle(color: _C.text, fontSize: 15),
            onChanged: (c) {
              if (c == null) return;
              setState(() {
                _country = c;
                // Email and phone are different inputs — never carry one over.
                _controller.clear();
              });
              context.read<AuthProvider>()
                ..countryCode = c.code
                ..clearError();
            },
            items: [
              for (final c in _kCountries)
                DropdownMenuItem<_Country>(
                  value: c,
                  child: Text(
                    // India is the one country name the UI localises; the rest
                    // stay in their English form, as elsewhere in the app.
                    c.code == 'IN' ? context.tr('auth_country_in') : c.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _identifierField() => TextFormField(
        controller: _controller,
        validator: _validate,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        keyboardType:
            _usesPhone ? TextInputType.phone : TextInputType.emailAddress,
        inputFormatters: _usesPhone
            ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)]
            : [LengthLimitingTextInputFormatter(254)],
        style: const TextStyle(color: _C.text, fontSize: 15),
        cursorColor: _C.cyan,
        decoration: InputDecoration(
          filled: true,
          fillColor: _C.card,
          prefixIcon: _usesPhone
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(start: 14, end: 8),
                  child: Text(
                    _country.dial,
                    style: const TextStyle(
                        color: _C.muted, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                )
              : null,
          prefixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          hintText: _usesPhone
              ? context.tr('auth_phone_hint')
              : context.tr('auth_email_hint'),
          hintStyle: const TextStyle(color: _C.muted, fontSize: 14),
          errorStyle: const TextStyle(color: _C.red, fontSize: 12),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _C.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _C.cyan, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _C.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _C.red, width: 1.5),
          ),
        ),
      );

  Widget _errorBanner(String message) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _C.red.withValues(alpha: 0.10),
          border: Border.all(color: _C.red.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: _C.red, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: _C.red, fontSize: 12.5, height: 1.4)),
            ),
          ],
        ),
      );

  Widget _primaryButton({
    required String label,
    required bool busy,
    required VoidCallback? onPressed,
  }) =>
      SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.green,
            disabledBackgroundColor: _C.border,
            foregroundColor: _C.bg,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: _C.bg),
                )
              : Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      );
}
