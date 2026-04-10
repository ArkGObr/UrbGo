import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../domain/auth_provider.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Observa o estado de auth — quando resolver, o GoRouter faz redirect.
    // Este listener é um seguro extra caso o router não dispare.
    ref.listen(authNotifierProvider, (_, next) {
      if (next.isLoading) return;
      final user = next.valueOrNull;
      if (user == null) {
        context.go('/login');
      } else {
        context.go(user.isClient ? '/client/home' : '/motoboy/home');
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.primaryGlow,
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.delivery_dining_rounded,
                color: AppColors.textInverse,
                size: 44,
              ),
            ),
            const SizedBox(height: AppSpacing.xl2),
            Text('UrbGo', style: AppTypography.display2),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Sua entrega em movimento',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl6),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
