import 'package:shared_preferences/shared_preferences.dart';

/// Persistence layer for the admin onboarding walkthrough.
///
/// Stores two boolean flags:
///   - Completed: tour was finished or skipped — never show again automatically.
///   - First-login: welcome dialog has already been presented this installation.
class WalkthroughService {
  static const String _completedKey = 'admin_walkthrough_completed';
  static const String _firstLoginKey = 'admin_first_login_seen';

  // ─── Completed ────────────────────────────────────────────────────────────

  Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
  }

  // ─── First-Login ──────────────────────────────────────────────────────────

  /// Returns [true] if the welcome dialog has NOT yet been shown.
  Future<bool> isFirstLogin() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_firstLoginKey) ?? false);
  }

  /// Marks that the welcome dialog has been presented once.
  Future<void> markFirstLoginSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstLoginKey, true);
  }

  // ─── Reset (Replay) ───────────────────────────────────────────────────────

  /// Clears both flags so the full tour flow restarts on next login.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_completedKey);
    await prefs.remove(_firstLoginKey);
  }
}