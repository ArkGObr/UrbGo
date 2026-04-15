import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../shared/widgets/delivery_card.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../domain/motoboy_providers.dart';

class RunHistoryScreen extends ConsumerWidget {
  const RunHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(runHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Histórico de Corridas'),
        backgroundColor: AppColors.surface,
        centerTitle: true,
      ),
      body: historyAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, _) => ErrorState(
          message: err.toString(),
          onRetry: () => ref.invalidate(runHistoryProvider),
        ),
        data: (deliveries) {
          if (deliveries.isEmpty) {
            return const EmptyState(
              icon: Icons.history_rounded,
              title: 'Nenhuma corrida',
              subtitle: 'Você ainda não realizou nenhuma entrega.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(runHistoryProvider),
            color: AppColors.primary,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: deliveries.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) {
                final d = deliveries[i];
                return DeliveryCard(
                  delivery: d,
                  onTap: () {},
                );
              },
            ),
          );
        },
      ),
    );
  }
}
