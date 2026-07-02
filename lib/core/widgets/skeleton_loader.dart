import 'package:flutter/material.dart';

class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.35, end: 0.75).animate(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
          ),
        );
      },
    );
  }
}

class SkeletonCardList extends StatelessWidget {
  final int itemCount;
  final double height;

  const SkeletonCardList({
    super.key,
    this.itemCount = 3,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const SkeletonLoader(width: 44, height: 44, borderRadius: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SkeletonLoader(width: 140, height: 14, borderRadius: 4),
                      const SizedBox(height: 8),
                      const SkeletonLoader(width: 90, height: 10, borderRadius: 4),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                const SkeletonLoader(width: 64, height: 22, borderRadius: 11),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SkeletonGridLoader extends StatelessWidget {
  final int itemCount;

  const SkeletonGridLoader({
    super.key,
    this.itemCount = 6,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    int gridCount = width < 600 ? 1 : (width < 900 ? 2 : (width < 1200 ? 3 : 6));
    double childAspectRatio = width < 600 ? 3.0 : (width < 1200 ? 1.8 : 1.4);

    return GridView.count(
      crossAxisCount: gridCount,
      childAspectRatio: childAspectRatio,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(itemCount, (index) {
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SkeletonLoader(width: 70, height: 12, borderRadius: 4),
                    const SkeletonLoader(width: 16, height: 16, borderRadius: 8),
                  ],
                ),
                const SkeletonLoader(width: 50, height: 24, borderRadius: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SkeletonLoader(width: 100, height: 10, borderRadius: 3),
                    const SkeletonLoader(width: 32, height: 10, borderRadius: 3),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
