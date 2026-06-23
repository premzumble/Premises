import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Branding (Stripe/Linear Indigo Style)
  static const Color primary = Color(0xFF4F46E5); // Indigo 600
  static const Color primaryHover = Color(0xFF4338CA); // Indigo 700
  static const Color primaryLight = Color(0xFFEEF2F6); // Indigo 50

  // Neutrals (Slate Palette - Modern SaaS standard)
  static const Color backgroundLight = Color(0xFFF8FAFC); // Slate 50
  static const Color surfaceLight = Colors.white;
  static const Color borderLight = Color(0xFFE2E8F0); // Slate 200
  static const Color textPrimaryLight = Color(0xFF0F172A); // Slate 900
  static const Color textSecondaryLight = Color(0xFF475569); // Slate 600
  static const Color textMutedLight = Color(0xFF94A3B8); // Slate 400

  // Dark Mode Neutrals
  static const Color backgroundDark = Color(0xFF0B0F19); // Slate 950
  static const Color surfaceDark = Color(0xFF1E293B); // Slate 800
  static const Color borderDark = Color(0xFF334155); // Slate 700
  static const Color textPrimaryDark = Color(0xFFF8FAFC); // Slate 50
  static const Color textSecondaryDark = Color(0xFF94A3B8); // Slate 400
  static const Color textMutedDark = Color(0xFF64748B); // Slate 500

  // Soft Accents (Present, Outside, Absent, Info)
  static const Color success = Color(0xFF10B981); // Emerald 500 (Present)
  static const Color warning = Color(0xFFF59E0B); // Amber 500 (Outside)
  static const Color danger = Color(0xFFEF4444); // Red 500 (Absent)
  static const Color error = Color(0xFFEF4444); // Alias for danger
  static const Color info = Color(0xFF3B82F6); // Blue 500 (Info/Pending)
}
