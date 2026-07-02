import 'package:flutter/material.dart';
import '../controller/walkthrough_controller.dart';

// ---------------------------------------------------------------------------
// WalkthroughNavigationHint
// ---------------------------------------------------------------------------

/// A floating animated banner that appears between tour phases to instruct
/// the admin which page to navigate to next.
///
/// Completely non-blocking — the user is free to click anywhere.
/// Listens to [WalkthroughController.showNavigationHint] and slides in/out
/// automatically.
///
/// Placement: Insert at the bottom of the admin body Stack in AdminNavigation.
class WalkthroughNavigationHint extends StatelessWidget {
  const WalkthroughNavigationHint({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = WalkthroughController.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: ctrl.showNavigationHint,
      builder: (context, show, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          transitionBuilder: (child, anim) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1.5),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: anim,
                curve: Curves.easeOutCubic,
              )),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: anim,
                  curve: Curves.easeIn,
                ),
                child: child,
              ),
            );
          },
          child: show
              ? ValueListenableBuilder<String>(
                  key: const ValueKey('hint_visible'),
                  valueListenable: ctrl.hintMessage,
                  builder: (context, message, _) =>
                      _HintBanner(message: message, onSkip: ctrl.skipTour),
                )
              : const SizedBox.shrink(key: ValueKey('hint_hidden')),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _HintBanner (internal)
// ---------------------------------------------------------------------------

class _HintBanner extends StatelessWidget {
  final String message;
  final VoidCallback onSkip;

  const _HintBanner({required this.message, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: RepaintBoundary(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F46E5).withOpacity(0.38),
                blurRadius: 22,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.navigation_outlined,
                  color: Colors.white,
                  size: 17,
                ),
              ),
              const SizedBox(width: 12),
              // Message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tour Guidance',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Skip button
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  backgroundColor: Colors.white.withOpacity(0.18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                child: const Text(
                  'Skip Tour',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
