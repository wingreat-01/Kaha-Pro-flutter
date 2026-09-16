import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Kahapro's visual identity: styled after a physical cash register /
/// calculator, not a generic SaaS dashboard. "Kaha" is Tagalog for
/// cash box — this palette leans into that.
///
/// AppColors now carries both a dark (original) and light palette.
/// Every field is a *getter* that reads whichever palette is active,
/// switched via [AppColors.isLight]. Existing call sites
/// (`AppColors.slate`, `AppColors.textPrimary`, etc. — used all over
/// the app, e.g. settings_panel.dart) don't need to change; they just
/// start returning light-palette values once isLight flips.
///
/// isLight itself is set by ThemeProvider (see state/theme_provider.dart)
/// whenever the resolved brightness changes. Flipping the bool alone
/// doesn't repaint anything — the widget tree has to actually rebuild
/// for these getters to be re-read. main.dart forces that with a
/// KeyedSubtree around `home` (see the comment there for why).
class AppColors {
  static bool isLight = false;

  // ---- Dark palette (original) ----
  static const _darkCharcoal = Color(0xFF1E2126);
  static const _darkSlate = Color(0xFF2A2E35);
  static const _darkSlateField = Color(0xFF15171A);
  static const _darkSlateBorder = Color(0xFF2E323A);
  static const _darkTextPrimary = Color(0xFFF6F1E4);
  static const _darkTextSecondary = Color(0xFF8A8F97);
  static const _darkTextMuted = Color(0xFF6B7078);

  // ---- Light palette ----
  // Brand accents (amber/green/red) stay the same across themes —
  // only the surfaces and text invert. Charcoal -> warm off-white,
  // slate cards -> white, slate borders -> a light warm-gray hairline.
  static const _lightCharcoal = Color(0xFFF7F5F1);   // base background
  static const _lightSlate = Color(0xFFFFFFFF);      // cards / surfaces
  static const _lightSlateField = Color(0xFFF0EEE9); // input fields, recessed areas
  static const _lightSlateBorder = Color(0xFFE1DDD3);
  static const _lightTextPrimary = Color(0xFF2A2117);
  static const _lightTextSecondary = Color(0xFF6B6459);
  static const _lightTextMuted = Color(0xFF938C7F);

  // ---- Brand accents — unchanged across themes ----
  static const ledAmber = Color(0xFFFFB020);  // primary accent — digital readout
  static const tillGreen = Color(0xFF3FA796); // secondary accent — confirm/paid
  static const ledgerRed = Color(0xFFE4572E); // errors / voids

  static const paperCream = Color(0xFFF6F1E4); // receipt/ticket surfaces only (unchanged — receipts stay paper-styled in both themes)
  static const paperInk = Color(0xFF2A2117);   // text on paper

  static Color get charcoal => isLight ? _lightCharcoal : _darkCharcoal;
  static Color get slate => isLight ? _lightSlate : _darkSlate;
  static Color get slateField => isLight ? _lightSlateField : _darkSlateField;
  static Color get slateBorder => isLight ? _lightSlateBorder : _darkSlateBorder;

  static Color get textPrimary => isLight ? _lightTextPrimary : _darkTextPrimary;
  static Color get textSecondary => isLight ? _lightTextSecondary : _darkTextSecondary;
  static Color get textMuted => isLight ? _lightTextMuted : _darkTextMuted;
}

/// Numeric/display text — every price, total, and quantity uses this,
/// so the whole app reads like a calculator readout.
class AppTextStyles {
  // NOTE: `color` used to default to `AppColors.textPrimary` directly
  // in the parameter list. That only worked because textPrimary was a
  // `static const`; now that it's a getter (so it can respond to
  // AppColors.isLight), it's no longer a compile-time constant and
  // can't sit in a default value. Nullable param + `??` inside the
  // body gets the same effect.
  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.textPrimary,
        letterSpacing: letterSpacing,
      );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) =>
      GoogleFonts.manrope(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.textPrimary,
      );
}

class AppTheme {
  static ThemeData _buildFor({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color inputFill,
    required Color border,
    required Color textPrimary,
    required Color textMuted,
  }) {
    final base = ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: brightness == Brightness.dark
          ? const ColorScheme.dark(
              primary: AppColors.ledAmber,
              secondary: AppColors.tillGreen,
              surface: AppColors._darkSlate,
              error: AppColors.ledgerRed,
            )
          : ColorScheme.light(
              primary: AppColors.ledAmber,
              secondary: AppColors.tillGreen,
              surface: surface,
              error: AppColors.ledgerRed,
            ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.manropeTextTheme(base.textTheme).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        hintStyle: GoogleFonts.manrope(color: textMuted, fontSize: 14, fontWeight: FontWeight.w500),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border, width: 1),
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
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF3A2600)),
          elevation: 0,
        ),
      ),
    );
  }

  static ThemeData dark() => _buildFor(
        brightness: Brightness.dark,
        background: AppColors._darkCharcoal,
        surface: AppColors._darkSlate,
        inputFill: AppColors._darkSlateField,
        border: AppColors._darkSlateBorder,
        textPrimary: AppColors._darkTextPrimary,
        textMuted: AppColors._darkTextMuted,
      );

  static ThemeData light() => _buildFor(
        brightness: Brightness.light,
        background: AppColors._lightCharcoal,
        surface: AppColors._lightSlate,
        inputFill: AppColors._lightSlateField,
        border: AppColors._lightSlateBorder,
        textPrimary: AppColors._lightTextPrimary,
        textMuted: AppColors._lightTextMuted,
      );

  /// Old call sites (`AppTheme.build()`) still work — returns whichever
  /// palette AppColors.isLight currently points at. New code (main.dart)
  /// should use dark()/light() directly with MaterialApp's themeMode.
  static ThemeData build() => AppColors.isLight ? light() : dark();
}
