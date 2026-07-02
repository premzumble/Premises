import 'dart:async';
import 'package:flutter/material.dart';
import '../design_system/app_colors.dart';

class PremisesBrandedLoader extends StatefulWidget {
  final double size;
  final bool isFullScreen;

  const PremisesBrandedLoader({
    super.key,
    this.size = 80,
    this.isFullScreen = false,
  });

  @override
  State<PremisesBrandedLoader> createState() => _PremisesBrandedLoaderState();
}

class _PremisesBrandedLoaderState extends State<PremisesBrandedLoader>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _rotationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _rotationAnimation;
  bool _showLoader = false;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 0.90, end: 1.05).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _rotationController,
        curve: Curves.linear,
      ),
    );

    _delayTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() {
          _showLoader = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showLoader) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget loader = Center(
      child: RepaintBoundary(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Rotating outer brand ring
            RotationTransition(
              turns: _rotationAnimation,
              child: Container(
                width: widget.size + 16,
                height: widget.size + 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border(
                    top: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 2.5,
                    ),
                    right: BorderSide(
                      color: theme.colorScheme.primary.withOpacity(0.2),
                      width: 2.5,
                    ),
                    bottom: BorderSide(
                      color: theme.colorScheme.primary.withOpacity(0.2),
                      width: 2.5,
                    ),
                    left: BorderSide(
                      color: theme.colorScheme.primary.withOpacity(0.2),
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            ),
            // Pulsing central logo card
            FadeTransition(
              opacity: _opacityAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  padding: EdgeInsets.all(widget.size * 0.22),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.isFullScreen) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: loader,
      );
    }

    return loader;
  }
}
