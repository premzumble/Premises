import 'package:flutter/material.dart';
import '../../../../core/design_system/app_colors.dart';

// ---------------------------------------------------------------------------
// WalkthroughCompletionDialog
// ---------------------------------------------------------------------------

/// Celebration dialog shown after the admin completes all 15 tour steps.
///
/// Displayed by AdminNavigation when [WalkthroughController.showCompletionCelebration]
/// becomes [true].
class WalkthroughCompletionDialog extends StatelessWidget {
  final VoidCallback onDismiss;

  const WalkthroughCompletionDialog({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 380,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 48,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias, // Bug 4 fix: Force children to respect the 24px radius
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Gradient top strip ────────────────────────────────────────
              Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
              ),

              // ── Content ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
                child: Column(
                  children: [
                    // Trophy icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        size: 44,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    const Text(
                      'Tour Complete!',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '🎉 Well done!',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description
                    const Text(
                      "You've completed the Premises onboarding tour. Your next step is to finish configuring Settings — especially the Campus Geofence — before registering faculty.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF475569),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Checklist reminders
                    _buildCheckItem('Complete Settings configuration'),
                    _buildCheckItem('Set your Campus Geofence boundary'),
                    _buildCheckItem('Add departments before faculty'),
                    _buildCheckItem('Approve faculty registrations'),

                    const SizedBox(height: 28),

                    // CTA button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onDismiss,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.rocket_launch_outlined, size: 18),
                            SizedBox(width: 8),
                            Text(
                              "Let's Get Started",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You can replay this tour anytime from the Help button (?) in the top bar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              size: 12,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}
