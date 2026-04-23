import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/earnings_dashboard.dart';
import '../domain/motoboy_providers.dart';
import 'recharge_bottom_sheet.dart';

enum _EarningsRange { daily, weekly, monthly }

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  _EarningsRange _range = _EarningsRange.daily;

  @override
  Widget build(BuildContext context) {
    final motoboyAsync = ref.watch(motoboyStreamProvider);
    final txAsync = ref.watch(transactionsProvider);
    final earningsAsync = ref.watch(earningsDashboardProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text('Minha Carteira', style: AppTypography.h3),
      ),
      body: motoboyAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
        error: (e, _) =>
            Center(child: Text('Erro: $e', style: AppTypography.bodyMedium)),
        data: (motoboy) {
          return SingleChildScrollView(
            padding: AppSpacing.screenPaddingFull,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.lg),
                Container(
                  width: double.infinity,
                  padding: AppSpacing.cardPaddingLarge,
                  decoration: BoxDecoration(
                    color: AppColors.primaryDeep,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Saldo disponível',
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.primary.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        CurrencyFormatter.format(motoboy.walletBalance),
                        style: AppTypography.numericHero.copyWith(fontSize: 48),
                      ),
                      const SizedBox(height: AppSpacing.xl2),
                      PrimaryButton(
                        label: 'Recarregar saldo',
                        onPressed: () => _showRechargeSheet(context, ref),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl3),
                Text('Dashboard de ganhos', style: AppTypography.h3),
                const SizedBox(height: AppSpacing.md),
                earningsAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                  error: (e, _) => Text('Erro ao carregar ganhos: $e'),
                  data: (dashboard) => _buildDashboard(dashboard),
                ),
                const SizedBox(height: AppSpacing.xl3),
                Text('Histórico', style: AppTypography.h3),
                const SizedBox(height: AppSpacing.lg),
                txAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  ),
                  error: (e, _) => Center(
                    child: Text('Erro: $e', style: AppTypography.bodyMedium),
                  ),
                  data: (transactions) {
                    if (transactions.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl3),
                          child: Column(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.lg,
                                  ),
                                  border: Border.all(
                                    color: AppColors.surfaceBorder,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.receipt_long_outlined,
                                  color: AppColors.textTertiary,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                'Nenhuma transação ainda',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: transactions.map((tx) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          padding: AppSpacing.cardPadding,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                              color: AppColors.surfaceBorder,
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: tx.isCredit
                                      ? AppColors.primary.withValues(
                                          alpha: 0.15,
                                        )
                                      : AppColors.error.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.xs,
                                  ),
                                ),
                                child: Icon(
                                  tx.isCredit
                                      ? Icons.add_circle_rounded
                                      : Icons.remove_circle_rounded,
                                  color: tx.isCredit
                                      ? AppColors.primary
                                      : AppColors.error,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tx.typeLabel,
                                      style: AppTypography.labelLarge,
                                    ),
                                    if (tx.description != null)
                                      Text(
                                        tx.description!,
                                        style: AppTypography.bodySmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${tx.isCredit ? '+' : ''}${CurrencyFormatter.format(tx.amount)}',
                                    style: AppTypography.numericMedium.copyWith(
                                      color: tx.isCredit
                                          ? AppColors.primary
                                          : AppColors.error,
                                    ),
                                  ),
                                  Text(
                                    _formatDate(tx.createdAt),
                                    style: AppTypography.bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xl4),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDashboard(EarningsDashboard dashboard) {
    final points = switch (_range) {
      _EarningsRange.daily => dashboard.dailyPoints,
      _EarningsRange.weekly => dashboard.weeklyPoints,
      _EarningsRange.monthly => dashboard.monthlyPoints,
    };

    return Container(
      padding: AppSpacing.cardPaddingLarge,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Hoje',
                  value: dashboard.today,
                  highlighted: _range == _EarningsRange.daily,
                  onTap: () => setState(() => _range = _EarningsRange.daily),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MetricCard(
                  label: '7 dias',
                  value: dashboard.week,
                  highlighted: _range == _EarningsRange.weekly,
                  onTap: () => setState(() => _range = _EarningsRange.weekly),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MetricCard(
                  label: '30 dias',
                  value: dashboard.month,
                  highlighted: _range == _EarningsRange.monthly,
                  onTap: () => setState(() => _range = _EarningsRange.monthly),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl2),
          Text('Tendência', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.md),
          SizedBox(height: 180, child: _EarningsChart(points: points)),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showRechargeSheet(BuildContext context, WidgetRef ref) {
    final user = ref.read(authNotifierProvider).valueOrNull;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RechargeBottomSheet(motoboyId: user.id),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final double value;
  final bool highlighted;
  final VoidCallback onTap;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: highlighted ? AppColors.primaryDeep : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: highlighted ? AppColors.primary : AppColors.surfaceBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.labelSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              CurrencyFormatter.format(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.numericMedium.copyWith(
                color: highlighted ? AppColors.primary : AppColors.textPrimary,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EarningsChart extends StatelessWidget {
  final List<EarningsPoint> points;

  const _EarningsChart({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
        child: Text(
          'Sem entregas suficientes para montar o gráfico ainda.',
          style: AppTypography.bodySmall,
          textAlign: TextAlign.center,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final point in points)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: math.max(
                          8,
                          (point.value /
                                  _maxValue(points).clamp(1, double.infinity)) *
                              120,
                        ),
                        decoration: BoxDecoration(
                          color: point.value > 0
                              ? AppColors.primary
                              : AppColors.surfaceBorder,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    point.label,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  double _maxValue(List<EarningsPoint> data) {
    return data.fold<double>(
      0,
      (max, item) => item.value > max ? item.value : max,
    );
  }
}
