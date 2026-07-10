import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'routes/app_router.dart';
import 'core/session_manager.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Restore session (Auth state) first so GoRouter can evaluate redirects correctly on page refresh
  try {
    await SessionManager.restore();
  } catch (_) {}

  // 2. Initial Local Theme Restore (Sync to prevent flickering)
  ThemeMode initialTheme = ThemeMode.light;
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('theme_mode');
    if (savedTheme == 'dark') {
      initialTheme = ThemeMode.dark;
    }
    themeNotifier.value = initialTheme;
  } catch (_) {}

  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Premises',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light, // Kept static to avoid router teardowns on theme toggle
      routerConfig: AppRouter.router,
      builder: (context, child) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (context, currentMode, _) {
            return ThemeSwitcher(
              themeMode: currentMode,
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}

// ── High-Performance Single-Layer Theme Overlay Crossfade Switcher ───────────
class ThemeSwitcher extends StatefulWidget {
  final Widget child;
  final ThemeMode themeMode;

  const ThemeSwitcher({
    super.key,
    required this.child,
    required this.themeMode,
  });

  @override
  State<ThemeSwitcher> createState() => _ThemeSwitcherState();
}

class _ThemeSwitcherState extends State<ThemeSwitcher> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  Color? _overlayColor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(ThemeSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.themeMode != oldWidget.themeMode) {
      // Capture the old theme background color to use as the fading overlay
      _overlayColor = oldWidget.themeMode == ThemeMode.dark
          ? const Color(0xFF09090B) // Deep Zinc background for dark
          : const Color(0xFFF9F9F6); // Warm Linen background for light
      
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeMode == ThemeMode.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme;

    return Theme(
      data: theme,
      child: Stack(
        children: [
          // Underlying view (instantly rebuilt under the new theme)
          widget.child,
          // Overlaid solid color layer that fades out to reveal the new theme
          AnimatedBuilder(
            animation: _opacityAnimation,
            builder: (context, child) {
              final opacity = _opacityAnimation.value;
              if (opacity <= 0.0 || _overlayColor == null) {
                return const SizedBox.shrink();
              }
              return Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      color: _overlayColor,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
