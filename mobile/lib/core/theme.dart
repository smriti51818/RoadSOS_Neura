import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// RoadSoS design system — colors, typography, and MaterialTheme definitions.
class AppTheme {
  AppTheme._();

  // ── Color palette ────────────────────────────────────────────────────────────
  static const Color primaryGreen = Color(0xFF006B2C);
  static const Color emergencyRed = Color(0xFFE11D48);
  static const Color warningAmber = Color(0xFFF59E0B);
  
  static const Color policeBlue = Color(0xFF2563EB);
  static const Color aiNavy = Color(0xFF1E3A8A);
  static const Color protocolGreen = Color(0xFF064E3B);
  
  static const Color surfaceGray = Color(0xFFF9FAFB); // Very light gray background
  static const Color cardWhite = Color(0xFFFFFFFF); // Pure white for cards
  
  // No dark backgrounds anymore, but keeping names if referenced
  static const Color darkBackground = Color(0xFFF9FAFB); // Mapped to light
  static const Color darkCard = Color(0xFFFFFFFF); // Mapped to light

  static const Color textPrimary = Color(0xFF111827); // Dark gray, almost black
  static const Color textSecondary = Color(0xFF6B7280); // Medium gray
  static const Color borderColor = Color(0xFFE5E7EB); // Light gray border
  
  static const Color successGreen = Color(0xFF10B981);
  static const Color lightGreenBg = Color(0xFFECFDF5);

  // ── Design Tokens ─────────────────────────────────────────────────────────────
  
  static List<BoxShadow> get softShadows => [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          offset: const Offset(0, 8),
          blurRadius: 24,
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.02),
          offset: const Offset(0, 2),
          blurRadius: 8,
        ),
      ];

  static BoxDecoration get premiumCardDecoration => BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: softShadows,
      );

  // ── Typography ────────────────────────────────────────────────────────────────
  static TextStyle get headingXL => GoogleFonts.outfit(
        fontSize: 48,
        fontWeight: FontWeight.w800,
        color: textPrimary,
        letterSpacing: -1.0,
      );

  static TextStyle get headingLG => GoogleFonts.outfit(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.5,
      );

  static TextStyle get headingMD => GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      );

  static TextStyle get headingSM => GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      );

  static TextStyle get bodyLG => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: textPrimary,
      );

  static TextStyle get bodyMD => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: textPrimary,
      );

  static TextStyle get bodySM => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  static TextStyle get labelMD => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  static TextStyle get labelSM => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: textSecondary,
      );

  // ── Light theme ───────────────────────────────────────────────────────────────
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryGreen,
      brightness: Brightness.light,
      primary: primaryGreen,
      surface: surfaceGray,
      error: emergencyRed,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceGray,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent, // Clean transparent header
        foregroundColor: textPrimary,
        titleTextStyle: headingMD,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderColor, width: 1),
        ),
        color: cardWhite,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: cardWhite,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: labelMD.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: primaryGreen, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: cardWhite,
        selectedItemColor: primaryGreen,
        unselectedItemColor: textSecondary,
        elevation: 20,
        type: BottomNavigationBarType.fixed,
      ),
      textTheme: _buildTextTheme(textPrimary),
    );
  }

  static TextTheme _buildTextTheme(Color baseColor) {
    return TextTheme(
      displayLarge: GoogleFonts.outfit(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: baseColor,
      ),
      displayMedium: GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      titleLarge: GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      titleMedium: GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: baseColor,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: baseColor,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: baseColor.withOpacity(0.7),
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: baseColor.withOpacity(0.7),
      ),
    );
  }
}
