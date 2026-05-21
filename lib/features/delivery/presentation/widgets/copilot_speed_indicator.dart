import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';

class CopilotSpeedIndicator extends StatelessWidget {
  final double currentSpeed;
  final double expectedSpeed;
  final double ratio;

  const CopilotSpeedIndicator({
    super.key,
    required this.currentSpeed,
    required this.expectedSpeed,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    final color = ratio <= 0.85
        ? AppColors.warning
        : ratio < 1
        ? AppColors.info
        : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Velocidade', style: AppTypography.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${currentSpeed.toStringAsFixed(0)} / ${expectedSpeed.toStringAsFixed(0)} km/h',
            style: AppTypography.numericMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1.2) / 1.2,
              color: color,
              backgroundColor: AppColors.surfaceBorder,
            ),
          ),
        ],
      ),
    );
  }
}
