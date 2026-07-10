import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_sizes.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/session_manager.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/notification_service.dart';

class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({super.key});

  @override
  State<PermissionOnboardingScreen> createState() => _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState extends State<PermissionOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingStep> _steps = [
    OnboardingStep(
      title: 'Welcome to Premises',
      description: 'The smart workforce management and automated attendance platform for modern organizations.',
      icon: Icons.domain,
      buttonText: 'Get Started',
    ),
    OnboardingStep(
      title: 'Location Services',
      description: 'Premises uses high-accuracy geofencing to verify your presence on campus and automate your attendance. Location is only tracked during working hours.',
      icon: Icons.location_on_outlined,
      buttonText: 'Grant Location Access',
      action: () => LocationService.initialize(),
    ),
    OnboardingStep(
      title: 'Stay Informed',
      description: 'Receive real-time updates for check-in confirmation, campus boundary alerts, approval notifications, and administrative announcements.',
      icon: Icons.notifications_active_outlined,
      buttonText: 'Enable Notifications',
      action: () => NotificationService.requestPermissions(),
    ),
  ];

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      if (_steps[_currentPage].action != null) {
        _steps[_currentPage].action!();
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    await SessionManager.setPermissionsOnboarded();
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemCount: _steps.length,
                itemBuilder: (context, index) {
                  final step = _steps[index];
                  return Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(step.icon, size: 64, color: AppColors.primary),
                        ),
                        const SizedBox(height: 48),
                        Text(
                          step.title,
                          textAlign: TextAlign.center,
                          style: AppTypography.h1.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          step.description,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyLarge.copyWith(
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            
            // Bottom Bar
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_steps.length, (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index ? AppColors.primary : Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 32),
                  AppButton(
                    text: _steps[_currentPage].buttonText,
                    onPressed: _nextPage,
                  ),
                  if (_currentPage > 0)
                    TextButton(
                      onPressed: _completeOnboarding,
                      child: Text(
                        'Skip for now',
                        style: TextStyle(color: Colors.grey.shade500),
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

class OnboardingStep {
  final String title;
  final String description;
  final IconData icon;
  final String buttonText;
  final VoidCallback? action;

  OnboardingStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.buttonText,
    this.action,
  });
}
