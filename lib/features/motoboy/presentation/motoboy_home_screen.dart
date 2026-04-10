import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/motoboy_providers.dart';

class MotoboyHomeScreen extends ConsumerStatefulWidget {
  const MotoboyHomeScreen({super.key});

  @override
  ConsumerState<MotoboyHomeScreen> createState() => _MotoboyHomeScreenState();
}

class _MotoboyHomeScreenState extends ConsumerState<MotoboyHomeScreen> {
  bool _isToggling = false;

  Future<bool> _requestLocationPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  Future<void> _toggleOnline(bool currentlyOnline) async {
    final user = ref.read(authNotifierProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isToggling = true);

    try {
      final repo = ref.read(motoboyRepositoryProvider);

      if (!currentlyOnline) {
        // Ficar online — pedir GPS
        final hasPermission = await _requestLocationPermission();
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Permissão de localização necessária para ficar online',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                backgroundColor: AppColors.surface,
              ),
            );
          }
          return;
        }
        await repo.setOnline(user.id, true);
        repo.startLocationUpdates(user.id);
      } else {
        // Ficar offline
        repo.stopLocationUpdates();
        await repo.setOnline(user.id, false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: AppColors.surface,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final motoboyAsync = ref.watch(motoboyStreamProvider);
    final user = ref.watch(authNotifierProvider).valueOrNull;
    final activeRunAsync =
        user != null ? ref.watch(activeRunProvider(user.id)) : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.delivery_dining_rounded,
                color: AppColors.textInverse,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'UrbGo',
              style: AppTypography.h2.copyWith(color: AppColors.primary),
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
              ref.read(motoboyRepositoryProvider).stopLocationUpdates();
              await ref.read(authNotifierProvider.notifier).signOut();
            },
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
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: AppSpacing.lg),
              Text('Erro ao carregar dados', style: AppTypography.h3),
              const SizedBox(height: AppSpacing.lg),
              TextButton.icon(
                onPressed: () => ref.invalidate(motoboyStreamProvider),
                icon: const Icon(Icons.refresh_rounded,
                    color: AppColors.primary),
                label: Text('Tentar novamente',
                    style: AppTypography.labelLarge
                        .copyWith(color: AppColors.primary)),
              ),
            ],
          ),
        ),
        data: (motoboy) {
          return SingleChildScrollView(
            padding: AppSpacing.screenPaddingFull,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.lg),

                // ── Card de Saldo ──────────────────────
                _BalanceCard(
                  balance: motoboy.walletBalance,
                  onRecharge: () => context.push('/motoboy/wallet'),
                ),
                const SizedBox(height: AppSpacing.xl2),

                // ── Toggle Online/Offline ──────────────
                _OnlineToggle(
                  isOnline: motoboy.isOnline,
                  isToggling: _isToggling,
                  onToggle: () => _toggleOnline(motoboy.isOnline),
                ),
                const SizedBox(height: AppSpacing.xl2),

                // ── Botão Ver Corridas ─────────────────
                if (motoboy.isOnline) ...[
                  PrimaryButton(
                    label: 'Ver Corridas Disponíveis',
                    onPressed: () => context.push('/motoboy/runs'),
                  ),
                  const SizedBox(height: AppSpacing.xl2),
                ],

                // ── Corrida Ativa ──────────────────────
                if (activeRunAsync != null)
                  activeRunAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (activeRun) {
                      if (activeRun == null) return const SizedBox.shrink();
                      return _ActiveRunCard(
                        pickupAddress: activeRun.pickupAddress,
                        deliveryAddress: activeRun.deliveryAddress,
                        status: activeRun.status,
                        onContinue: () => context
                            .push('/motoboy/active/${activeRun.id}'),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Balance Card ─────────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final double balance;
  final VoidCallback onRecharge;

  const _BalanceCard({required this.balance, required this.onRecharge});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPaddingLarge,
      decoration: BoxDecoration(
        color: AppColors.primaryDeep,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 1,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Seu saldo',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            CurrencyFormatter.format(balance),
            style: AppTypography.numericHero,
          ),
          const SizedBox(height: AppSpacing.lg),
          GestureDetector(
            onTap: onRecharge,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Recarregar',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.primary,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Online Toggle ────────────────────────────────────────────
class _OnlineToggle extends StatelessWidget {
  final bool isOnline;
  final bool isToggling;
  final VoidCallback onToggle;

  const _OnlineToggle({
    required this.isOnline,
    required this.isToggling,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isToggling ? null : onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: double.infinity,
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: isOnline ? AppColors.primaryDeep : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isOnline ? AppColors.primary : AppColors.surfaceBorder,
            width: isOnline ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isOnline
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                isOnline
                    ? Icons.wifi_tethering_rounded
                    : Icons.wifi_tethering_off_rounded,
                color: isOnline ? AppColors.primary : AppColors.textTertiary,
                size: 24,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOnline ? 'Você está online' : 'Você está offline',
                    style: AppTypography.h4.copyWith(
                      color: isOnline
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isOnline
                        ? 'Recebendo corridas'
                        : 'Toque para ficar online',
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
            if (isToggling)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              )
            else
              Switch(
                value: isOnline,
                activeThumbColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
                inactiveThumbColor: AppColors.textTertiary,
                inactiveTrackColor: AppColors.surfaceBorder,
                onChanged: (_) => onToggle(),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Active Run Card ──────────────────────────────────────────
class _ActiveRunCard extends StatelessWidget {
  final String pickupAddress;
  final String deliveryAddress;
  final dynamic status;
  final VoidCallback onContinue;

  const _ActiveRunCard({
    required this.pickupAddress,
    required this.deliveryAddress,
    required this.status,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Corrida em andamento',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Coleta
          Row(
            children: [
              const Icon(Icons.radio_button_on_rounded,
                  color: AppColors.primary, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  pickupAddress,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Entrega
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppColors.error, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  deliveryAddress,
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
          PrimaryButton(
            label: 'Continuar Entrega',
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}
