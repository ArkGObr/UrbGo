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
    _OnboardingItem(
      icon: Icons.bolt_rounded,
      title: 'Bem-vindo ao ArkGO',
      subtitle:
          'Plataforma completa de mobilidade urbana. Entregas de qualquer tamanho e corridas com passageiros — onde você estiver.',
    ),
    _OnboardingItem(
      icon: Icons.inventory_2_rounded,
      title: 'Toda entrega,\nno tamanho certo',
      subtitle:
          'Pacotes pequenos ou mudanças completas. Escolha o veículo ideal e acompanhe cada etapa no mapa.',
      chips: ['Moto', 'Bike', 'Utilitário', 'Caminhão'],
    ),
    _OnboardingItem(
      icon: Icons.directions_car_rounded,
      title: 'Corridas com\npassageiros',
      subtitle:
          'Precisando de uma carona? Solicite um moto táxi ou carro passeio em segundos e chegue ao seu destino.',
      chips: ['Moto Táxi', 'Carro Passeio'],
    ),
    _OnboardingItem(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Tecnologia a\nseu favor',
      subtitle:
          'Rastreie no mapa, fale pelo chat, pague com PIX ou dinheiro e acompanhe seus ganhos em tempo real.',
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
                            boxShadow: const [
                              BoxShadow(
                                color: AppColors.primaryGlow,
                                blurRadius: 40,
                                spreadRadius: 4,
                              ),
                            ],
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
                        if (item.chips.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: item.chips
                                .map(
                                  (chip) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                      vertical: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppColors.surfaceBorder,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.full,
                                      ),
                                    ),
                                    child: Text(
                                      chip,
                                      style: AppTypography.labelSmall.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
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

class _OnboardingItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> chips;

  const _OnboardingItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.chips = const [],
  });
}
