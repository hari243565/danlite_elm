import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.bgPrimary,
        colorScheme: const ColorScheme.light(
          primary: AppColors.navyMid,
          onPrimary: Colors.white,
          secondary: AppColors.flameOrange,
          onSecondary: Colors.white,
          surface: AppColors.bgSurface,
          onSurface: AppColors.textPrimary,
          error: AppColors.error,
        ),

        // ── AppBar ───────────────────────────────────────────────────────────
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.navyMid,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: AppColors.navyDeep,
          ),
          titleTextStyle: GoogleFonts.nunito(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),

        // ── Bottom Navigation ─────────────────────────────────────────────────
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.navBackground,
          selectedItemColor: AppColors.navSelected,
          unselectedItemColor: AppColors.navUnselected,
          type: BottomNavigationBarType.fixed,
          elevation: 12,
          selectedLabelStyle:
              TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle:
              TextStyle(fontWeight: FontWeight.w400, fontSize: 11),
        ),

        // ── Cards ─────────────────────────────────────────────────────────────
        cardTheme: CardThemeData(
          color: AppColors.bgCard,
          elevation: 3,
          shadowColor: AppColors.navyMid.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        ),

        // ── Elevated Button ───────────────────────────────────────────────────
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.navyMid,
            foregroundColor: Colors.white,
            elevation: 4,
            shadowColor: AppColors.navyMid.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),

        // ── Outlined Button ───────────────────────────────────────────────────
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.navyMid,
            side: const BorderSide(color: AppColors.navyMid, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),

        // ── Text Button ───────────────────────────────────────────────────────
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.navyMid,
            textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w600),
          ),
        ),

        // ── Input Decoration ──────────────────────────────────────────────────
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppColors.borderLight, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.navyMid, width: 2),
          ),
          labelStyle: GoogleFonts.nunito(color: AppColors.textSecondary),
          hintStyle: GoogleFonts.nunito(color: AppColors.textHint),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),

        // ── List Tile ─────────────────────────────────────────────────────────
        listTileTheme: const ListTileThemeData(
          tileColor: Colors.transparent,
          selectedTileColor: AppColors.bgSecondary,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),

        // ── Divider ───────────────────────────────────────────────────────────
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          thickness: 1,
          space: 1,
        ),

        // ── Chip ─────────────────────────────────────────────────────────────
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.bgSecondary,
          selectedColor: AppColors.navyMid,
          labelStyle:
              GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),

        // ── Switch ────────────────────────────────────────────────────────────
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.navyMid;
            return Colors.grey.shade400;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.navyMid.withValues(alpha: 0.4);
            }
            return Colors.grey.shade300;
          }),
        ),

        // ── Text ─────────────────────────────────────────────────────────────
        textTheme: GoogleFonts.nunitoTextTheme().copyWith(
          displayLarge: GoogleFonts.nunito(
            color: AppColors.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
          headlineMedium: GoogleFonts.nunito(
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: GoogleFonts.nunito(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: GoogleFonts.nunito(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: GoogleFonts.nunito(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          bodyMedium: GoogleFonts.nunito(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          labelLarge: GoogleFonts.nunito(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: GoogleFonts.nunito(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}
