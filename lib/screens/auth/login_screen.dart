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
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color text = Color(0xFFEEF2F8);
  static const Color muted = Color(0xFF607080);
  static const Color cyan = Color(0xFF00CAFF);
  static const Color green = Color(0xFF00E39C);
  static const Color red = Color(0xFFFF3D3D);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// See the note in signup_screen.dart: `context.tr()` watches and is only
  /// legal inside build, so validators read the locale instead.
  String _t(String key) => AppStrings.get(
      key, context.read<SettingsProvider>().locale.languageCode);

  String? _validate(String? raw) {
    final value = (raw ?? '').trim();
    return RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(value)
        ? null
        : _t('auth_email_invalid');
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final sent = await auth.login(identifier: _controller.text.trim());

    if (!mounted || !sent) return;
    Navigator.of(context).pushNamed('/otp');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _C.card,
                      border: Border.all(color: _C.border),
                    ),
                    child: ClipOval(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Image.asset('assets/images/logo.png',
                            fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  context.tr('auth_login_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _C.text, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('auth_login_subtitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _C.muted, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 28),

                Text(
                  context.tr('auth_email_hint').toUpperCase(),
                  style: const TextStyle(
                      color: _C.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _controller,
                  validator: _validate,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  keyboardType: TextInputType.emailAddress,
                  inputFormatters: [LengthLimitingTextInputFormatter(254)],
                  style: const TextStyle(color: _C.text, fontSize: 15),
                  cursorColor: _C.cyan,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _C.card,
                    hintText: context.tr('auth_email_hint'),
                    hintStyle: const TextStyle(color: _C.muted, fontSize: 14),
                    errorStyle: const TextStyle(color: _C.red, fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 16),
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
                ),
                const SizedBox(height: 20),

                if (auth.errorKey != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
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
                          child: Text(
                            context.tr(auth.errorKey!),
                            style: const TextStyle(
                                color: _C.red, fontSize: 12.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: auth.busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.green,
                      disabledBackgroundColor: _C.border,
                      foregroundColor: _C.bg,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: auth.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: _C.bg),
                          )
                        : Text(context.tr('auth_login_cta'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        context.tr('auth_no_account'),
                        style: const TextStyle(color: _C.muted, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: auth.busy
                          ? null
                          : () => Navigator.of(context).pushNamed('/signup'),
                      child: Text(
                        context.tr('auth_signup_link'),
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

  /// Bottom-of-screen setup strip, shown ONLY when the backend config that
  /// shipped in this build is unusable. Mirrors the sign-up screen.
  ///
  /// Deliberately visible in release: the owner cannot read logcat from a
  /// release APK on a phone, so this turns an otherwise unreadable packaging
  /// fault into a screenshot he can act on. It reports presence and shape only
  /// — never any part of the URL or the anon key.
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
}
