// lib/core/constants.dart
// App-wide design tokens: colors, gradients, text styles, and theme.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Color Palette ─────────────────────────────────────────────────────────────
class AppColors {
  // Backgrounds — warm ivory / parchment
  static const Color bg          = Color(0xFFF8F5F0);
  static const Color bgGradTop   = Color(0xFFFDFBF7);
  static const Color surface     = Color(0xFFFFFFFF);
  static const Color surfaceCard = Color(0xFFFFFEFC);
  static const Color border      = Color(0xFFE8E2D9);
  static const Color borderLight = Color(0xFFF0EBE3);

  // Brand — deep indigo (professional, trustworthy)
  static const Color primary      = Color(0xFF2D3A8C);
  static const Color primaryEnd   = Color(0xFF1E2D6E);
  static const Color primaryLight = Color(0xFF4A5BA8);
  // ignore: constant_identifier_names
  static const Color primaryGlow  = Color(0x222D3A8C);

  // Semantic accents — restrained, distinct
  static const Color accentGreen = Color(0xFF1A7F5E);
  static const Color accentBlue  = Color(0xFF1A6FA8);
  static const Color accentAmber = Color(0xFFB07D1A);
  static const Color accentRed   = Color(0xFFB03A2E);

  // Text — warm dark slate
  static const Color textPrimary = Color(0xFF1A1814);
  static const Color textBody    = Color(0xFF3C3830);
  static const Color textSecond  = Color(0xFF7A7268);
  static const Color textMuted   = Color(0xFFB8B0A4);

  // ── Home-screen specific palette additions ──────────────────────────────────
  // Upload CTA card background
  static const Color ctaBlue     = Color(0xFF2A5DB8);

  // Session tile accent colours (cycled by index)
  static const List<Color> tileAccents = [
    Color(0xFF2A5DB8),
    Color(0xFF2A8A4A),
    Color(0xFFC97D12),
    Color(0xFF7B55C8),
  ];
  static const List<Color> tileAccentBgs = [
    Color(0xFFEDF2FC),
    Color(0xFFEDFAF3),
    Color(0xFFFDF6E8),
    Color(0xFFF5EDFB),
  ];

  // Continue card — amber border / highlight
  static const Color continueAmber    = Color(0xFFE8A520);
  static const Color continueAmberBg  = Color(0xFFFDF2E0);
  static const Color continueAmberFg  = Color(0xFFC97D12);

  // Due-for-review section
  static const Color reviewRedBg      = Color(0xFFFDE8E8);
  static const Color reviewRedFg      = Color(0xFFC94040);

  // Stats section — positive delta
  static const Color deltaGreen       = Color(0xFF2A8A4A);

  // Review-item dot colours (cycled by index)
  static const List<Color> reviewDots = [
    Color(0xFF4A80E0),
    Color(0xFF2A8A4A),
    Color(0xFFC97D12),
  ];
  static const List<Color> reviewCountBgs = [
    Color(0xFFEDF2FC),
    Color(0xFFEDFAF3),
    Color(0xFFFDF6E8),
  ];
  static const List<Color> reviewCountFgs = [
    Color(0xFF2A5DB8),
    Color(0xFF2A8A4A),
    Color(0xFFC97D12),
  ];

  // Avatar / profile circle
  static const Color avatarBlue = Color(0xFF3B6FCA);

  // Gradients
  static const LinearGradient primaryGrad = LinearGradient(
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
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
  // Large display heading — Playfair Display for editorial authority
  static TextStyle display(double size) => GoogleFonts.playfairDisplay(
    fontSize:      size,
    fontWeight:    FontWeight.w700,
    color:         AppColors.textPrimary,
    letterSpacing: -0.3,
    height:        1.2,
  );

  static TextStyle heading = GoogleFonts.playfairDisplay(
    fontSize:   20,
    fontWeight: FontWeight.w700,
    color:      AppColors.textPrimary,
  );

  static TextStyle subheading = GoogleFonts.dmSans(
    fontSize:   16,
    fontWeight: FontWeight.w600,
    color:      AppColors.textPrimary,
  );

  static TextStyle body = GoogleFonts.dmSans(
    fontSize: 14,
    color:    AppColors.textBody,
    height:   1.6,
  );

  static TextStyle bodySmall = GoogleFonts.dmSans(
    fontSize: 13,
    color:    AppColors.textBody,
    height:   1.6,
  );

  static TextStyle caption = GoogleFonts.dmSans(
    fontSize: 12,
    color:    AppColors.textSecond,
    height:   1.5,
  );

  static TextStyle label = GoogleFonts.dmSans(
    fontSize:      11,
    fontWeight:    FontWeight.w600,
    color:         AppColors.textSecond,
    letterSpacing: 0.6,
  );
}

// ── Reusable decorations ──────────────────────────────────────────────────────
BoxDecoration cardDecoration({Color? border, Color? bg}) => BoxDecoration(
  color:        bg ?? AppColors.surfaceCard,
  borderRadius: BorderRadius.circular(16),
  border:       Border.all(color: border ?? AppColors.borderLight),
  boxShadow: [
    BoxShadow(
      color:      const Color(0xFF1A1814).withOpacity(0.04),
      blurRadius: 12,
      offset:     const Offset(0, 2),
    ),
  ],
);

// ── Theme ─────────────────────────────────────────────────────────────────────
ThemeData buildAppTheme() {
  return ThemeData(
    brightness:              Brightness.light,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.light(
      primary:    AppColors.primary,
      surface:    AppColors.surface,
      background: AppColors.bg,
    ),
    textTheme: GoogleFonts.dmSansTextTheme(ThemeData.light().textTheme),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding:   const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
        shape:     RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 15),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled:      true,
      fillColor:   AppColors.surface,
      border: OutlineInputBorder(
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
      hintStyle:      AppText.caption,
      labelStyle:     AppText.caption,
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