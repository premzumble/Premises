import 'package:flutter/material.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_sizes.dart';
import '../design_system/app_typography.dart';

class AppTable extends StatelessWidget {
  final List<String> headers;
  final List<List<Widget>> rows;
  final Function(int)? onRowTap;

  const AppTable({
    super.key,
    required this.headers,
    required this.rows,
    this.onRowTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Header
          Container(
            color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: headers
                  .map(
                    (header) => Expanded(
                      child: Text(
                        header,
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.borderLight),

          // Table Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              thickness: 1,
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            ),
            itemBuilder: (context, index) {
              final rowCells = rows[index];
              return _HoverableTableRow(
                cells: rowCells,
                onTap: onRowTap != null ? () => onRowTap!(index) : null,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HoverableTableRow extends StatefulWidget {
  final List<Widget> cells;
  final VoidCallback? onTap;

  const _HoverableTableRow({
    required this.cells,
    this.onTap,
  });

  @override
  State<_HoverableTableRow> createState() => _HoverableTableRowState();
}

class _HoverableTableRowState extends State<_HoverableTableRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color hoverColor = isDark 
        ? AppColors.backgroundDark.withOpacity(0.4) 
        : AppColors.backgroundLight.withOpacity(0.6);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: _isHovered ? hoverColor : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: widget.cells
                .map(
                  (cell) => Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: cell,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}
