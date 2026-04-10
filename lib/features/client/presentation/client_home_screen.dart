import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../auth/domain/auth_provider.dart';
import '../../shared/widgets/delivery_card.dart';
import '../domain/client_providers.dart';

class ClientHomeScreen extends ConsumerWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesAsync = ref.watch(clientDeliveriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              width: 36,
              height: 36,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: AppSpacing.sm),
            RichText(
              text: TextSpan(
                style: AppTypography.h2,
                children: [
                  const TextSpan(text: 'Urb'),
                  TextSpan(
                    text: 'Go',
                    style: AppTypography.h2.copyWith(color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
            tooltip: 'Sair',
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).signOut();
            },
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      floatingActionButton: Container(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGlow,
              blurRadius: 20,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => context.push('/client/create'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textInverse,
          elevation: 0,
          icon: const Icon(Icons.add_rounded),
          label: Text(
            'Nova Entrega',
            style: AppTypography.buttonSmall.copyWith(
              color: AppColors.textInverse,
            ),
          ),
        ),
      ),
      body: deliveriesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
        error: (e, _) => _ErrorState(
          onRetry: () => ref.invalidate(clientDeliveriesProvider),
          e: e,
        ),
        data: (deliveries) {
          if (deliveries.isEmpty) {
            return const _EmptyState();
          }

          // Separar ativas e histórico
          final active = deliveries.where((d) => d.isActive).toList();
          final history = deliveries.where((d) => !d.isActive).toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(clientDeliveriesProvider);
              await ref.read(clientDeliveriesProvider.future);
            },
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: ListView(
              padding: AppSpacing.screenPaddingFull,
              children: [
                // Entregas ativas
                if (active.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Em andamento',
                    count: active.length,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...active.map((d) => DeliveryCard(delivery: d)),
                  const SizedBox(height: AppSpacing.xl2),
                ],

                // Histórico
                if (history.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Histórico',
                    count: history.length,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...history.map((d) => DeliveryCard(delivery: d)),
                ],

                // Espaço para FAB
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: AppTypography.h3),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            '$count',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.primary,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Empty State ───────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: const Icon(
                Icons.two_wheeler_rounded,
                color: AppColors.textTertiary,
                size: 40,
              ),
            ),
            const SizedBox(height: AppSpacing.xl2),
            Text(
              'Nenhuma entrega ainda',
              style: AppTypography.h3.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Toque no botão abaixo para\ncriar seu primeiro pedido',
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error State ───────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final Object e;

  const _ErrorState({required this.onRetry, required this.e});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 48,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Erro: ${e.toString()}',
              style: AppTypography.h4.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl2),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
              label: Text(
                'Tentar novamente',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
