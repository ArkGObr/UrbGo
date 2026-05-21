import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';

class TrafficBadge extends StatelessWidget {
  final double trafficRatio;

  const TrafficBadge({super.key, required this.trafficRatio});

  @override
  Widget build(BuildContext context) {
    final config = switch (trafficRatio) {
      > 1.35 => ('PESADO', AppColors.error),
      >= 1.15 => ('MODERADO', AppColors.warning),
      _ => ('LIVRE', AppColors.success),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: config.$2.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: config.$2.withValues(alpha: 0.35)),
      ),
      child: Text(
        config.$1,
        style: AppTypography.labelMedium.copyWith(
          color: config.$2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
