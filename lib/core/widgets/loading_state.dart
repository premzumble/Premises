import 'package:flutter/material.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_sizes.dart';

class AppLoadingState extends StatelessWidget {
  final int count;

  const AppLoadingState({
    super.key,
    this.count = 3,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color baseColor = isDark ? AppColors.borderDark : AppColors.borderLight;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
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
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.withOpacity(0.4),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(4),
      ),
    );
  }
}
