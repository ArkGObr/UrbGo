import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../client/domain/delivery_model.dart';
import '../../shared/widgets/micro_interactions.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/vehicle_badge.dart';
import '../data/motoboy_repository.dart';
import '../domain/motoboy_providers.dart';

class AvailableRunsScreen extends ConsumerStatefulWidget {
  const AvailableRunsScreen({super.key});

  @override
  ConsumerState<AvailableRunsScreen> createState() =>
      _AvailableRunsScreenState();
}

class _AvailableRunsScreenState extends ConsumerState<AvailableRunsScreen> {
  bool _isAccepting = false;
  String? _acceptingId;

  Future<void> _acceptRun(DeliveryModel delivery) async {
    final user = ref.read(authNotifierProvider).valueOrNull;
    if (user == null) return;

    setState(() {
      _isAccepting = true;
      _acceptingId = delivery.id;
    });

    try {
      await ref.read(motoboyRepositoryProvider).acceptDelivery(
            deliveryId: delivery.id,
            motoboyId: user.id,
            commission: delivery.commission,
          );
      if (mounted) {
        context.go('/motoboy/active/${delivery.id}');
      }
    } on InsufficientBalanceException catch (e) {
      if (mounted) _showInsufficientBalanceSheet(e.message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    e.toString(),
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              side: const BorderSide(color: AppColors.error, width: 1),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
          _acceptingId = null;
        });
      }
    }
  }

  void _showInsufficientBalanceSheet(String message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            const SizedBox(height: AppSpacing.xl3),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                color: AppColors.warning,
                size: 32,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Saldo Insuficiente', style: AppTypography.h2),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl3),
            PrimaryButton(
              label: 'Recarregar agora',
              onPressed: () {
                Navigator.pop(context);
                context.push('/motoboy/wallet');
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Voltar',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final runsAsync = ref.watch(availableRunsProvider);
    final motoboyAsync = ref.watch(motoboyStreamProvider);
    final categoryName = motoboyAsync.valueOrNull?.vehicleCategory.info.name;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: categoryName != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Corridas Disponíveis', style: AppTypography.h3),
                  Text(
                    categoryName,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              )
            : Text('Corridas Disponíveis', style: AppTypography.h3),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: () => ref.invalidate(availableRunsProvider),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: runsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
        error: (e, _) {
          debugPrint('[AvailableRuns] Erro: $e');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                const SizedBox(height: AppSpacing.lg),
                Text('Erro ao carregar corridas', style: AppTypography.h3),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl3),
                  child: Text(
                    '$e',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextButton.icon(
                  onPressed: () => ref.invalidate(availableRunsProvider),
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppColors.primary),
                  label: Text(
                    'Tentar novamente',
                    style: AppTypography.labelLarge
                        .copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        },
        data: (runs) {
          if (runs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl4),
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 200),
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
                          Icons.search_off_rounded,
                          color: AppColors.textTertiary,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl2),
                      Text(
                        'Nenhuma corrida na sua região',
                        style: AppTypography.h3.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Novas corridas aparecem automaticamente',
                        style: AppTypography.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(availableRunsProvider);
              await ref.read(availableRunsProvider.future);
            },
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: ListView.separated(
              padding: AppSpacing.screenPaddingFull,
              itemCount: runs.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) => StaggeredListItem(
                index: i,
                child: _RunCard(
                  delivery: runs[i],
                  isAccepting: _isAccepting && _acceptingId == runs[i].id,
                  onAccept: () => _acceptRun(runs[i]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Run Card ─────────────────────────────────────────────────
class _RunCard extends StatelessWidget {
  final DeliveryModel delivery;
  final bool isAccepting;
  final VoidCallback onAccept;

  const _RunCard({
    required this.delivery,
    required this.isAccepting,
    required this.onAccept,
  });

  double _haversineDistanceKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lng2 - lng1) * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * asin(sqrt(h));
  }

  @override
  Widget build(BuildContext context) {
    final distKm = _haversineDistanceKm(
      delivery.pickupLat,
      delivery.pickupLng,
      delivery.deliveryLat,
      delivery.deliveryLng,
    );

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coleta
          Row(
            children: [
              const Icon(Icons.radio_button_on_rounded,
                  color: AppColors.primary, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  delivery.pickupAddress,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          // Linha pontilhada
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Container(
              width: 1.5,
              height: 14,
              color: AppColors.surfaceBorder,
            ),
          ),
          // Entrega
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppColors.error, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  delivery.deliveryAddress,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Badge de categoria + valor líquido
          Row(
            children: [
              VehicleBadge(category: delivery.vehicleCategory),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Você recebe',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(
                      PriceCalculator.netValue(delivery.value),
                    ),
                    style: AppTypography.numericMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Info chips: distância
          Row(
            children: [
              _InfoChip(
                icon: Icons.straighten_rounded,
                label: '${distKm.toStringAsFixed(1)} km',
              ),
              const SizedBox(width: AppSpacing.sm),
              _InfoChip(
                icon: Icons.attach_money_rounded,
                label: 'Total ${CurrencyFormatter.format(delivery.value)}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Botão aceitar
          PrimaryButton(
            label: 'Aceitar Corrida',
            onPressed: isAccepting ? null : onAccept,
            isLoading: isAccepting,
          ),
        ],
      ),
    );
  }
}

// ── Info Chip ────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    const color = AppColors.textSecondary;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: color,
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
