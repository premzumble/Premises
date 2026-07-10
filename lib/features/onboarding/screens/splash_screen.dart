import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../../../core/session_manager.dart';
import '../../../core/api_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/premises_loader.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final startTime = DateTime.now();

    // 1. Core Service Initialization
    await NotificationService.initialize();

    // 2. Session Restoration
    await SessionManager.restore();

    // 3. Validation & Onboarding Checks
    String targetLocation = '/login';

    if (SessionManager.isLoggedIn) {
      final isValid = await _validateSession();
      if (isValid) {
        targetLocation = SessionManager.isAdmin ? '/admin/dashboard' : '/faculty/dashboard';
      } else {
        await SessionManager.clear();
      }
    }

    // 4. Mobile-specific Onboarding Logic
    // If not web and permissions haven't been onboarded, force onboarding flow first.
    if (!kIsWeb && !SessionManager.permissionsOnboarded) {
      targetLocation = '/onboarding';
    }

    // 5. Intelligent Timing (Min 1.2s to prevent flicker)
    final elapsed = DateTime.now().difference(startTime);
    const minDuration = Duration(milliseconds: 1200);
    if (elapsed < minDuration) {
      await Future.delayed(minDuration - elapsed);
    }

    if (mounted) {
      context.go(targetLocation);
    }
  }

  Future<bool> _validateSession() async {
    try {
      if (SessionManager.isAdmin) {
        await ApiService.fetchSettings();
      } else {
        await ApiService.fetchFacultyProfile();
        // Fetch and cache the latest geofence config on startup/bootstrap
        try {
          final data = await ApiService.fetchDashboardSummary();
          final double lat = data['geofence_latitude'] != null ? (data['geofence_latitude'] as num).toDouble() : 0.0;
          final double lng = data['geofence_longitude'] != null ? (data['geofence_longitude'] as num).toDouble() : 0.0;
          final double rad = data['geofence_radius'] != null ? (data['geofence_radius'] as num).toDouble() : 0.0;
          final String type = data['geofence_type'] as String? ?? 'circle';
          final vertices = data['geofence_vertices'];
          final String? verticesJson = vertices != null ? json.encode(vertices) : null;
          final int allowedOutside = data['allowed_outside_minutes'] as int? ?? 25;
          final int rem1 = data['reminder_1_minutes'] as int? ?? 0;
          final int rem2 = data['reminder_2_minutes'] as int? ?? 0;
          final int rem3 = data['reminder_3_minutes'] as int? ?? 0;
          final int eval = data['evaluation_minutes'] as int? ?? 15;
          final String? gfId = data['geofence_id'] as String?;
          final String? gfUpdatedAt = data['geofence_updated_at'] as String?;
          SessionManager.cacheGeofence(lat, lng, rad, type, verticesJson, allowedOutside, rem1, rem2, rem3, eval, gfId, gfUpdatedAt);
        } catch (e) {
          debugPrint('[Splash] Failed to pre-fetch geofence: $e');
        }
      }
      return true;
    } on ApiException catch (e) {
      if (e.isAuthError) return false;
      return true; // Network error - allow offline access to cached data
    } catch (_) {
      return true; 
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF09090B) : const Color(0xFFF9F9F6),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PremisesBrandedLoader(),
              const SizedBox(height: 16),
              Text(
                'Initializing Premises Portal...',
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo placeholder (Asset image should be here in real app)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.domain, size: 64, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Premises',
              style: AppTypography.h1.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Smart Workforce Management',
              style: AppTypography.bodyMedium.copyWith(
                color: Colors.white.withOpacity(0.8),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
