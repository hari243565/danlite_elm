import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _fade  = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.easeIn));
    _scale = Tween<double>(begin: 0.75, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack)));
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 2400), _navigate);
  }

  void _navigate() {
    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.navyGradient),
        child: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo icon
                    Container(
                      width: 110, height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.12),
                        border: Border.all(color: AppColors.flameOrange, width: 2.5),
                      ),
                      child: ClipOval(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('OBD Danlite',
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900,
                          color: Colors.white, letterSpacing: 1.2,
                          shadows: [Shadow(color: AppColors.flameOrange, blurRadius: 18)])),
                    const SizedBox(height: 10),
                    const Text('OBD2 Vehicle Diagnostics',
                      style: TextStyle(fontSize: 14, color: Colors.white60, letterSpacing: 1.5)),
                    const SizedBox(height: 48),
                    const SizedBox(
                      width: 36, height: 36,
                      child: CircularProgressIndicator(
                        color: AppColors.flameOrange, strokeWidth: 2.5)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
