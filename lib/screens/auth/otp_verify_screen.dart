import 'dart:async';

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

const int _kResendCooldownSeconds = 30;
const int _kOtpLength = 6;

class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({super.key});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _controller = TextEditingController();
  Timer? _cooldownTimer;
  int _secondsLeft = _kResendCooldownSeconds;
  String? _localErrorKey;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = _kResendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) t.cancel();
      });
    });
  }

  String _t(String key) => AppStrings.get(
      key, context.read<SettingsProvider>().locale.languageCode);

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    final code = _controller.text.trim();
    if (code.length != _kOtpLength) {
      setState(() => _localErrorKey = 'auth_otp_invalid_len');
      return;
    }
    setState(() => _localErrorKey = null);

    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyOtp(code);
    if (!mounted || !ok) return;

    // Hand the decision back to the gate rather than routing to /home here,
    // so there stays exactly one place that decides where a user lands.
    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0) return;
    setState(() => _localErrorKey = null);
    final auth = context.read<AuthProvider>();
    final ok = await auth.resendOtp();
    if (!mounted) return;
    if (ok) {
      _controller.clear();
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _C.card,
          content: Text(_t('auth_otp_sent'),
              style: const TextStyle(color: _C.green, fontSize: 13)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final identifier = auth.pendingIdentifier;
    final errorKey = _localErrorKey ?? auth.errorKey;

    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.surface,
        elevation: 0,
        foregroundColor: _C.text,
        title: Text(context.tr('auth_otp_title'),
            style: const TextStyle(
                color: _C.text, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                identifier == null
                    ? context.tr('auth_err_generic')
                    : context.trArgs('auth_otp_sent_to', {'id': identifier}),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _C.muted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 28),

              TextField(
                controller: _controller,
                autofocus: true,
                enabled: identifier != null,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: _kOtpLength,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_kOtpLength),
                ],
                style: const TextStyle(
                    color: _C.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 10),
                cursorColor: _C.cyan,
                onChanged: (_) {
                  if (_localErrorKey != null) {
                    setState(() => _localErrorKey = null);
                  }
                },
                onSubmitted: (_) => _verify(),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: _C.card,
                  hintText: context.tr('auth_otp_hint'),
                  hintStyle: const TextStyle(
                      color: _C.muted, fontSize: 15, letterSpacing: 1),
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _C.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _C.cyan, width: 1.5),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _C.border),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (errorKey != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          context.tr(errorKey),
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
                  onPressed:
                      (auth.busy || identifier == null) ? null : _verify,
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
                      : Text(context.tr('auth_verify_cta'),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 16),

              Center(
                child: (_secondsLeft > 0)
                    ? Text(
                        context.trArgs(
                            'auth_resend_in', {'s': '$_secondsLeft'}),
                        style:
                            const TextStyle(color: _C.muted, fontSize: 13),
                      )
                    : TextButton(
                        onPressed: (auth.busy || identifier == null)
                            ? null
                            : _resend,
                        child: Text(
                          context.tr('auth_resend'),
                          style: const TextStyle(
                              color: _C.cyan,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: auth.busy
                      ? null
                      : () => Navigator.of(context)
                          .pushNamedAndRemoveUntil('/login', (_) => false),
                  child: Text(
                    context.tr('auth_change_identifier'),
                    style: const TextStyle(color: _C.muted, fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
