import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../client/domain/delivery_model.dart';
import 'micro_interactions.dart';
import 'vehicle_badge.dart';

class DeliveryCard extends StatelessWidget {
  final DeliveryModel delivery;
  final VoidCallback? onTap;
  final int index;
  final bool compact;
  final VoidCallback? onChatTap;

  const DeliveryCard({
    super.key,
    required this.delivery,
    this.onTap,
    this.index = 0,
    this.compact = false,
    this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    return StaggeredListItem(
      index: index,
      child: TapScale(
        onTap: onTap ?? () => context.push('/client/tracking/${delivery.id}'),
        child: Container(
          margin: EdgeInsets.only(bottom: compact ? 0 : AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Faixa lateral colorida por status
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: delivery.status.color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.md),
                      bottomLeft: Radius.circular(AppRadius.md),
                    ),
                  ),
                ),
                // Conteúdo
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(
                      compact ? AppSpacing.md : AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.xs,
                                children: [
                                  _StatusBadge(
                                    status: delivery.status,
                                    compact: compact,
                                  ),
                                  VehicleBadge(
                                    category: delivery.vehicleCategory,
                                  ),
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
                          compact: compact,
                        ),
                        _ConnectorLine(compact: compact),
                        if (delivery.extraStopAddress != null) ...[
                          _AddressRow(
                            icon: Icons.add_location_alt_rounded,
                            iconColor: const Color(0xFFFF9800),
                            address: delivery.extraStopAddress!,
                            compact: compact,
                          ),
                          _ConnectorLine(compact: compact),
                        ],
                        // Endereço de entrega
                        _AddressRow(
                          icon: Icons.location_on_rounded,
                          iconColor: AppColors.error,
                          address: delivery.deliveryAddress,
                          compact: compact,
                        ),
                        SizedBox(
                          height: compact ? AppSpacing.sm : AppSpacing.md,
                        ),

                        // Rodapé: pagamento + data
                        Row(
                          children: [
                            Icon(
                              delivery.paymentMethodIcon,
                              size: 14,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              delivery.paymentMethodLabel,
                              style: compact
                                  ? AppTypography.labelSmall
                                  : AppTypography.bodySmall,
                            ),
                            const Spacer(),
                            Text(
                              _formatDate(delivery.createdAt),
                              style: AppTypography.bodySmall,
                            ),
                          ],
                        ),
                        if (compact && onChatTap != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: onChatTap,
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 16,
                              ),
                              label: Text(
                                delivery.motoboyId == null
                                    ? 'Aguardando entregador'
                                    : 'Abrir chat',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: delivery.motoboyId == null
                                    ? AppColors.textTertiary
                                    : AppColors.primary,
                                side: BorderSide(
                                  color: delivery.motoboyId == null
                                      ? AppColors.surfaceBorder
                                      : AppColors.primary,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                textStyle: AppTypography.labelLarge.copyWith(
                                  fontSize: 13,
                                ),
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
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }
}

// ── Status Badge ──────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final DeliveryStatus status;
  final bool compact;

  const _StatusBadge({required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: compact ? 3 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
          color: status.color.withValues(alpha: 0.3),
          width: 0.5,
        ),
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
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Address Row ──────────────────────────────────────────────
class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String address;
  final bool compact;

  const _AddressRow({
    required this.icon,
    required this.iconColor,
    required this.address,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: compact ? 16 : 18, color: iconColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            address,
            style:
                (compact ? AppTypography.bodySmall : AppTypography.bodyMedium)
                    .copyWith(color: AppColors.textPrimary),
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ConnectorLine extends StatelessWidget {
  final bool compact;

  const _ConnectorLine({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 9),
      child: Container(
        width: 1.5,
        height: compact ? 10 : 16,
        color: AppColors.surfaceBorder,
      ),
    );
  }
}
