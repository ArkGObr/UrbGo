import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/services/dynamic_pricing_service.dart';
import '../../../core/utils/currency_formatter.dart';

class PricePreviewCard extends StatelessWidget {
  final VehicleCategoryInfo category;
  final double distanceKm;
  final double totalValue;
  final SurgeInfo? surgeInfo;

  const PricePreviewCard({
    super.key,
    required this.category,
    required this.distanceKm,
    required this.totalValue,
    this.surgeInfo,
  });

  @override
  Widget build(BuildContext context) {
    final surge = surgeInfo;
    final hasSurge = surge != null && surge.multiplier != 1.0;
    final totalLabel = category.isRide ? 'Corrida' : 'Total';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: hasSurge
              ? (surge.isSurge ? AppColors.warning.withValues(alpha: 0.5) : AppColors.primary.withValues(alpha: 0.4))
              : AppColors.surfaceBorder,
          width: hasSurge ? 1.2 : 0.8,
        ),
      ),
      padding: AppSpacing.cardPadding,
      child: Column(
        children: [
          Row(
            children: [
              Icon(category.icon, size: 20, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(category.name, style: AppTypography.h4),
              const Spacer(),
              Text(
                '${distanceKm.toStringAsFixed(1)} km',
                style: AppTypography.bodySmall,
              ),
            ],
          ),

          // Banner de preço dinâmico
          if (hasSurge) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: surge.isSurge
                    ? AppColors.warning.withValues(alpha: 0.12)
                    : AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Row(
                children: [
                  Icon(
                    surge.isSurge ? Icons.bolt_rounded : Icons.nights_stay_rounded,
                    size: 14,
                    color: surge.isSurge ? AppColors.warning : AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      surge.ruleName ?? (surge.isSurge ? 'Horário de pico' : 'Horário com desconto'),
                      style: AppTypography.labelSmall.copyWith(
                        color: surge.isSurge ? AppColors.warning : AppColors.primary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Text(
                    surge.label,
                    style: AppTypography.labelSmall.copyWith(
                      color: surge.isSurge ? AppColors.warning : AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],

          Divider(
            color: AppColors.surfaceBorder,
            height: AppSpacing.xl.toDouble(),
          ),
          Row(
            children: [
              Text(totalLabel, style: AppTypography.h4),
              const Spacer(),
              Text(
                CurrencyFormatter.format(totalValue),
                style: AppTypography.numericMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
