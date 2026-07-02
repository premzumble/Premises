import 'package:flutter/material.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_sizes.dart';

class AppLoadingState extends StatefulWidget {
  final int count;

  const AppLoadingState({
    super.key,
    this.count = 3,
  });

  @override
  State<AppLoadingState> createState() => _AppLoadingStateState();
}

class _AppLoadingStateState extends State<AppLoadingState> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color baseColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.count,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
            ),
          ),
          child: Row(
            children: [
              _buildShimmerBlock(width: 40, height: 40, isCircle: true, color: baseColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildShimmerBlock(width: 120, height: 14, color: baseColor),
                    const SizedBox(height: 8),
                    _buildShimmerBlock(width: 200, height: 10, color: baseColor),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _buildShimmerBlock(width: 60, height: 20, color: baseColor),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShimmerBlock({
    required double width,
    required double height,
    bool isCircle = false,
    required Color color,
  }) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: color,
              shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: isCircle ? null : BorderRadius.circular(4),
            ),
          ),
        );
      },
    );
  }
}
