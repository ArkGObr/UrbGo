import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/auth_provider.dart';

class MotoboyReleasePendingScreen extends ConsumerStatefulWidget {
  const MotoboyReleasePendingScreen({super.key});

  @override
  ConsumerState<MotoboyReleasePendingScreen> createState() =>
      _MotoboyReleasePendingScreenState();
}

class _MotoboyReleasePendingScreenState
    extends ConsumerState<MotoboyReleasePendingScreen> {
  bool _isRefreshing = false;

  Future<void> _refreshStatus() async {
    setState(() => _isRefreshing = true);
    try {
      await ref.read(authNotifierProvider.notifier).refreshSessionUser();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).valueOrNull;
    final blockMessage = user?.blockReason?.trim().isNotEmpty == true
        ? user!.blockReason!.trim()
        : 'Seu cadastro está em análise automática. Em breve você poderá rodar!';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.screenPaddingFull,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: AppColors.warning,
                  size: 36,
                ),
              ),
              const SizedBox(height: AppSpacing.xl2),
              Text('Aguardando aprovação', style: AppTypography.display2),
              const SizedBox(height: AppSpacing.md),
              Text(blockMessage, style: AppTypography.bodyLarge),
              if (user != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Status da conta: ${user.status}${user.isReleased ? ' • liberado' : ' • aguardando liberação'}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const Spacer(),
              PrimaryButton(
                label: _isRefreshing ? 'Atualizando...' : 'Verificar novamente',
                onPressed: _isRefreshing ? null : _refreshStatus,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: () => context.push('/motoboy/profile'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: AppColors.surfaceBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                child: Text(
                  'Revisar documentos',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () async {
                  final router = GoRouter.of(context);
                  await ref.read(authNotifierProvider.notifier).signOut();
                  if (!mounted) return;
                  router.go('/login');
                },
                child: Text(
                  'Sair',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
