import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/fare_breakdown.dart';

class FareBreakdownCard extends StatelessWidget {
  final FareBreakdown breakdown;

  const FareBreakdownCard({super.key, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        children: [
          _row('Tarifa base', breakdown.baseFare),
          const SizedBox(height: AppSpacing.sm),
          _row('Adicional de trafego', breakdown.trafficSurcharge),
          if (breakdown.returnTripFee > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            _row('Retorno (50%)', breakdown.returnTripFee),
          ],
          const SizedBox(height: AppSpacing.sm),
          _row('Pedagio', breakdown.tollCost),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(height: 1),
          ),
          _row('Total', breakdown.totalFare, emphasize: true),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              breakdown.trafficRatioDisplay,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, double value, {bool emphasize = false}) {
    final style = emphasize ? AppTypography.h4 : AppTypography.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(
          CurrencyFormatter.format(value),
          style: style.copyWith(
            color: emphasize ? AppColors.primary : AppColors.textPrimary,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
