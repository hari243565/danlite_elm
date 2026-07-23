import 'package:flutter/material.dart';

/// Danlite ELM — Brand Color System
/// Primary identity: Light blue background + Deep navy + Warm orange (flame)
class AppColors {
  AppColors._();

  // ── Brand Navy (from logo text) ────────────────────────────────────────────
  static const Color navyDeep     = Color(0xFF1A3461);
  static const Color navyMid      = Color(0xFF1E3A6E);
  static const Color navyLight    = Color(0xFF2E5299);

  // ── Brand Flame (from logo flame) ─────────────────────────────────────────
  static const Color flameOrange  = Color(0xFFE87722);
  static const Color flameGold    = Color(0xFFF5A623);
  static const Color flameAmber   = Color(0xFFFFC107);

  // ── Light Blue Backgrounds ─────────────────────────────────────────────────
  static const Color bgPrimary    = Color(0xFFE8F4FD); // Main app background
  static const Color bgSecondary  = Color(0xFFD0E9F8); // Cards / panels
  static const Color bgTertiary   = Color(0xFFBBDEF5); // Deeper sections
  static const Color bgSurface    = Color(0xFFF0F8FF); // White-ish surface
  static const Color bgCard       = Color(0xFFFFFFFF); // Pure white cards

  // ── Gauge Zone Colors ──────────────────────────────────────────────────────
  static const Color gaugeGreen   = Color(0xFF27AE60);
  static const Color gaugeYellow  = Color(0xFFF1C40F);
  static const Color gaugeOrange  = Color(0xFFE67E22);
  static const Color gaugeRed     = Color(0xFFE74C3C);
  static const Color gaugeTrack   = Color(0xFFCCE4F5);
  static const Color gaugeNeedle  = Color(0xFFE87722);

  // ── Text Colors ───────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1A2C4E);
  static const Color textSecondary = Color(0xFF4A6B8A);
  static const Color textHint      = Color(0xFF8AACC8);
  static const Color textOnDark    = Color(0xFFFFFFFF);
  static const Color textOnLight   = Color(0xFF1A2C4E);

  // ── Status Colors ─────────────────────────────────────────────────────────
  static const Color success  = Color(0xFF27AE60);
  static const Color warning  = Color(0xFFF39C12);
  static const Color error    = Color(0xFFE74C3C);
  static const Color info     = Color(0xFF2980B9);

  // ── Connection Status ─────────────────────────────────────────────────────
  static const Color connected     = Color(0xFF27AE60);
  static const Color disconnected  = Color(0xFFE74C3C);
  static const Color connecting    = Color(0xFFF39C12);

  // ── Dividers & Borders ────────────────────────────────────────────────────
  static const Color divider       = Color(0xFFB8D4E8);
  static const Color borderLight   = Color(0xFFCCE0F0);

  // ── Bottom Nav ────────────────────────────────────────────────────────────
  static const Color navSelected   = Color(0xFF1E3A6E);
  static const Color navUnselected = Color(0xFF8AACC8);
  static const Color navBackground = Color(0xFFFFFFFF);

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navyDeep, navyLight],
  );

  static const LinearGradient blueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgPrimary, bgTertiary],
  );

  static const LinearGradient flameGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [flameGold, flameOrange],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5F9FF), Color(0xFFE8F4FD)],
  );
}
