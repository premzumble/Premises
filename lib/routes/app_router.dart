import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/session_manager.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/forgot_password/forgot_password_screen.dart';
import '../features/auth/screens/forgot_password/verify_reset_otp_screen.dart';
import '../features/auth/screens/forgot_password/reset_password_screen.dart';
import '../features/auth/screens/forgot_password/reset_success_screen.dart';
import '../features/onboarding/screens/splash_screen.dart';
import '../features/onboarding/screens/permission_onboarding_screen.dart';
import '../features/faculty/layouts/faculty_navigation.dart';
import '../features/faculty/screens/faculty_dashboard_screen.dart';
import '../features/faculty/screens/faculty_history_screen.dart';
import '../features/faculty/screens/faculty_notifications_screen.dart';
import '../features/faculty/screens/faculty_profile_screen.dart';
import '../features/faculty/screens/faculty_device_screen.dart';
import '../features/faculty/screens/faculty_reason_request_screen.dart';
import '../features/admin/layouts/admin_navigation.dart';
import '../features/admin/screens/dashboard_screen.dart';
import '../features/admin/screens/requests_screen.dart';
import '../features/admin/screens/simulator_screen.dart';
import '../features/attendance/screens/attendance_screen.dart';
import '../features/attendance/screens/faculty_list_screen.dart';
import '../features/logs/screens/logs_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/reports/screens/reports_screen.dart';

class AppRouter {
  AppRouter._();

  static Page<dynamic> _buildFadePage(Widget child, GoRouterState state) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }

  /// Redirect logic — enforces RBAC and authentication on every navigation event.
  static String? _redirect(BuildContext context, GoRouterState state) {
    final path = state.matchedLocation;
    final isLoggedIn = SessionManager.isLoggedIn;
    final isAdmin = SessionManager.isAdmin;
    final isFaculty = SessionManager.isFaculty;

    // Public routes — allow unauthenticated access
    final publicRoutes = ['/splash', '/login', '/register', '/forgot-password', '/onboarding'];
    final isPublic = publicRoutes.any((r) => path.startsWith(r));

    // Not logged in: always redirect to login (unless already on a public route)
    if (!isLoggedIn && !isPublic) {
      return '/login';
    }

    // Role-based access control
    if (isLoggedIn) {
      // 1. Trying to access public routes while logged in? Redirect to dashboard.
      if (path == '/login' || path == '/register') {
        return isAdmin ? '/admin/dashboard' : '/faculty/dashboard';
      }

      // 2. Cross-role access prevention
      if (isFaculty && path.startsWith('/admin')) {
        return '/faculty/dashboard';
      }
      if (isAdmin && path.startsWith('/faculty')) {
        return '/admin/dashboard';
      }
    }

    return null; // No redirect needed
  }

  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    redirect: _redirect,
    routes: [
      // ----------------------------------------------------------------
      // Bootstrap & Onboarding
      // ----------------------------------------------------------------
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const PermissionOnboardingScreen(),
      ),

      // ----------------------------------------------------------------
      // Public: Auth Routes
      // ----------------------------------------------------------------
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // ----------------------------------------------------------------
      // Forgot Password Flow (Public)
      // ----------------------------------------------------------------
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
        routes: [
          GoRoute(
            path: 'verify',
            builder: (context, state) {
              final email = state.extra as String? ?? '';
              return VerifyResetOtpScreen(email: email);
            },
          ),
          GoRoute(
            path: 'reset',
            builder: (context, state) {
              final data = state.extra as Map<String, dynamic>? ?? {};
              return ResetPasswordScreen(
                email: data['email'] ?? '',
                otp: data['otp'] ?? '',
              );
            },
          ),
          GoRoute(
            path: 'success',
            builder: (context, state) => const ResetSuccessScreen(),
          ),
        ],
      ),

      // ----------------------------------------------------------------
      // Faculty Portal (Protected: FACULTY role only)
      // ----------------------------------------------------------------
      ShellRoute(
        builder: (context, state, child) {
          return FacultyNavigation(
            location: state.matchedLocation,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/faculty/dashboard',
            pageBuilder: (context, state) => _buildFadePage(const FacultyDashboardScreen(), state),
          ),
          GoRoute(
            path: '/faculty/history',
            pageBuilder: (context, state) => _buildFadePage(const FacultyHistoryScreen(), state),
          ),
          GoRoute(
            path: '/faculty/notifications',
            pageBuilder: (context, state) => _buildFadePage(const FacultyNotificationsScreen(), state),
          ),
          GoRoute(
            path: '/faculty/device',
            pageBuilder: (context, state) => _buildFadePage(const FacultyDeviceScreen(), state),
          ),
          GoRoute(
            path: '/faculty/profile',
            pageBuilder: (context, state) => _buildFadePage(const FacultyProfileScreen(), state),
          ),
          GoRoute(
            path: '/faculty/reason-request',
            pageBuilder: (context, state) => _buildFadePage(const FacultyReasonRequestScreen(), state),
          ),
        ],
      ),

      // ----------------------------------------------------------------
      // Admin Portal (Protected: ADMIN role only)
      // ----------------------------------------------------------------
      ShellRoute(
        builder: (context, state, child) {
          return AdminNavigation(
            location: state.matchedLocation,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/admin/dashboard',
            pageBuilder: (context, state) => _buildFadePage(const DashboardScreen(), state),
          ),
          GoRoute(
            path: '/admin/faculty',
            pageBuilder: (context, state) {
              final status = state.uri.queryParameters['status'];
              return _buildFadePage(FacultyListScreen(filterStatus: status), state);
            },
          ),
          GoRoute(
            path: '/admin/attendance',
            pageBuilder: (context, state) => _buildFadePage(const AttendanceScreen(), state),
          ),
          GoRoute(
            path: '/admin/reports',
            pageBuilder: (context, state) => _buildFadePage(const ReportsScreen(), state),
          ),
          GoRoute(
            path: '/admin/logs',
            pageBuilder: (context, state) => _buildFadePage(const LogsScreen(), state),
          ),
          GoRoute(
            path: '/admin/requests',
            pageBuilder: (context, state) => _buildFadePage(const RequestsScreen(), state),
          ),
          GoRoute(
            path: '/admin/settings',
            pageBuilder: (context, state) => _buildFadePage(const SettingsScreen(), state),
          ),
          // Debug-only: Attendance Simulator (not shown in release builds)
          if (kDebugMode)
            GoRoute(
              path: '/admin/simulator',
              pageBuilder: (context, state) => _buildFadePage(const SimulatorScreen(), state),
            ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Navigation Error',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(state.error.toString()),
          ],
        ),
      ),
    ),
  );
}
