import 'package:flutter/material.dart';
import '../../../../core/design_system/app_colors.dart';
import '../controller/walkthrough_controller.dart';

// ---------------------------------------------------------------------------
// WalkthroughTooltip
// ---------------------------------------------------------------------------

/// Custom tooltip content rendered inside each [Showcase] overlay.
///
/// Displays:
///   - Gradient header with icon + title + step counter badge
///   - Descriptive body text
///   - Optional call-to-action hint
///   - Linear progress bar
///   - Navigation buttons: [Skip] · [← Prev] · [Next → / ✓ Finish]
///
/// Communicates with [WalkthroughController.instance] to advance/retreat/skip.
class WalkthroughTooltip extends StatelessWidget {
  /// 1-based global step number (out of [WalkthroughTourData.totalSteps]).
  final int stepNumber;

  /// Short bold title shown in the gradient header.
  final String title;

  /// Main explanatory text shown below the header.
  final String body;

  /// Icon displayed in the header icon badge.
  final IconData icon;

  /// When [true], the Previous button is hidden (first step of its phase).
  final bool isFirstInPhase;

  /// When [true], the Next button label changes to "✓ Finish".
  final bool isLastGlobally;

  /// Optional secondary tip shown in a highlighted info box.
  final String? callToAction;

  const WalkthroughTooltip({
    super.key,
    required this.stepNumber,
    required this.title,
    required this.body,
    required this.icon,
    this.isFirstInPhase = false,
    this.isLastGlobally = false,
    this.callToAction,
  });

  static const int _total = 15;

  @override
  Widget build(BuildContext context) {
    final ctrl = WalkthroughController.instance;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 292,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F46E5).withOpacity(0.18),
              blurRadius: 36,
              spreadRadius: -4,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Gradient header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon badge
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 15, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  // Title
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Step counter badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$stepNumber / $_total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(
                body,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF475569),
                  height: 1.6,
                ),
              ),
            ),

            // ── Call-to-action tip ───────────────────────────────────────────
            if (callToAction != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.14)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.tips_and_updates_outlined,
                          size: 13, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          callToAction!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Progress bar ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: stepNumber / _total,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF4F46E5),
                      ),
                      minHeight: 3,
                    ),
                  ),
                ],
              ),
            ),

            // ── Action buttons ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              child: Row(
                children: [
                  // Skip Tour
                  TextButton(
                    onPressed: ctrl.skipTour,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Previous button (only when not first in phase)
                  if (!isFirstInPhase) ...[
                    OutlinedButton(
                      onPressed: ctrl.previous,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: const BorderSide(
                          color: Color(0xFFE2E8F0),
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '← Prev',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  // Next / Finish button
                  ElevatedButton(
                    onPressed: ctrl.next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLastGlobally
                          ? AppColors.success
                          : AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      isLastGlobally ? '✓ Finish' : 'Next →',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
