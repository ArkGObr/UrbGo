import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';

class LiveMetricCounter extends StatelessWidget {
  final int value;
  final Animation<double> animation;

  const LiveMetricCounter({
    super.key,
    required this.value,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) => Opacity(
        opacity: animation.value,
        child: Column(
          children: [
            Text(
              'MINUTOS ECONOMIZADOS HOJE',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '$value',
              style: AppTypography.numericLarge.copyWith(
                fontSize: 72,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
