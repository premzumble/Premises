import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/session_manager.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
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

  /// Redirect logic — enforces RBAC and authentication on every navigation event.
  static String? _redirect(BuildContext context, GoRouterState state) {
    final path = state.matchedLocation;
    final isLoggedIn = SessionManager.isLoggedIn;
    final isAdmin = SessionManager.isAdmin;
    final isFaculty = SessionManager.isFaculty;

    // Public routes — allow unauthenticated access
    final publicRoutes = ['/login', '/register'];
    final isPublic = publicRoutes.any((r) => path.startsWith(r));

    // Not logged in: always redirect to login
    if (!isLoggedIn && !isPublic) {
      return '/login';
    }

    // Already logged in: redirect away from public pages to the correct dashboard
    if (isLoggedIn && isPublic) {
      return isAdmin ? '/admin/dashboard' : '/faculty/dashboard';
    }

    // Logged in as FACULTY trying to access ADMIN routes → redirect to their dashboard
    if (isFaculty && path.startsWith('/admin')) {
      return '/faculty/dashboard';
    }

    // Logged in as ADMIN trying to access FACULTY routes → redirect to their dashboard
    if (isAdmin && path.startsWith('/faculty')) {
      return '/admin/dashboard';
    }

    return null; // No redirect needed
  }

  static final GoRouter router = GoRouter(
    initialLocation: '/login',
    redirect: _redirect,
    routes: [
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
            builder: (context, state) => const FacultyDashboardScreen(),
          ),
          GoRoute(
            path: '/faculty/history',
            builder: (context, state) => const FacultyHistoryScreen(),
          ),
          GoRoute(
            path: '/faculty/notifications',
            builder: (context, state) => const FacultyNotificationsScreen(),
          ),
          GoRoute(
            path: '/faculty/device',
            builder: (context, state) => const FacultyDeviceScreen(),
          ),
          GoRoute(
            path: '/faculty/profile',
            builder: (context, state) => const FacultyProfileScreen(),
          ),
          GoRoute(
            path: '/faculty/reason-request',
            builder: (context, state) => const FacultyReasonRequestScreen(),
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
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/admin/faculty',
            builder: (context, state) {
              final status = state.uri.queryParameters['status'];
              return FacultyListScreen(filterStatus: status);
            },
          ),
          GoRoute(
            path: '/admin/attendance',
            builder: (context, state) => const AttendanceScreen(),
          ),
          GoRoute(
            path: '/admin/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/admin/logs',
            builder: (context, state) => const LogsScreen(),
          ),
          GoRoute(
            path: '/admin/requests',
            builder: (context, state) => const RequestsScreen(),
          ),
          GoRoute(
            path: '/admin/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          // Debug-only: Attendance Simulator (not shown in release builds)
          if (kDebugMode)
            GoRoute(
              path: '/admin/simulator',
              builder: (context, state) => const SimulatorScreen(),
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
