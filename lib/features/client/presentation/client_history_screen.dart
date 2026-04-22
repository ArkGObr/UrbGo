import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/vehicle_badge.dart';
import '../domain/client_providers.dart';
import '../domain/delivery_model.dart';
import 'widgets/rating_bottom_sheet.dart';

class ClientHistoryScreen extends ConsumerStatefulWidget {
  const ClientHistoryScreen({super.key});

  @override
  ConsumerState<ClientHistoryScreen> createState() =>
      _ClientHistoryScreenState();
}

class _ClientHistoryScreenState extends ConsumerState<ClientHistoryScreen> {
  Future<void> _rate(DeliveryModel delivery) async {
    await RatingBottomSheet.show(context, ref, delivery);
    if (!mounted) return;
    ref.invalidate(clientRatingsProvider);
    ref.invalidate(clientHistoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(clientHistoryProvider);
    final ratingsAsync = ref.watch(clientRatingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Histórico de Entregas', style: AppTypography.h3),
        backgroundColor: AppColors.surface,
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.surfaceBorder),
        ),
      ),
      body: historyAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (_, __) => ErrorState(
          message: 'Erro ao carregar histórico',
          onRetry: () => ref.invalidate(clientHistoryProvider),
        ),
        data: (deliveries) {
          if (deliveries.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'Nenhuma entrega ainda',
              subtitle:
                  'Seu histórico de entregas concluídas aparecerá aqui.',
            );
          }

          final ratings = ratingsAsync.valueOrNull ?? {};

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(clientHistoryProvider);
              ref.invalidate(clientRatingsProvider);
            },
            color: AppColors.primary,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: deliveries.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                final d = deliveries[i];
                final userRating = ratings[d.id];
                return _HistoryCard(
                  delivery: d,
                  userRating: userRating,
                  onRate: d.status == DeliveryStatus.completed &&
                          userRating == null &&
                          d.motoboyId != null
                      ? () => _rate(d)
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ── Card de histórico ─────────────────────────────────────────
class _HistoryCard extends StatelessWidget {
  final DeliveryModel delivery;
  final int? userRating;
  final VoidCallback? onRate;

  static const _ratingLabels = [
    '',
    'Muito ruim',
    'Ruim',
    'Regular',
    'Bom',
    'Excelente',
  ];

  const _HistoryCard({
    required this.delivery,
    this.userRating,
    this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    // Local var para Dart poder promover int? → int em closures
    final rating = userRating;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Faixa lateral colorida por status
            Container(
              width: 4,
              color: delivery.status.color,
            ),
            // Conteúdo
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status + valor
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              _StatusBadge(status: delivery.status),
                              VehicleBadge(category: delivery.vehicleCategory),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          CurrencyFormatter.format(delivery.value),
                          style: AppTypography.numericMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Endereço de coleta
                    _AddressRow(
                      icon: Icons.radio_button_on_rounded,
                      iconColor: AppColors.primary,
                      address: delivery.pickupAddress,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 9),
                      child: Container(
                        width: 1.5,
                        height: 14,
                        color: AppColors.surfaceBorder,
                      ),
                    ),
                    // Endereço de entrega
                    _AddressRow(
                      icon: Icons.location_on_rounded,
                      iconColor: AppColors.error,
                      address: delivery.deliveryAddress,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Rodapé: entregador + pagamento + data
                    Row(
                      children: [
                        if (delivery.motoboyName != null) ...[
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 13,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              delivery.motoboyName!,
                              style: AppTypography.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else
                          const Spacer(),
                        Text(
                          _formatDate(delivery.createdAt),
                          style: AppTypography.bodySmall,
                        ),
                      ],
                    ),

                    // Seção de avaliação (apenas entregas concluídas)
                    if (delivery.status == DeliveryStatus.completed) ...[
                      const SizedBox(height: AppSpacing.sm),
                      const Divider(color: AppColors.surfaceBorder, height: 1),
                      const SizedBox(height: AppSpacing.sm),
                      if (rating != null)
                        // Já avaliado: mostra a nota que o cliente deu
                        Row(
                          children: [
                            ...List.generate(
                              5,
                              (i) => Icon(
                                i < rating
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 18,
                                color: i < rating
                                    ? const Color(0xFFFFC107)
                                    : AppColors.textTertiary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              _ratingLabels[rating],
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        )
                      else if (onRate != null)
                        // Ainda não avaliado: botão de avaliação
                        GestureDetector(
                          onTap: onRate,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xs),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_border_rounded,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  'Avaliar entregador',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min atrás';
    if (diff.inHours < 24) return '${diff.inHours}h atrás';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}

// ── Status Badge ──────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final DeliveryStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border:
            Border.all(color: status.color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 12, color: status.color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            status.label,
            style: AppTypography.labelSmall.copyWith(
              color: status.color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Address Row ───────────────────────────────────────────────
class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String address;

  const _AddressRow({
    required this.icon,
    required this.iconColor,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            address,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
