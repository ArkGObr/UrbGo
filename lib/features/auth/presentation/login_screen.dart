import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/validators.dart';
import '../../shared/widgets/micro_interactions.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(authNotifierProvider.notifier).signIn(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );

    if (!mounted) return;

    final authState = ref.read(authNotifierProvider);
    if (authState.hasError) {
      _showError(authState.error.toString());
    }
  }

  void _showError(String message) {
    final isCredentialError =
        message.contains('Invalid') || message.contains('Credenciais');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                isCredentialError
                    ? 'E-mail ou senha incorretos'
                    : 'Erro ao fazer login. Tente novamente.',
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
        margin: const EdgeInsets.all(AppSpacing.lg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authNotifierProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.screenPaddingFull,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xl4),

                // Logo
                FadeSlideIn(
                  delay: const Duration(milliseconds: 100),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/logo.png',
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      RichText(
                        text: TextSpan(
                          style: AppTypography.h1,
                          children: [
                            const TextSpan(text: 'Urb'),
                            TextSpan(
                              text: 'Go',
                              style: AppTypography.h1.copyWith(color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl2),

                FadeSlideIn(
                  delay: const Duration(milliseconds: 200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Entrar na conta', style: AppTypography.display2),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Sua entrega em movimento', style: AppTypography.bodyLarge),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl4),

                FadeSlideIn(
                  delay: const Duration(milliseconds: 300),
                  child: Column(
                    children: [
                      // E-mail
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        style: AppTypography.bodyLarge.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: AppColors.textTertiary,
                            size: 20,
                          ),
                        ),
                        validator: Validators.email,
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Senha
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        style: AppTypography.bodyLarge.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: const Icon(
                            Icons.lock_outlined,
                            color: AppColors.textTertiary,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.textTertiary,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: Validators.password,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl3),

                // Botão entrar
                FadeSlideIn(
                  delay: const Duration(milliseconds: 450),
                  child: PrimaryButton(
                    label: 'Entrar',
                    onPressed: isLoading ? null : _submit,
                    isLoading: isLoading,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl2),

                // Link cadastro
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/register'),
                    child: RichText(
                      text: TextSpan(
                        text: 'Não tem conta? ',
                        style: AppTypography.bodyMedium,
                        children: [
                          TextSpan(
                            text: 'Cadastre-se',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
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
}
