import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/onboarding_service.dart';
import '../domain/auth_provider.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Observa o estado de auth — quando resolver, o GoRouter faz redirect.
    // Este listener é um seguro extra caso o router não dispare.
    ref.listen(authNotifierProvider, (_, next) {
      if (next.isLoading) return;
      final onboarding = ref.read(onboardingSeenProvider).valueOrNull;
      if (onboarding == false) {
        context.go('/onboarding');
        return;
      }
      final user = next.valueOrNull;
      if (user == null) {
        context.go('/login');
      } else {
        context.go(user.isClient ? '/client/home' : '/motoboy/home');
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Splash Logo / Image
          Center(
            child: Image.asset(
              'assets/logo-grande.png',
              width: 500,
              fit: BoxFit.contain,
            ),
          ),
          // Loading indicator at the bottom
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 64.0),
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
