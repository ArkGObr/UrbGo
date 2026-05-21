import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../services/copilot_settings.dart';

class CopilotSettingsSheet extends ConsumerWidget {
  const CopilotSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(copilotSettingsProvider);
    return SafeArea(
      child: Padding(
        padding: AppSpacing.screenPaddingFull,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Configurações do copiloto', style: AppTypography.h3),
            SwitchListTile(
              value: settings.audioEnabled,
              onChanged: (value) => ref
                  .read(copilotSettingsProvider.notifier)
                  .update(settings.copyWith(audioEnabled: value)),
              title: const Text('Áudio dos alertas'),
            ),
            SwitchListTile(
              value: settings.notificationsEnabled,
              onChanged: (value) => ref
                  .read(copilotSettingsProvider.notifier)
                  .update(settings.copyWith(notificationsEnabled: value)),
              title: const Text('Notificações'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Economia mínima: ${settings.minimumTimeSavingMinutes} min',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            Slider(
              min: 1,
              max: 10,
              divisions: 9,
              value: settings.minimumTimeSavingMinutes.toDouble(),
              onChanged: (value) => ref
                  .read(copilotSettingsProvider.notifier)
                  .update(
                    settings.copyWith(minimumTimeSavingMinutes: value.round()),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
