import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTypography {
  // ── Display ───────────────────────────────────────────────
  static TextStyle display1 = GoogleFonts.archivo(
    fontSize: 48, fontWeight: FontWeight.w900,
    color: AppColors.textPrimary, height: 1.0, letterSpacing: -1.5,
  );
  static TextStyle display2 = GoogleFonts.archivo(
    fontSize: 36, fontWeight: FontWeight.w900,
    color: AppColors.textPrimary, height: 1.1, letterSpacing: -1.0,
  );

  // ── Headlines ─────────────────────────────────────────────
  static TextStyle h1 = GoogleFonts.dmSans(
    fontSize: 28, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, height: 1.2, letterSpacing: -0.5,
  );
  static TextStyle h2 = GoogleFonts.dmSans(
    fontSize: 22, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, height: 1.25, letterSpacing: -0.3,
  );
  static TextStyle h3 = GoogleFonts.dmSans(
    fontSize: 18, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary, height: 1.3,
  );
  static TextStyle h4 = GoogleFonts.dmSans(
    fontSize: 15, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary, height: 1.35,
  );

  // ── Body ──────────────────────────────────────────────────
  static TextStyle bodyLarge = GoogleFonts.dmSans(
    fontSize: 16, fontWeight: FontWeight.w400,
    color: AppColors.textSecondary, height: 1.5,
  );
  static TextStyle bodyMedium = GoogleFonts.dmSans(
    fontSize: 14, fontWeight: FontWeight.w400,
    color: AppColors.textSecondary, height: 1.5,
  );
  static TextStyle bodySmall = GoogleFonts.dmSans(
    fontSize: 12, fontWeight: FontWeight.w400,
    color: AppColors.textTertiary, height: 1.4,
  );

  // ── Labels / UI ───────────────────────────────────────────
  static TextStyle labelLarge = GoogleFonts.dmSans(
    fontSize: 14, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary, letterSpacing: 0.1,
  );
  static TextStyle labelMedium = GoogleFonts.dmSans(
    fontSize: 12, fontWeight: FontWeight.w600,
    color: AppColors.textSecondary, letterSpacing: 0.3,
  );
  static TextStyle labelSmall = GoogleFonts.dmSans(
    fontSize: 10, fontWeight: FontWeight.w700,
    color: AppColors.textTertiary, letterSpacing: 0.8,
  );

  // ── Numérico ──────────────────────────────────────────────
  static TextStyle numericHero = GoogleFonts.dmSans(
    fontSize: 40, fontWeight: FontWeight.w800,
    color: AppColors.primary, height: 1.0, letterSpacing: -1.0,
  );
  static TextStyle numericLarge = GoogleFonts.dmSans(
    fontSize: 24, fontWeight: FontWeight.w700,
    color: AppColors.primary, height: 1.1,
  );
  static TextStyle numericMedium = GoogleFonts.dmSans(
    fontSize: 16, fontWeight: FontWeight.w700,
    color: AppColors.primary,
  );

  // ── Mono — PIX, IDs, placas ───────────────────────────────
  static TextStyle mono = GoogleFonts.jetBrainsMono(
    fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.textSecondary, letterSpacing: 0.5,
  );
  static TextStyle monoBold = GoogleFonts.jetBrainsMono(
    fontSize: 13, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  // ── Botão ─────────────────────────────────────────────────
  static TextStyle button = GoogleFonts.dmSans(
    fontSize: 16, fontWeight: FontWeight.w700,
    color: AppColors.textInverse, letterSpacing: 0.2,
  );
  static TextStyle buttonSmall = GoogleFonts.dmSans(
    fontSize: 13, fontWeight: FontWeight.w700,
    color: AppColors.textInverse, letterSpacing: 0.2,
  );
}
