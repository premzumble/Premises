import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import '../services/walkthrough_service.dart';
import '../walkthrough_steps_definition.dart';

// ---------------------------------------------------------------------------
// Tour Phase
// ---------------------------------------------------------------------------

/// Tracks which phase of the multi-page walkthrough is currently active.
enum TourPhase {
  /// Tour not running.
  idle,

  /// startTour() called; waiting for DashboardScreen to render Phase 1 keys.
  pendingDashboard,

  /// Phase 1 active — KPI grid + Settings sidebar.
  dashboardIntro,

  /// Phase 1 complete; waiting for the user to navigate to Settings.
  awaitingSettings,

  /// Phase 2 active — Settings section tiles.
  settings,

  /// Phase 2 complete; Phase 3 starting — Management module sidebar items.
  dashboardModules,

  /// All phases done; tour marked complete.
  complete,
}

// ---------------------------------------------------------------------------
// WalkthroughController (Singleton)
// ---------------------------------------------------------------------------

/// Singleton that orchestrates the three-phase admin onboarding tour.
///
/// Architecture overview:
///   - AdminNavigation wraps its Scaffold with [ShowCaseWidget].
///   - A [Builder] inside that widget captures [_innerContext], which is the
///     only stable reference into the ShowCaseWidget subtree.
///   - Each phase is started by calling
///     [ShowCaseWidget.of(_innerContext!).startShowCase(keys)].
///   - Cross-page transitions show a [WalkthroughNavigationHint] overlay
///     and resume automatically when the target page renders.
///
/// **Nothing in this controller performs routing or forces navigation.**
class WalkthroughController {
  WalkthroughController._();

  /// The single shared instance used across the entire admin portal.
  static final WalkthroughController instance = WalkthroughController._();

  final WalkthroughService _service = WalkthroughService();

  // ─── Internal State ───────────────────────────────────────────────────────

  TourPhase _phase = TourPhase.idle;
  TourPhase get phase => _phase;

  bool _isSkipping = false;

  /// Stable context captured from the [Builder] inside [ShowCaseWidget].
  /// Used to call [ShowCaseWidget.of(_innerContext!).next()] etc. from anywhere.
  BuildContext? _innerContext;

  // ─── Reactive Notifiers ───────────────────────────────────────────────────

  /// Drives [WalkthroughNavigationHint] banner visibility.
  final ValueNotifier<bool> showNavigationHint = ValueNotifier(false);

  /// Message displayed in the navigation hint banner.
  final ValueNotifier<String> hintMessage = ValueNotifier('');

  /// Set to [true] when the final phase completes; AdminNavigation listens
  /// to this to show the completion celebration dialog.
  final ValueNotifier<bool> showCompletionCelebration = ValueNotifier(false);

  /// Whether the tour is currently in an active showcasing phase.
  final ValueNotifier<bool> isActive = ValueNotifier(false);

  // ─── Context Management ───────────────────────────────────────────────────

  /// Called by the [Builder] inside [ShowCaseWidget] in AdminNavigation to
  /// register the stable inner context. Must be called before [startTour].
  void attachContext(BuildContext ctx) {
    _innerContext = ctx;
  }

  // ─── Persistence Wrappers ─────────────────────────────────────────────────

  Future<bool> shouldShowWalkthrough() async =>
      !(await _service.isCompleted());

  Future<bool> isFirstLogin() async => _service.isFirstLogin();

  Future<void> markFirstLoginSeen() async => _service.markFirstLoginSeen();

  /// Clears persistence so the tour can be replayed from the help button.
  Future<void> resetWalkthrough() async {
    _phase = TourPhase.idle;
    _isSkipping = false;
    isActive.value = false;
    showNavigationHint.value = false;
    showCompletionCelebration.value = false;
    await _service.reset();
  }

  // ─── Tour Lifecycle ───────────────────────────────────────────────────────

  /// Starts the tour. Sets [pendingDashboard] phase and shows a navigation
  /// hint if the user is not yet on the Dashboard page. DashboardScreen calls
  /// [onDashboardReady] in its post-frame callback to launch Phase 1.
  void startTour() {
    _phase = TourPhase.pendingDashboard;
    _isSkipping = false;
    isActive.value = true;
    showNavigationHint.value = false;
    showCompletionCelebration.value = false;
    // Show guidance hint; Dashboard dismisses it when it's ready.
    hintMessage.value =
        'Navigate to the Dashboard to begin your tour.';
    showNavigationHint.value = true;
  }

  /// Marks the tour as permanently declined (skip on welcome dialog).
  void declineTour() {
    _phase = TourPhase.complete;
    isActive.value = false;
    _service.markCompleted(); // fire-and-forget
  }

  // ─── Page-Ready Callbacks ─────────────────────────────────────────────────

  /// Called by [DashboardScreen] in its post-frame callback.
  /// Starts Phase 1 if the tour is pending dashboard readiness.
  void onDashboardReady(BuildContext context) {
    if (_phase != TourPhase.pendingDashboard) return;
    _phase = TourPhase.dashboardIntro;
    showNavigationHint.value = false;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_innerContext != null && _innerContext!.mounted) {
        ShowCaseWidget.of(_innerContext!)
            .startShowCase(WalkthroughTourData.phase1Keys);
      }
    });
  }

  /// Called by [SettingsScreen] in its post-frame callback.
  /// Starts Phase 2 when the user navigates to Settings during [awaitingSettings].
  void onSettingsReady(BuildContext settingsContext) {
    if (_phase != TourPhase.awaitingSettings) return;
    _phase = TourPhase.settings;
    showNavigationHint.value = false;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (settingsContext.mounted) {
        ShowCaseWidget.of(settingsContext)
            .startShowCase(WalkthroughTourData.phase2Keys);
      }
    });
  }

  // ─── ShowCaseWidget Callbacks ─────────────────────────────────────────────

  /// Registered as [ShowCaseWidget.onFinish].
  /// Called by the library when the last step of the current [startShowCase]
  /// list is completed — i.e., at the end of each phase.
  void onPhaseFinished() {
    if (_isSkipping) {
      _isSkipping = false;
      return;
    }

    switch (_phase) {
      case TourPhase.dashboardIntro:
        // Phase 1 done → guide user to open Settings.
        _phase = TourPhase.awaitingSettings;
        hintMessage.value =
            'Great start!  Open  ⚙️ Settings  from the sidebar to continue your tour.';
        showNavigationHint.value = true;
        break;

      case TourPhase.settings:
        // Phase 2 done → start Phase 3 immediately (sidebar always rendered).
        _phase = TourPhase.dashboardModules;
        showNavigationHint.value = false;
        Future.delayed(const Duration(milliseconds: 350), () {
          if (_innerContext != null && _innerContext!.mounted) {
            ShowCaseWidget.of(_innerContext!)
                .startShowCase(WalkthroughTourData.phase3Keys);
          }
        });
        break;

      case TourPhase.dashboardModules:
        // Phase 3 done → tour complete.
        _completeAndCelebrate();
        break;

      default:
        break;
    }
  }

  // ─── Navigation Actions (called from tooltip buttons) ─────────────────────

  /// Advance to the next showcase step.
  void next() {
    if (_innerContext != null && _innerContext!.mounted) {
      ShowCaseWidget.of(_innerContext!).next();
    }
  }

  /// Go back to the previous showcase step within the current phase.
  void previous() {
    if (_innerContext != null && _innerContext!.mounted) {
      ShowCaseWidget.of(_innerContext!).previous();
    }
  }

  /// Immediately exits the tour, marks as complete, and closes the overlay.
  void skipTour() {
    _isSkipping = true;
    _phase = TourPhase.complete;
    isActive.value = false;
    showNavigationHint.value = false;
    _service.markCompleted(); // fire-and-forget
    // Start an empty showcase list to dismiss the active overlay.
    if (_innerContext != null && _innerContext!.mounted) {
      try {
        ShowCaseWidget.of(_innerContext!).startShowCase(const []);
      } catch (_) {}
    }
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  void _completeAndCelebrate() {
    _phase = TourPhase.complete;
    isActive.value = false;
    showNavigationHint.value = false;
    _service.markCompleted(); // fire-and-forget
    showCompletionCelebration.value = true;
  }
}