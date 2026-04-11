import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/utils/currency_formatter.dart';

class PricePreviewCard extends StatelessWidget {
  final VehicleCategoryInfo category;
  final double distanceKm;
  final double totalValue;

  const PricePreviewCard({
    super.key,
    required this.category,
    required this.distanceKm,
    required this.totalValue,
  });

  @override
  Widget build(BuildContext context) {
    final commission = PriceCalculator.commission(totalValue);
    final distanceCost = distanceKm * category.perKmRate;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceBorder, width: 0.8),
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
          Divider(
            color: AppColors.surfaceBorder,
            height: AppSpacing.xl.toDouble(),
          ),
          _PriceRow(
            'Taxa base',
            CurrencyFormatter.format(category.baseRate),
          ),
          const SizedBox(height: AppSpacing.xs),
          _PriceRow(
            '${distanceKm.toStringAsFixed(1)} km × '
            '${CurrencyFormatter.format(category.perKmRate)}',
            CurrencyFormatter.format(distanceCost),
          ),
          Divider(
            color: AppColors.surfaceBorder,
            height: AppSpacing.lg.toDouble(),
          ),
          Row(
            children: [
              Text('Total', style: AppTypography.h4),
              const Spacer(),
              Text(
                CurrencyFormatter.format(totalValue),
                style: AppTypography.numericMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 12,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                'Taxa de serviço UrbGo: ${CurrencyFormatter.format(commission)}',
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;

  const _PriceRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: AppTypography.bodySmall),
        ),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
