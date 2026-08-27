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

/// The countries offered at sign-up. `code` is written to
/// `profiles.country_code` and drives PRICING only (₹109 India vs $1.10
/// international). It has no bearing on identity: every user, in every country,
/// signs up by email OTP.
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

/// Generous, and a ceiling rather than a rule. It exists so that a pasted
/// document cannot become a name; it is not an opinion about how long a name
/// may be. Mirrors `profiles_first_name_len` / `profiles_last_name_len`.
const int _kNameMaxLength = 80;

/// Long enough for the longest international number written out with a country
/// code, spaces and brackets. Mirrors `profiles_phone_len`.
const int _kPhoneMaxLength = 32;

/// A loose shape check for the optional phone field, and it stays loose.
///
/// Digits, spaces, a plus, and the hyphens and brackets real people actually
/// type. There is deliberately no country-specific format check: this app
/// sells into eight countries that write their numbers eight different ways,
/// the value authenticates nothing, and a validator precise enough to be
/// useful would be precise enough to reject somebody's real number.
final RegExp _kPhoneShape = RegExp(r'^[0-9+\-() ]+$');

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  _Country _country = _kCountries.first;

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// `context.tr()` watches SettingsProvider, which is only legal inside
  /// build. Validators run outside it too, so they resolve strings by reading
  /// the locale instead. MaterialApp's ValueKey still rebuilds everything on a
  /// language change, so nothing goes stale.
  String _t(String key) => AppStrings.get(
      key, context.read<SettingsProvider>().locale.languageCode);

  String? _validate(String? raw) {
    final value = (raw ?? '').trim();
    final ok = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(value);
    return ok ? null : _t('auth_email_invalid');
  }

  /// Required, and that is the whole of it.
  ///
  /// There is NO character-set check here and none is coming. This app serves
  /// international customers, and real names carry apostrophes, hyphens,
  /// accents and non-Latin scripts; a name field that accepts only `[A-Za-z ]`
  /// is a field that tells real people their real name is invalid. Length is
  /// capped by the input formatter, exactly as the email field's 254 is, so
  /// there is no length message to write either.
  String? _validateName(String? raw) =>
      (raw ?? '').trim().isEmpty ? _t('auth_name_required') : null;

  /// Optional, and only sanity-checked.
  ///
  /// An empty field is always valid — this is contact data, not an identity,
  /// and nothing in this app is ever sent to it. What is typed only has to be
  /// plausibly a phone number at all: the right characters, and somewhere
  /// between a short national number and E.164's fifteen-digit maximum.
  String? _validatePhone(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (!_kPhoneShape.hasMatch(value)) return _t('auth_phone_invalid');
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digits < 6 || digits > 15) return _t('auth_phone_invalid');
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final value = _controller.text.trim();

    // The country selector is the sole source of `profiles.country_code` — it
    // is pricing data, and it has never been routing data.
    auth.countryCode = _country.code;

    // ── One name box, two columns ─────────────────────────────────────────
    // The screen collects a single "full name" and `profiles` has first_name
    // and last_name, so the split happens here, on the last run of whitespace.
    //
    // Deliberately naive, and deliberately biased the safe way. A single-token
    // name keeps the whole string as the first name and leaves last_name null
    // rather than inventing a surname for somebody who does not use one; a
    // multi-part given name ("Maria Del Carmen Ruiz") keeps everything but the
    // final token together. Nothing is rejected and nothing is discarded —
    // every character typed survives in one column or the other.
    //
    // One field rather than two is also what fits this screen: every other
    // input on it is a single full-width control in a vertical stack, and a
    // side-by-side First/Last row would be the only exception. It is the more
    // honest field as well, since a First/Last pair quietly asserts that
    // everyone's name has exactly two parts in that order.
    final name = _nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final cut = name.lastIndexOf(' ');

    // Staged, not sent with the OTP — see AuthProvider.stageSignupDetails for
    // why. Nothing is written until this account's OTP has been verified.
    auth.stageSignupDetails(
      firstName: cut < 0 ? name : name.substring(0, cut),
      lastName: cut < 0 ? null : name.substring(cut + 1),
      phone: _phoneController.text.trim(),
    );

    final sent = await auth.startSignup(identifier: value);

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

                _label(context.tr('auth_name_label')),
                const SizedBox(height: 8),
                _nameField(),
                const SizedBox(height: 20),

                _label(context.tr('auth_email_hint')),
                const SizedBox(height: 8),
                _identifierField(),
                const SizedBox(height: 20),

                _label(context.tr('auth_phone_label')),
                const SizedBox(height: 8),
                _phoneField(),
                const SizedBox(height: 6),
                // Says plainly what the number is and is not for. The promise
                // it makes is kept in code, not just in copy: nothing anywhere
                // in this app sends anything to profiles.phone.
                Text(
                  context.tr('auth_phone_note'),
                  style: const TextStyle(
                      color: _C.muted, fontSize: 11, height: 1.5),
                ),
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
                _setupStrip(auth),
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
              setState(() => _country = c);
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

  /// The decoration every text field on this screen wears. Lifted out when the
  /// name and phone fields were added, rather than copied twice more — the
  /// three are visually identical and there is no reason for them to be able
  /// to drift apart.
  InputDecoration _decoration(String hint) => InputDecoration(
        filled: true,
        fillColor: _C.card,
        hintText: hint,
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
      );

  Widget _identifierField() => TextFormField(
        controller: _controller,
        validator: _validate,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        keyboardType: TextInputType.emailAddress,
        inputFormatters: [LengthLimitingTextInputFormatter(254)],
        style: const TextStyle(color: _C.text, fontSize: 15),
        cursorColor: _C.cyan,
        decoration: _decoration(context.tr('auth_email_hint')),
      );

  /// No `inputFormatters` beyond the length cap, on purpose: a filtering
  /// formatter here would silently swallow characters out of somebody's own
  /// name as they typed it. See [_validateName].
  Widget _nameField() => TextFormField(
        controller: _nameController,
        validator: _validateName,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        keyboardType: TextInputType.name,
        textCapitalization: TextCapitalization.words,
        inputFormatters: [LengthLimitingTextInputFormatter(_kNameMaxLength)],
        style: const TextStyle(color: _C.text, fontSize: 15),
        cursorColor: _C.cyan,
        decoration: _decoration(context.tr('auth_name_hint')),
      );

  /// `TextInputType.phone` selects the keypad and nothing more. It is not a
  /// claim that this value will be dialled, messaged or verified — it will not
  /// be, in any language, on any rail.
  Widget _phoneField() => TextFormField(
        controller: _phoneController,
        validator: _validatePhone,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        keyboardType: TextInputType.phone,
        inputFormatters: [LengthLimitingTextInputFormatter(_kPhoneMaxLength)],
        style: const TextStyle(color: _C.text, fontSize: 15),
        cursorColor: _C.cyan,
        decoration: _decoration(context.tr('auth_phone_hint')),
      );

  /// Bottom-of-screen setup strip, shown ONLY when the backend config that
  /// shipped in this build is unusable.
  ///
  /// This is deliberately visible in release. The owner cannot read logcat from
  /// a release APK on a phone, so without it a packaging fault surfaces as an
  /// unactionable error banner. It reports presence and shape only — never any
  /// part of the URL or the anon key — so it discloses nothing a screenshot
  /// could leak. When the config is fine it renders nothing at all.
  Widget _setupStrip(AuthProvider auth) {
    if (auth.configOk) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(
        '${context.tr('auth_setup_diagnostic')}: ${auth.configDiagnostics}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: _C.muted, fontSize: 10, height: 1.45),
      ),
    );
  }

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
