import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/utils/validators.dart';
import '../../shared/widgets/category_selector.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();

  String _selectedRole = 'client';
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  VehicleCategoryInfo? _selectedCategory;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _plateCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRole == 'motoboy' && _selectedCategory == null) {
      _showError('Selecione o tipo de veículo para continuar.');
      return;
    }

    await ref.read(authNotifierProvider.notifier).signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          role: _selectedRole,
          vehiclePlate:
              _selectedRole == 'motoboy' ? _plateCtrl.text.trim() : null,
          vehicleCategory: _selectedRole == 'motoboy'
              ? (_selectedCategory?.id ?? 'motoboy')
              : null,
          vehicleModel: _selectedRole == 'motoboy'
              ? _modelCtrl.text.trim().isEmpty
                  ? null
                  : _modelCtrl.text.trim()
              : null,
          vehicleYear: _selectedRole == 'motoboy'
              ? int.tryParse(_yearCtrl.text.trim())
              : null,
        );

    if (!mounted) return;

    final authState = ref.read(authNotifierProvider);
    if (authState.hasError) {
      _showError(authState.error.toString());
    }
  }

  void _showError(String message) {
    final isEmailUsed =
        message.contains('already') || message.contains('registered');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                isEmailUsed
                    ? 'Este e-mail já está cadastrado'
                    : 'Erro ao criar conta. Tente novamente.',
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
                const SizedBox(height: AppSpacing.xl2),

                // Voltar + título
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.surfaceBorder),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.textPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text('Criar conta', style: AppTypography.h2),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl3),

                // Seleção de tipo de conta
                Text('Tipo de conta', style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _RoleCard(
                        icon: Icons.business_rounded,
                        label: 'Sou Empresa',
                        subtitle: 'Crio pedidos',
                        value: 'client',
                        selected: _selectedRole == 'client',
                        onTap: () => setState(() => _selectedRole = 'client'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _RoleCard(
                        icon: Icons.two_wheeler_rounded,
                        label: 'Sou Entregador',
                        subtitle: 'Faço entregas',
                        value: 'motoboy',
                        selected: _selectedRole == 'motoboy',
                        onTap: () => setState(() => _selectedRole = 'motoboy'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl2),

                // Nome
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  style: AppTypography.bodyLarge
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Nome completo',
                    prefixIcon: Icon(Icons.person_outlined,
                        color: AppColors.textTertiary, size: 20),
                  ),
                  validator: (v) => Validators.required(v, field: 'Nome'),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Telefone
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [_PhoneMaskFormatter()],
                  style: AppTypography.bodyLarge
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    hintText: '(00) 00000-0000',
                    prefixIcon: Icon(Icons.phone_outlined,
                        color: AppColors.textTertiary, size: 20),
                  ),
                  validator: Validators.phone,
                ),
                const SizedBox(height: AppSpacing.lg),

                // E-mail
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  style: AppTypography.bodyLarge
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.email_outlined,
                        color: AppColors.textTertiary, size: 20),
                  ),
                  validator: Validators.email,
                ),
                const SizedBox(height: AppSpacing.lg),

                // Senha
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  style: AppTypography.bodyLarge
                      .copyWith(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    prefixIcon: const Icon(Icons.lock_outlined,
                        color: AppColors.textTertiary, size: 20),
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
                const SizedBox(height: AppSpacing.lg),

                // Confirmar senha
                TextFormField(
                  controller: _confirmPasswordCtrl,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.next,
                  style: AppTypography.bodyLarge
                      .copyWith(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Confirmar senha',
                    prefixIcon: const Icon(Icons.lock_outlined,
                        color: AppColors.textTertiary, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Confirme sua senha';
                    if (v != _passwordCtrl.text) return 'As senhas não coincidem';
                    return null;
                  },
                ),

                // ── Campos exclusivos para entregador ─────────
                if (_selectedRole == 'motoboy') ...[
                  const SizedBox(height: AppSpacing.xl3),

                  // Seletor de categoria
                  Text('Tipo de veículo', style: AppTypography.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Você só receberá corridas da sua categoria',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  CategorySelectorWidget(
                    isForDriver: true,
                    onSelected: (cat) =>
                        setState(() => _selectedCategory = cat),
                  ),
                  const SizedBox(height: AppSpacing.xl2),

                  // Placa
                  TextFormField(
                    controller: _plateCtrl,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    style: AppTypography.bodyLarge
                        .copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Placa do veículo',
                      hintText: 'Ex: ABC-1234',
                      prefixIcon: Icon(Icons.two_wheeler_rounded,
                          color: AppColors.textTertiary, size: 20),
                    ),
                    validator: (v) => _selectedRole == 'motoboy'
                        ? Validators.required(v, field: 'Placa')
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Modelo
                  TextFormField(
                    controller: _modelCtrl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    style: AppTypography.bodyLarge
                        .copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Modelo do veículo',
                      hintText: 'Ex: Honda CG 160',
                      prefixIcon: Icon(Icons.directions_car_outlined,
                          color: AppColors.textTertiary, size: 20),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Ano
                  TextFormField(
                    controller: _yearCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    style: AppTypography.bodyLarge
                        .copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Ano do veículo',
                      hintText: 'Ex: 2021',
                      prefixIcon: Icon(Icons.calendar_today_outlined,
                          color: AppColors.textTertiary, size: 20),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return null; // opcional
                      final year = int.tryParse(v);
                      if (year == null || year < 1980 || year > 2030) {
                        return 'Ano inválido';
                      }
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: AppSpacing.xl3),

                // Botão criar conta
                PrimaryButton(
                  label: 'Criar conta',
                  onPressed: isLoading ? null : _submit,
                  isLoading: isLoading,
                ),
                const SizedBox(height: AppSpacing.xl2),

                Center(
                  child: TextButton(
                    onPressed: () => context.go('/login'),
                    child: RichText(
                      text: TextSpan(
                        text: 'Já tem conta? ',
                        style: AppTypography.bodyMedium,
                        children: [
                          TextSpan(
                            text: 'Entrar',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Widget: Card de seleção de role ──────────────────────────
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDeep : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.surfaceBorder,
            width: selected ? 1.5 : 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: selected ? AppColors.primary : AppColors.textTertiary,
              size: 26,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: AppTypography.h4.copyWith(
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppTypography.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Formatador de telefone simples ────────────────────────────
class _PhoneMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length && i < 11; i++) {
      if (i == 0) buffer.write('(');
      if (i == 2) buffer.write(') ');
      if (i == 7) buffer.write('-');
      buffer.write(digits[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
