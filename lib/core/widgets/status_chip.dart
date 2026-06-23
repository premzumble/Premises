import 'package:flutter/material.dart';
import '../design_system/app_colors.dart';

class StatusChip extends StatelessWidget {
  final String status;

  const StatusChip({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label = status.toUpperCase().replaceAll('_', ' ');

    switch (status.toUpperCase()) {
      case 'PRESENT':
      case 'ACTIVE':
      case 'APPROVED':
        bgColor = AppColors.success.withOpacity(0.12);
        textColor = AppColors.success;
        break;
      case 'ABSENT':
      case 'INACTIVE':
      case 'REJECTED':
        bgColor = AppColors.danger.withOpacity(0.12);
        textColor = AppColors.danger;
        break;
      case 'OUTSIDE':
      case 'TEMPORARILY_OUTSIDE':
      case 'OUTSIDE_CAMPUS':
        bgColor = AppColors.warning.withOpacity(0.12);
        textColor = AppColors.warning;
        label = 'OUTSIDE';
        break;
      case 'HALF_DAY':
      case 'PENDING':
      case 'PENDING_APPROVAL':
        bgColor = AppColors.info.withOpacity(0.12);
        textColor = AppColors.info;
        break;
      default:
        bgColor = Colors.grey.withOpacity(0.12);
        textColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
