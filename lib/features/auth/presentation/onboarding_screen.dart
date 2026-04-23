import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/onboarding_service.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/auth_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _items = [
    (
      icon: Icons.flash_on_rounded,
      title: 'Entrega urbana sem enrolacao',
      subtitle:
          'Peça corridas em poucos toques ou fique online para receber entregas perto de voce.',
    ),
    (
      icon: Icons.route_rounded,
      title: 'Rastreamento e conversa em tempo real',
      subtitle:
          'Acompanhe o motoboy no mapa, receba previsao e fale direto pela entrega.',
    ),
    (
      icon: Icons.account_balance_wallet_rounded,
      title: 'Carteira, reputacao e controle',
      subtitle:
          'Veja ganhos, evolua seu nivel de reputacao e gerencie suas recargas no app.',
    ),
  ];

  Future<void> _finish() async {
    await ref.read(onboardingServiceProvider).markSeen();
    ref.invalidate(onboardingSeenProvider);
    if (!mounted) return;
    final user = ref.read(authNotifierProvider).valueOrNull;
    context.go(
      user == null
          ? '/login'
          : (user.isClient ? '/client/home' : '/motoboy/home'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _items.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.screenPaddingFull,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Pular',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _items.length,
                  onPageChanged: (value) => setState(() => _page = value),
                  itemBuilder: (_, index) {
                    final item = _items[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            color: AppColors.primaryDeep,
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Icon(
                            item.icon,
                            color: AppColors.primary,
                            size: 52,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl3),
                        Text(
                          item.title,
                          textAlign: TextAlign.center,
                          style: AppTypography.h1.copyWith(fontSize: 30),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          item.subtitle,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _items.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _page == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _page == index
                          ? AppColors.primary
                          : AppColors.surfaceBorder,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl2),
              PrimaryButton(
                label: isLast ? 'Começar agora' : 'Continuar',
                onPressed: () async {
                  if (isLast) {
                    await _finish();
                    return;
                  }
                  await _controller.nextPage(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
