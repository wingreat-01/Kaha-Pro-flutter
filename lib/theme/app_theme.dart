import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Kahapro's new visual identity: the app is styled after a physical
/// cash register / calculator, not a generic SaaS dashboard.
/// "Kaha" is Tagalog for cash box — this palette leans into that.
class AppColors {
  static const charcoal = Color(0xFF1E2126);   // base background / register body
  static const slate = Color(0xFF2A2E35);      // cards / surfaces
  static const slateField = Color(0xFF15171A); // input fields, recessed areas
  static const slateBorder = Color(0xFF2E323A);

  static const ledAmber = Color(0xFFFFB020);   // primary accent — digital readout
  static const tillGreen = Color(0xFF3FA796);  // secondary accent — confirm/paid
  static const ledgerRed = Color(0xFFE4572E);  // errors / voids

  static const paperCream = Color(0xFFF6F1E4); // receipt/ticket surfaces only
  static const paperInk = Color(0xFF2A2117);   // text on paper

  static const textPrimary = Color(0xFFF6F1E4);
  static const textSecondary = Color(0xFF8A8F97);
  static const textMuted = Color(0xFF6B7078);
}

/// Numeric/display text — every price, total, and quantity uses this,
/// so the whole app reads like a calculator readout.
class AppTextStyles {
  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
  }) =>
      GoogleFonts.manrope(
        fontSize: size,
        fontWeight: weight,
        color: color,
      );
}

class AppTheme {
  static ThemeData build() {
    final base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.charcoal,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.ledAmber,
        secondary: AppColors.tillGreen,
        surface: AppColors.slate,
        error: AppColors.ledgerRed,
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.manropeTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.slateField,
        hintStyle: AppTextStyles.body(color: AppColors.textMuted, size: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.slateBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.slateBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.ledAmber, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ledAmber,
          foregroundColor: const Color(0xFF3A2600),
          disabledBackgroundColor: AppColors.ledAmber.withOpacity(0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: AppTextStyles.body(size: 15, weight: FontWeight.w700, color: const Color(0xFF3A2600)),
          elevation: 0,
        ),
      ),
    );
  }
}
