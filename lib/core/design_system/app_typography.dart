import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTypography {
  AppTypography._();

  // Page Titles: 28px, SemiBold, tightly tracked (-0.5px)
  static TextStyle get h1 => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      );

  // Card/Section Headers: 18px, Medium
  static TextStyle get h2 => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w500,
      );

  // Subtitles / Highlights: 16px, Medium
  static TextStyle get h3 => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      );

  // Compact Titles: 14px, Medium
  static TextStyle get h4 => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      );

  // Body Text Large: 16px, Regular, 1.5 line height
  static TextStyle get bodyLarge => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  // Body Text Medium: 14px, Regular, 1.5 line height
  static TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  // Labels/Metadata: 12px, Medium, ALL CAPS with generous letter spacing (1.2px)
  static TextStyle get caption => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.2,
      );

  // Button Text
  static TextStyle get buttonText => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );
}
