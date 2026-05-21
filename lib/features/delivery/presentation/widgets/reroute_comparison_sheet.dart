import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../data/models/route_result.dart';

class RerouteComparisonSheet extends StatelessWidget {
  final RouteResult currentRoute;
  final RouteResult alternativeRoute;
  final VoidCallback onConfirm;

  const RerouteComparisonSheet({
    super.key,
    required this.currentRoute,
    required this.alternativeRoute,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: AppSpacing.screenPaddingFull,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Comparativo de rotas', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.lg),
            _row('Atual', currentRoute),
            const SizedBox(height: AppSpacing.sm),
            _row('Alternativa', alternativeRoute),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: onConfirm,
                    child: const Text('Confirmar desvio'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, RouteResult route) {
    final minutes = (route.durationInTrafficSeconds / 60).round();
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.labelLarge)),
        Text('${route.distanceKm.toStringAsFixed(1)} km • $minutes min'),
        const SizedBox(width: AppSpacing.md),
        Text(CurrencyFormatter.format(route.tollCostBrl)),
      ],
    );
  }
}
