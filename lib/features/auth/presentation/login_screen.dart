import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/document_opener_service.dart';
import '../../../core/utils/validators.dart';
import 'widgets/privacy_policy_sheet.dart';
import '../../shared/widgets/micro_interactions.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _clientTermsAsset = 'assets/legal/termo_cliente_arkgo.pdf';
  static const _driverTermsAsset = 'assets/legal/termo_motorista_arkgo.pdf';

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _openingClientTerms = false;
  bool _openingDriverTerms = false;
  bool _openingPrivacy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _openPrivacyPolicy() async {
    setState(() => _openingPrivacy = true);
    try {
      await PrivacyPolicySheet.show(context);
    } finally {
      if (mounted) {
        setState(() => _openingPrivacy = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    await ref
        .read(authNotifierProvider.notifier)
        .signIn(email: _emailCtrl.text.trim(), password: _passwordCtrl.text);

    if (!mounted) return;

    final authState = ref.read(authNotifierProvider);
    if (authState.hasError) {
      _showError(authState.error.toString());
    }
  }

  Future<void> _openTerms({
    required String assetPath,
    required String fileName,
    required bool isClient,
  }) async {
    setState(() {
      if (isClient) {
        _openingClientTerms = true;
      } else {
        _openingDriverTerms = true;
      }
    });

    try {
      await DocumentOpenerService().openAssetPdf(
        assetPath: assetPath,
        fileName: fileName,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o termo agora.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isClient) {
            _openingClientTerms = false;
          } else {
            _openingDriverTerms = false;
          }
        });
      }
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

  Future<void> _showForgotPasswordDialog() async {
    final emailResetCtrl = TextEditingController(text: _emailCtrl.text);
    final formKey = GlobalKey<FormState>();
    bool loading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          title: Text('Recuperar Senha', style: AppTypography.h3),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Digite seu e-mail para receber um link de redefinição de senha.',
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: emailResetCtrl,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.email_outlined, size: 20),
                  ),
                  validator: Validators.email,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text(
                'Cancelar',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setStateDialog(() => loading = true);
                      try {
                        await ref
                            .read(authNotifierProvider.notifier)
                            .resetPassword(emailResetCtrl.text.trim());
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Um link de recuperação de senha foi enviado para o seu e-mail!',
                            ),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Erro: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setStateDialog(() => loading = false);
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Enviar',
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
            ),
          ],
        ),
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
                  child: Image.asset(
                    'assets/arkgo-logo.png',
                    width: 180,
                    fit: BoxFit.contain,
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
                      Text('Você em movimento', style: AppTypography.bodyLarge),
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
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: Validators.password,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPasswordDialog,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 0,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Esqueci minha senha?',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
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
                FadeSlideIn(
                  delay: const Duration(milliseconds: 500),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Documentos legais', style: AppTypography.h3),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Consulte os termos de uso e a politica de privacidade sempre que precisar.',
                          style: AppTypography.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _openingClientTerms
                                  ? null
                                  : () => _openTerms(
                                      assetPath: _clientTermsAsset,
                                      fileName: 'Termo_Cliente_ARKGO.pdf',
                                      isClient: true,
                                    ),
                              icon: _openingClientTerms
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Termo do cliente'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _openingDriverTerms
                                  ? null
                                  : () => _openTerms(
                                      assetPath: _driverTermsAsset,
                                      fileName: 'Termo_Entregador_ARKGO.pdf',
                                      isClient: false,
                                    ),
                              icon: _openingDriverTerms
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Termo do entregador'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _openingPrivacy
                                  ? null
                                  : _openPrivacyPolicy,
                              icon: _openingPrivacy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.privacy_tip_outlined),
                              label: const Text('Politica de privacidade'),
                            ),
                          ],
                        ),
                      ],
                    ),
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
