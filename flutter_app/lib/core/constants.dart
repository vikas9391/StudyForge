// lib/core/constants.dart
// App-wide design tokens: colors, gradients, text styles, and theme.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Color Palette ─────────────────────────────────────────────────────────────
class AppColors {
  // Backgrounds
  static const Color bg          = Color(0xFF0D1117);
  static const Color bgGradTop   = Color(0xFF1A0A2E);
  static const Color surface     = Color(0xFF161B22);
  static const Color surfaceCard = Color(0xFF1C2333);
  static const Color border      = Color(0xFF30363D);
  static const Color borderLight = Color(0xFF21262D);

  // Brand purple
  static const Color primary      = Color(0xFF7C3AED);
  static const Color primaryEnd   = Color(0xFF4F46E5);
  static const Color primaryLight = Color(0xFF9D5CF5);
  static const Color primaryGlow  = Color(0x337C3AED);

  // Semantic accents
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentBlue  = Color(0xFF3B82F6);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentRed   = Color(0xFFEF4444);

  // Text
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textBody    = Color(0xFFC9D1D9);
  static const Color textSecond  = Color(0xFF8B949E);
  static const Color textMuted   = Color(0xFF484F58);

  // Gradients
  static const LinearGradient primaryGrad = LinearGradient(
    begin: Alignment.topLeft,
    end:   Alignment.bottomRight,
    colors: [primary, primaryEnd],
  );

  static const LinearGradient bgGrad = LinearGradient(
    begin:  Alignment.topCenter,
    end:    Alignment.bottomCenter,
    colors: [bgGradTop, bg],
    stops:  [0.0, 0.40],
  );
}

// ── Typography ────────────────────────────────────────────────────────────────
class AppText {
  // Large display heading (SpaceGrotesk gives a premium feel)
  static TextStyle display(double size) => GoogleFonts.spaceGrotesk(
    fontSize:     size,
    fontWeight:   FontWeight.w700,
    color:        AppColors.textPrimary,
    letterSpacing: -0.5,
    height:       1.2,
  );

  static TextStyle heading = GoogleFonts.spaceGrotesk(
    fontSize:   20,
    fontWeight: FontWeight.w600,
    color:      AppColors.textPrimary,
  );

  static TextStyle subheading = GoogleFonts.spaceGrotesk(
    fontSize:   16,
    fontWeight: FontWeight.w600,
    color:      AppColors.textPrimary,
  );

  static TextStyle body = GoogleFonts.inter(
    fontSize: 14,
    color:    AppColors.textPrimary,
    height:   1.6,
  );

  static TextStyle bodySmall = GoogleFonts.inter(
    fontSize: 13,
    color:    AppColors.textBody,
    height:   1.6,
  );

  static TextStyle caption = GoogleFonts.inter(
    fontSize: 12,
    color:    AppColors.textSecond,
    height:   1.5,
  );

  static TextStyle label = GoogleFonts.inter(
    fontSize:     11,
    fontWeight:   FontWeight.w600,
    color:        AppColors.textSecond,
    letterSpacing: 0.5,
  );
}

// ── Reusable decorations ──────────────────────────────────────────────────────
BoxDecoration cardDecoration({Color? border, Color? bg}) => BoxDecoration(
  color:        bg ?? AppColors.surfaceCard,
  borderRadius: BorderRadius.circular(16),
  border:       Border.all(color: border ?? AppColors.borderLight),
);

// ── Theme ─────────────────────────────────────────────────────────────────────
ThemeData buildAppTheme() {
  return ThemeData(
    brightness:              Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary:    AppColors.primary,
      surface:    AppColors.surface,
      background: AppColors.bg,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled:       true,
      fillColor:    AppColors.surface,
      border:       OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:   const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:   const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:   const BorderSide(color: AppColors.primary, width: 2),
      ),
      hintStyle:       AppText.caption,
      labelStyle:      AppText.caption,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor:        Colors.transparent,
      elevation:              0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: AppColors.textSecond),
    ),
  );
}
