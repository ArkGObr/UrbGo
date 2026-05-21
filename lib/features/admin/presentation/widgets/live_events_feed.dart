import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';

class LiveEventsFeed extends StatelessWidget {
  final List<Map<String, dynamic>> events;

  const LiveEventsFeed({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Eventos ao vivo', style: AppTypography.h4),
          const SizedBox(height: AppSpacing.md),
          for (final event in events.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                _formatEvent(event),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatEvent(Map<String, dynamic> event) {
    final createdAt = event['createdAt'] as String? ?? '';
    final time = createdAt.length >= 16 ? createdAt.substring(11, 16) : '--:--';
    final minutesSaved = event['minutesSaved'] ?? 0;
    final tollCost = event['tollCostBrl'] ?? 0;
    if ((tollCost as num).toDouble() > 0) {
      return '$time  --  Pedagio de R\$$tollCost calculado automaticamente';
    }
    return '$time  --  Corrida em ${event['area'] ?? 'zona urbana'} economizou $minutesSaved min com desvio sugerido';
  }
}
