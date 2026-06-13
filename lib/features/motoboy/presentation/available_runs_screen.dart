import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../client/domain/delivery_model.dart';
import '../../shared/widgets/micro_interactions.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/vehicle_badge.dart';
import '../data/motoboy_repository.dart';
import '../domain/driver_registration_rules.dart';
import '../domain/motoboy_model.dart';
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
  int _lastRunCount = -1;

  Future<void> _acceptRun(DeliveryModel delivery) async {
    final user = ref.read(authNotifierProvider).valueOrNull;
    if (user == null) return;

    final connected = await ConnectivityService.ensureConnected(
      context,
      message: 'Conecte-se para aceitar a corrida.',
    );
    if (!connected || !mounted) return;

    setState(() {
      _isAccepting = true;
      _acceptingId = delivery.id;
    });

    try {
      await ref
          .read(motoboyRepositoryProvider)
          .acceptDelivery(
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
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 18,
                ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
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

    ref.listen<AsyncValue<List<DeliveryModel>>>(availableRunsProvider, (
      prev,
      next,
    ) {
      final prevList = prev?.valueOrNull ?? [];
      final nextList = next.valueOrNull ?? [];
      // Exibe toast apenas quando novas corridas aparecem (não no carregamento inicial)
      if (_lastRunCount >= 0 && nextList.length > prevList.length) {
        final newCount = nextList.length - prevList.length;
        final value = nextList.first.value;
        AppToast.show(
          context,
          title: newCount == 1
              ? 'Nova corrida disponível!'
              : '$newCount novas corridas disponíveis!',
          subtitle:
              'Você recebe ${CurrencyFormatter.format(value)} — Aceite rápido!',
          type: AppToastType.info,
          duration: const Duration(seconds: 5),
        );
      }
      _lastRunCount = nextList.length;
    });

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
      body: motoboyAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (motoboy) {
          if (!motoboy.isApproved) {
            return _ApprovalBlockedBody(motoboy: motoboy);
          }

          return runsAsync.when(
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
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 48,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Erro ao carregar corridas', style: AppTypography.h3),
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl3,
                      ),
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
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: AppColors.primary,
                      ),
                      label: Text(
                        'Tentar novamente',
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.primary,
                        ),
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
                              border: Border.all(
                                color: AppColors.surfaceBorder,
                              ),
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
          );
        },
      ),
    );
  }
}

class _ApprovalBlockedBody extends StatelessWidget {
  final MotoboyModel motoboy;

  const _ApprovalBlockedBody({required this.motoboy});

  @override
  Widget build(BuildContext context) {
    final reason = motoboy.rejectionReason?.trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.verified_user_outlined,
              color: AppColors.warning,
              size: 54,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              motoboy.accessStatusLabel,
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              reason != null && reason.isNotEmpty
                  ? reason
                  : motoboy.accessStatusSummary,
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (!motoboy.canGoOnline &&
                motoboy.approvalStatus ==
                    MotoboyApprovalStatus.pendingDocuments &&
                (motoboy.missingRegistrationItems as List).isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Pendências: ${motoboy.missingRegistrationItems.join(', ')}',
                style: AppTypography.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    // Usa a distância real de rua salva no banco (a mesma usada para calcular o preço).
    // Se por algum motivo não estiver no banco (entrega antiga), mostra "—".
    final distKm = delivery.distanceKm;

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
              const Icon(
                Icons.radio_button_on_rounded,
                color: AppColors.primary,
                size: 16,
              ),
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
              const Icon(
                Icons.location_on_rounded,
                color: AppColors.error,
                size: 16,
              ),
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
                    CurrencyFormatter.format(delivery.value),
                    style: AppTypography.numericMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Info chips: distância real de rua + valor total
          Row(
            children: [
              _InfoChip(
                icon: Icons.straighten_rounded,
                label: distKm != null
                    ? '${distKm.toStringAsFixed(1)} km'
                    : '— km',
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

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    const color = AppColors.textSecondary;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
