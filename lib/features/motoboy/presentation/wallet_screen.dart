import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/motoboy_providers.dart';
import 'recharge_bottom_sheet.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final motoboyAsync = ref.watch(motoboyStreamProvider);
    final txAsync = ref.watch(transactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
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
        error: (e, _) => Center(
          child: Text('Erro: $e', style: AppTypography.bodyMedium),
        ),
        data: (motoboy) {
          return SingleChildScrollView(
            padding: AppSpacing.screenPaddingFull,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.lg),

                // ── Card de saldo ──────────────────────
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
                    crossAxisAlignment: CrossAxisAlignment.center,
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
                        style: AppTypography.numericHero.copyWith(
                          fontSize: 48,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl2),

                      // Botão recarregar
                      PrimaryButton(
                        label: 'Recarregar via PIX',
                        onPressed: () {
                          _showRechargeSheet(context, ref);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl3),

                // ── Histórico de transações ────────────
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
                    child: Text('Erro: $e',
                        style: AppTypography.bodyMedium),
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
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                  border: Border.all(
                                      color: AppColors.surfaceBorder),
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
                                style: AppTypography.bodyMedium
                                    .copyWith(
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
                          margin: const EdgeInsets.only(
                              bottom: AppSpacing.sm),
                          padding: AppSpacing.cardPadding,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                              color: AppColors.surfaceBorder,
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Ícone
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: tx.isCredit
                                      ? AppColors.primary
                                          .withValues(alpha: 0.15)
                                      : AppColors.error
                                          .withValues(alpha: 0.15),
                                  borderRadius:
                                      BorderRadius.circular(
                                          AppRadius.xs),
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
                              // Descrição
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                                        overflow:
                                            TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              // Valor
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${tx.isCredit ? '+' : ''}${CurrencyFormatter.format(tx.amount)}',
                                    style: AppTypography.numericMedium
                                        .copyWith(
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
