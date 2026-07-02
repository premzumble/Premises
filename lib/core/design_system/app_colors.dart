import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Branding (Warm Forest/Olive Style inspired by the reference)
  static const Color primary = Color(0xFF2E3D30); // Forest Green
  static const Color primaryHover = Color(0xFF1E2B1F); 
  static const Color primaryLight = Color(0xFFF1F3EE); 

  // Neutrals (Warm Linen Palette - Premium SaaS standard)
  static const Color backgroundLight = Color(0xFFF9F9F6); // Warm linen
  static const Color surfaceLight = Colors.white;
  static const Color borderLight = Color(0xFFE8E8E1); // Soft warm border
  static const Color textPrimaryLight = Color(0xFF1C221C); // Deep charcoal green
  static const Color textSecondaryLight = Color(0xFF556055); // Muted warm gray-green
  static const Color textMutedLight = Color(0xFF98A298); // Light warm gray-green

  // Dark Mode Neutrals (Deepest Zinc)
  static const Color backgroundDark = Color(0xFF09090B); 
  static const Color surfaceDark = Color(0xFF18181B); 
  static const Color borderDark = Color(0xFF27272A); 
  static const Color textPrimaryDark = Color(0xFFFAFAFA); 
  static const Color textSecondaryDark = Color(0xFFA1A1AA); 
  static const Color textMutedDark = Color(0xFF71717A); 
  static const Color primaryDark = Color(0xFF3B82F6); // Vibrant Blue Accent

  // Soft Accents (Present, Outside, Absent, Info)
  static const Color success = Color(0xFF10B981); // Emerald Success
  static const Color warning = Color(0xFFF59E0B); // Amber Warning
  static const Color danger = Color(0xFFEF4444); // Red Danger
  static const Color error = Color(0xFFEF4444); // Alias for danger
  static const Color info = Color(0xFF3B82F6); // Vibrant Blue Info
}
