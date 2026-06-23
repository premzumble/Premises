import 'package:flutter/material.dart';

class AppShadows {
  AppShadows._();

  static List<BoxShadow> get softSm => [
        const BoxShadow(
          color: Color(0x05000000),
          offset: Offset(0, 1),
          blurRadius: 2,
        ),
      ];

  static List<BoxShadow> get softMd => [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          offset: const Offset(0, 4),
          blurRadius: 12,
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.02),
          offset: const Offset(0, 2),
          blurRadius: 4,
        ),
      ];

  static List<BoxShadow> get softLg => [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          offset: const Offset(0, 12),
          blurRadius: 24,
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          offset: const Offset(0, 4),
          blurRadius: 8,
        ),
      ];
}
