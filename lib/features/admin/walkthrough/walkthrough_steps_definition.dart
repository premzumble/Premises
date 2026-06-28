import 'package:flutter/material.dart';

/// Central registry of all [GlobalKey]s used in the admin onboarding tour.
///
/// Keys are [static final] so they are instantiated once and shared across
/// every widget that references them (AdminNavigation sidebar items,
/// SettingsScreen section tiles, DashboardScreen KPI grid).
///
/// Tour order (15 steps total):
///   Phase 1 — Dashboard Intro  : Steps  1–2
///   Phase 2 — Settings          : Steps  3–10
///   Phase 3 — Module Navigation : Steps 11–15
class WalkthroughKeys {
  WalkthroughKeys._();

  // ─── Phase 1: Dashboard Intro (Steps 1–2) ────────────────────────────────
  /// Step 1 — KPI Stats grid on the Dashboard content area.
  static final GlobalKey kpiGrid =
      GlobalKey(debugLabel: 'wt_kpi_grid');

  /// Step 2 — Settings item in the admin sidebar.
  static final GlobalKey sidebarSettings =
      GlobalKey(debugLabel: 'wt_sidebar_settings');

  // ─── Phase 2: Settings Sections (Steps 3–10) ─────────────────────────────
  /// Step 3 — General configuration section tile.
  static final GlobalKey settingsGeneral =
      GlobalKey(debugLabel: 'wt_settings_general');

  /// Step 4 — Departments section tile.
  static final GlobalKey settingsDepartments =
      GlobalKey(debugLabel: 'wt_settings_departments');

  /// Step 5 — Working Hours section tile.
  static final GlobalKey settingsWorkingHours =
      GlobalKey(debugLabel: 'wt_settings_hours');

  /// Step 6 — Attendance Policy section tile.
  static final GlobalKey settingsAttendancePolicy =
      GlobalKey(debugLabel: 'wt_settings_policy');

  /// Step 7 — Campus Geofence section tile.
  static final GlobalKey settingsGeofence =
      GlobalKey(debugLabel: 'wt_settings_geofence');

  /// Step 8 — Security section tile.
  static final GlobalKey settingsSecurity =
      GlobalKey(debugLabel: 'wt_settings_security');

  /// Step 9 — Notifications section tile.
  static final GlobalKey settingsNotifications =
      GlobalKey(debugLabel: 'wt_settings_notifications');

  /// Step 10 — Account section tile.
  static final GlobalKey settingsAccount =
      GlobalKey(debugLabel: 'wt_settings_account');

  // ─── Phase 3: Management Modules (Steps 11–15) ───────────────────────────
  /// Step 11 — Faculty sidebar navigation item.
  static final GlobalKey sidebarFaculty =
      GlobalKey(debugLabel: 'wt_sidebar_faculty');

  /// Step 12 — Attendance sidebar navigation item.
  static final GlobalKey sidebarAttendance =
      GlobalKey(debugLabel: 'wt_sidebar_attendance');

  /// Step 13 — Reports sidebar navigation item.
  static final GlobalKey sidebarReports =
      GlobalKey(debugLabel: 'wt_sidebar_reports');

  /// Step 14 — Requests sidebar navigation item.
  static final GlobalKey sidebarRequests =
      GlobalKey(debugLabel: 'wt_sidebar_requests');

  /// Step 15 — Logs sidebar navigation item (last step in the tour).
  static final GlobalKey sidebarLogs =
      GlobalKey(debugLabel: 'wt_sidebar_logs');
}

/// Convenience accessor for phase key lists passed to
/// [ShowCaseWidget.of(context).startShowCase()].
class WalkthroughTourData {
  WalkthroughTourData._();

  /// Total number of steps across all three phases.
  static const int totalSteps = 15;

  /// Phase 1 keys (Steps 1–2). Requires Dashboard to be rendered.
  static List<GlobalKey> get phase1Keys => [
        WalkthroughKeys.kpiGrid,
        WalkthroughKeys.sidebarSettings,
      ];

  /// Phase 2 keys (Steps 3–10). Requires SettingsScreen to be rendered.
  static List<GlobalKey> get phase2Keys => [
        WalkthroughKeys.settingsGeneral,
        WalkthroughKeys.settingsDepartments,
        WalkthroughKeys.settingsWorkingHours,
        WalkthroughKeys.settingsAttendancePolicy,
        WalkthroughKeys.settingsGeofence,
        WalkthroughKeys.settingsSecurity,
        WalkthroughKeys.settingsNotifications,
        WalkthroughKeys.settingsAccount,
      ];

  /// Phase 3 keys (Steps 11–15). Sidebar items always rendered by AdminNavigation.
  static List<GlobalKey> get phase3Keys => [
        WalkthroughKeys.sidebarFaculty,
        WalkthroughKeys.sidebarAttendance,
        WalkthroughKeys.sidebarReports,
        WalkthroughKeys.sidebarRequests,
        WalkthroughKeys.sidebarLogs,
      ];

  /// 1-based global step number for the first step in each phase.
  static const int phase1Offset = 1; // steps 1–2
  static const int phase2Offset = 3; // steps 3–10
  static const int phase3Offset = 11; // steps 11–15
}
