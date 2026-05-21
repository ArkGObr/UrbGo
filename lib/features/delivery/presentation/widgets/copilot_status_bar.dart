import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../services/copilot_state.dart';

class CopilotStatusBar extends StatelessWidget {
  final CopilotState state;
  final VoidCallback onSeeReroute;
  final VoidCallback onIgnore;

  const CopilotStatusBar({
    super.key,
    required this.state,
    required this.onSeeReroute,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final isAlert = state.status == CopilotUiStatus.alert;
    final isAccepted = state.status == CopilotUiStatus.rerouteAccepted;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isAlert
            ? const Color(0xFFFFA726)
            : isAccepted
            ? AppColors.primaryDeep
            : const Color(0xFF134E4A),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: isAlert
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.alertMessage ?? 'Desvio sugerido',
                  style: AppTypography.h4.copyWith(
                    color: AppColors.textInverse,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Economize ${state.timeSavedMinutes} min com o desvio sugerido',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textInverse,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onIgnore,
                        child: const Text('Ignorar'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: onSeeReroute,
                        child: const Text('Ver desvio no mapa'),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Icon(
                  isAccepted ? Icons.check_circle : Icons.radar_rounded,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    isAccepted
                        ? 'Rota atualizada!'
                        : 'Monitorando • ${state.currentSpeedKmh.toStringAsFixed(0)} km/h',
                    style: AppTypography.labelLarge,
                  ),
                ),
              ],
            ),
    );
  }
}
