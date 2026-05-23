import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/app_spacing.dart';

class CheckEmailScreen extends StatelessWidget {
  const CheckEmailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mark_email_read_rounded,
                  color: AppColors.primary,
                  size: 64,
                ),
              ),
              SizedBox(height: AppSpacing.xl2),
              Text(
                'Confirme seu E-mail',
                style: AppTypography.h1,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.md),
              Text(
                'Enviamos um link de confirmação para o seu e-mail.\n\nAbra o Gmail (ou seu app de e-mail) e clique no link para ativar sua conta — você será redirecionado automaticamente para o app.',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/login'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
                child: const Text('Voltar para o Início'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
