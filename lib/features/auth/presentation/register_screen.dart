import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/utils/validators.dart';
import '../../motoboy/domain/driver_registration_rules.dart';
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
  final _documentCtrl = TextEditingController();
  final _motoboyCpfCtrl = TextEditingController();
  final _cnhNumberCtrl = TextEditingController();
  final _cnhCategoryCtrl = TextEditingController();

  String _selectedRole = 'client';
  String _clientType = 'cpf'; // 'cpf' ou 'cnpj'
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  VehicleCategoryInfo? _selectedCategory;
  DateTime? _cnhExpirationDate;
  File? _identityDocumentFile;
  File? _selfieWithDocumentFile;
  File? _addressProofFile;
  File? _cnhPhotoFile;
  File? _vehicleDocumentFile;
  File? _additionalPermitFile;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _plateCtrl.dispose();
    _modelCtrl.dispose();
    _documentCtrl.dispose();
    _yearCtrl.dispose();
    _motoboyCpfCtrl.dispose();
    _cnhNumberCtrl.dispose();
    _cnhCategoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRole == 'client' &&
        _documentCtrl.text.replaceAll(RegExp(r'\D'), '').isEmpty) {
      _showError('Informe o CPF ou CNPJ para continuar.');
      return;
    }

    if (_selectedRole == 'motoboy') {
      if (_selectedCategory == null) {
        _showError('Selecione a categoria do entregador para continuar.');
        return;
      }

      final missing = missingDriverRegistrationItems(
        category: _selectedCategory!.category,
        cpf: _motoboyCpfCtrl.text.replaceAll(RegExp(r'\D'), ''),
        vehiclePlate: _plateCtrl.text.trim(),
        vehicleModel: _modelCtrl.text.trim(),
        vehicleYear: _yearCtrl.text.trim(),
        cnhNumber: _cnhNumberCtrl.text.trim(),
        cnhCategory: _cnhCategoryCtrl.text.trim(),
        cnhExpirationDate: _cnhExpirationDate,
        hasIdentityDocument: _identityDocumentFile != null,
        hasSelfieWithDocument: _selfieWithDocumentFile != null,
        hasAddressProof: _addressProofFile != null,
        hasCnhPhoto: _cnhPhotoFile != null,
        hasVehicleDocument: _vehicleDocumentFile != null,
        hasAdditionalPermit: _additionalPermitFile != null,
      );

      if (missing.isNotEmpty) {
        _showError('Cadastro incompleto. Envie: ${missing.join(', ')}.');
        return;
      }
    }

    await ref
        .read(authNotifierProvider.notifier)
        .signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          role: _selectedRole,
          clientType: _selectedRole == 'client' ? _clientType : null,
          document: _selectedRole == 'client'
              ? _documentCtrl.text.replaceAll(RegExp(r'\D'), '')
              : null,
          vehiclePlate: _selectedRole == 'motoboy'
              ? _plateCtrl.text.trim()
              : null,
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
          motoboyCpf: _selectedRole == 'motoboy'
              ? _motoboyCpfCtrl.text.replaceAll(RegExp(r'\D'), '')
              : null,
          cnhNumber: _selectedRole == 'motoboy'
              ? _cnhNumberCtrl.text.trim()
              : null,
          cnhCategory: _selectedRole == 'motoboy'
              ? _cnhCategoryCtrl.text.trim().toUpperCase()
              : null,
          cnhExpirationDate: _selectedRole == 'motoboy'
              ? _cnhExpirationDate
              : null,
          identityDocumentFile: _selectedRole == 'motoboy'
              ? _identityDocumentFile
              : null,
          selfieWithDocumentFile: _selectedRole == 'motoboy'
              ? _selfieWithDocumentFile
              : null,
          addressProofFile: _selectedRole == 'motoboy'
              ? _addressProofFile
              : null,
          cnhPhotoFile: _selectedRole == 'motoboy' ? _cnhPhotoFile : null,
          vehicleDocumentFile: _selectedRole == 'motoboy'
              ? _vehicleDocumentFile
              : null,
          additionalPermitFile: _selectedRole == 'motoboy'
              ? _additionalPermitFile
              : null,
        );

    if (!mounted) return;

    final authState = ref.read(authNotifierProvider);
    if (authState.hasError) {
      _showError(authState.error.toString());
    }
  }

  Future<void> _pickDocument(void Function(File file) onSelected) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 75,
    );
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      onSelected(file);
    });
  }

  Future<void> _pickCnhExpirationDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _cnhExpirationDate ?? now.add(const Duration(days: 365)),
      firstDate: now.subtract(const Duration(days: 3650)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    setState(() => _cnhExpirationDate = picked);
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  void _showError(String message) {
    if (message.contains('check_email_flag')) {
      context.go('/check-email');
      return;
    }

    final isEmailUsed =
        message.contains('already') || message.contains('registered');
    final displayMessage = isEmailUsed
        ? 'Este e-mail já está cadastrado'
        : message;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error),
            SizedBox(width: 8),
            Text(
              'Erro no Cadastro',
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        content: Text(
          displayMessage,
          style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: AppColors.primary)),
          ),
        ],
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

                // ── Campos exclusivos para cliente ─────────────
                if (_selectedRole == 'client') ...[
                  DropdownButtonFormField<String>(
                    initialValue: _clientType,
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    dropdownColor: AppColors.surface,
                    decoration: InputDecoration(
                      labelText: 'Tipo de Conta',
                      prefixIcon: Icon(
                        _clientType == 'cpf'
                            ? Icons.person_outlined
                            : Icons.business_rounded,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'cpf',
                        child: Text('Pessoa Física (CPF)'),
                      ),
                      DropdownMenuItem(
                        value: 'cnpj',
                        child: Text('Empresa (CNPJ)'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _clientType = v;
                          _documentCtrl.clear();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _documentCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(
                        _clientType == 'cpf' ? 11 : 14,
                      ),
                      _clientType == 'cpf'
                          ? _CpfMaskFormatter()
                          : _CnpjMaskFormatter(),
                    ],
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: _clientType == 'cpf' ? 'CPF' : 'CNPJ',
                      hintText: _clientType == 'cpf'
                          ? '000.000.000-00'
                          : '00.000.000/0000-00',
                      prefixIcon: Icon(
                        _clientType == 'cpf'
                            ? Icons.badge_outlined
                            : Icons.business_center_outlined,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                    ),
                    validator: (v) {
                      final digits = v?.replaceAll(RegExp(r'\D'), '') ?? '';
                      if (_clientType == 'cpf' && digits.length != 11) {
                        return 'CPF deve ter 11 dígitos';
                      }
                      if (_clientType == 'cnpj' && digits.length != 14) {
                        return 'CNPJ deve ter 14 dígitos';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // Nome
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Nome completo',
                    prefixIcon: Icon(
                      Icons.person_outlined,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
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
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    hintText: '(00) 00000-0000',
                    prefixIcon: Icon(
                      Icons.phone_outlined,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
                  ),
                  validator: Validators.phone,
                ),
                const SizedBox(height: AppSpacing.lg),

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
                  textInputAction: TextInputAction.next,
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
                const SizedBox(height: AppSpacing.lg),

                // Confirmar senha
                TextFormField(
                  controller: _confirmPasswordCtrl,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.next,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Confirmar senha',
                    prefixIcon: const Icon(
                      Icons.lock_outlined,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
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
                    if (v != _passwordCtrl.text) {
                      return 'As senhas não coincidem';
                    }
                    return null;
                  },
                ),

                // ── Campos exclusivos para entregador ─────────
                if (_selectedRole == 'motoboy') ...[
                  const SizedBox(height: AppSpacing.xl3),

                  // Seletor de categoria
                  Text(
                    'Categoria do entregador',
                    style: AppTypography.labelLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'O cadastro será analisado com documentos obrigatórios de acordo com a categoria.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  CategorySelectorWidget(
                    isForDriver: true,
                    onSelected: (cat) =>
                        setState(() => _selectedCategory = cat),
                  ),
                  const SizedBox(height: AppSpacing.xl2),

                  TextFormField(
                    controller: _motoboyCpfCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                      _CpfMaskFormatter(),
                    ],
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'CPF do entregador',
                      hintText: '000.000.000-00',
                      prefixIcon: Icon(
                        Icons.badge_outlined,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                    ),
                    validator: (v) =>
                        _selectedRole == 'motoboy' ? Validators.cpf(v) : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Placa
                  if (_selectedCategory != null &&
                      driverCategoryNeedsPlate(
                        _selectedCategory!.category,
                      )) ...[
                    TextFormField(
                      controller: _plateCtrl,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Placa do veículo',
                        hintText: 'Ex: ABC-1234',
                        prefixIcon: Icon(
                          Icons.two_wheeler_rounded,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                      ),
                      validator: (v) =>
                          _selectedRole == 'motoboy' &&
                              _selectedCategory != null &&
                              driverCategoryNeedsPlate(
                                _selectedCategory!.category,
                              )
                          ? Validators.required(v, field: 'Placa')
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  // Modelo
                  if (_selectedCategory != null &&
                      driverCategoryNeedsPlate(
                        _selectedCategory!.category,
                      )) ...[
                    TextFormField(
                      controller: _modelCtrl,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Modelo do veículo',
                        hintText: 'Ex: Honda CG 160',
                        prefixIcon: Icon(
                          Icons.directions_car_outlined,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                      ),
                      validator: (v) =>
                          _selectedCategory != null &&
                              driverCategoryNeedsPlate(
                                _selectedCategory!.category,
                              )
                          ? Validators.required(v, field: 'Modelo do veículo')
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  // Ano
                  if (_selectedCategory != null &&
                      driverCategoryNeedsPlate(
                        _selectedCategory!.category,
                      )) ...[
                    TextFormField(
                      controller: _yearCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Ano do veículo',
                        hintText: 'Ex: 2021',
                        prefixIcon: Icon(
                          Icons.calendar_today_outlined,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                      ),
                      validator: (v) {
                        if (_selectedCategory == null ||
                            !driverCategoryNeedsPlate(
                              _selectedCategory!.category,
                            )) {
                          return null;
                        }
                        if (v == null || v.isEmpty) {
                          return 'Ano do veículo é obrigatório';
                        }
                        final year = int.tryParse(v);
                        if (year == null || year < 1980 || year > 2035) {
                          return 'Ano inválido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  if (_selectedCategory != null &&
                      driverCategoryNeedsCnh(_selectedCategory!.category)) ...[
                    TextFormField(
                      controller: _cnhNumberCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Número da CNH',
                        prefixIcon: Icon(
                          Icons.credit_card_outlined,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                      ),
                      validator: (v) =>
                          _selectedCategory != null &&
                              driverCategoryNeedsCnh(
                                _selectedCategory!.category,
                              )
                          ? Validators.required(v, field: 'Número da CNH')
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _cnhCategoryCtrl,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                        LengthLimitingTextInputFormatter(2),
                      ],
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Categoria da CNH',
                        hintText: 'Ex: A, B ou AB',
                        prefixIcon: Icon(
                          Icons.assignment_ind_outlined,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                      ),
                      validator: (v) =>
                          _selectedCategory != null &&
                              driverCategoryNeedsCnh(
                                _selectedCategory!.category,
                              )
                          ? Validators.required(v, field: 'Categoria da CNH')
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    InkWell(
                      onTap: _pickCnhExpirationDate,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Validade da CNH',
                          prefixIcon: Icon(
                            Icons.event_outlined,
                            color: AppColors.textTertiary,
                            size: 20,
                          ),
                        ),
                        child: Text(
                          _cnhExpirationDate == null
                              ? 'Selecione a data'
                              : _formatDate(_cnhExpirationDate!),
                          style: AppTypography.bodyLarge.copyWith(
                            color: _cnhExpirationDate == null
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl2),
                  ],

                  if (_selectedCategory != null) ...[
                    _DocumentsChecklistCard(
                      category: _selectedCategory!.category,
                      hasIdentityDocument: _identityDocumentFile != null,
                      hasSelfieWithDocument: _selfieWithDocumentFile != null,
                      hasAddressProof: _addressProofFile != null,
                      hasCnhPhoto: _cnhPhotoFile != null,
                      hasVehicleDocument: _vehicleDocumentFile != null,
                      hasAdditionalPermit: _additionalPermitFile != null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _DocumentUploadTile(
                      label: 'Documento de identificação',
                      subtitle: 'RG ou documento oficial com foto',
                      file: _identityDocumentFile,
                      onTap: () =>
                          _pickDocument((file) => _identityDocumentFile = file),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _DocumentUploadTile(
                      label: 'Selfie com documento',
                      subtitle: 'Foto do rosto segurando o documento visível',
                      file: _selfieWithDocumentFile,
                      onTap: () => _pickDocument(
                        (file) => _selfieWithDocumentFile = file,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _DocumentUploadTile(
                      label: 'Comprovante de residência',
                      subtitle: 'Conta recente em nome do entregador',
                      file: _addressProofFile,
                      onTap: () =>
                          _pickDocument((file) => _addressProofFile = file),
                    ),
                    if (driverCategoryNeedsCnh(
                      _selectedCategory!.category,
                    )) ...[
                      const SizedBox(height: AppSpacing.md),
                      _DocumentUploadTile(
                        label: 'Foto da CNH',
                        subtitle: 'Imagem legível da habilitação',
                        file: _cnhPhotoFile,
                        onTap: () =>
                            _pickDocument((file) => _cnhPhotoFile = file),
                      ),
                    ],
                    if (driverCategoryNeedsVehicleDocument(
                      _selectedCategory!.category,
                    )) ...[
                      const SizedBox(height: AppSpacing.md),
                      _DocumentUploadTile(
                        label: 'Documento do veículo',
                        subtitle: 'CRLV ou equivalente',
                        file: _vehicleDocumentFile,
                        onTap: () => _pickDocument(
                          (file) => _vehicleDocumentFile = file,
                        ),
                      ),
                    ],
                    if (driverCategoryNeedsAdditionalPermit(
                      _selectedCategory!.category,
                    )) ...[
                      const SizedBox(height: AppSpacing.md),
                      _DocumentUploadTile(
                        label: driverAdditionalPermitLabel(
                          _selectedCategory!.category,
                        ),
                        subtitle:
                            'Envie a licença complementar exigida para operar',
                        file: _additionalPermitFile,
                        onTap: () => _pickDocument(
                          (file) => _additionalPermitFile = file,
                        ),
                      ),
                    ],
                  ],
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
            Text(subtitle, style: AppTypography.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _DocumentsChecklistCard extends StatelessWidget {
  final VehicleCategory category;
  final bool hasIdentityDocument;
  final bool hasSelfieWithDocument;
  final bool hasAddressProof;
  final bool hasCnhPhoto;
  final bool hasVehicleDocument;
  final bool hasAdditionalPermit;

  const _DocumentsChecklistCard({
    required this.category,
    required this.hasIdentityDocument,
    required this.hasSelfieWithDocument,
    required this.hasAddressProof,
    required this.hasCnhPhoto,
    required this.hasVehicleDocument,
    required this.hasAdditionalPermit,
  });

  @override
  Widget build(BuildContext context) {
    final items = <({String label, bool done})>[
      (label: 'Documento de identificação', done: hasIdentityDocument),
      (label: 'Selfie com documento', done: hasSelfieWithDocument),
      (label: 'Comprovante de residência', done: hasAddressProof),
      if (driverCategoryNeedsCnh(category))
        (label: 'Foto da CNH', done: hasCnhPhoto),
      if (driverCategoryNeedsVehicleDocument(category))
        (label: 'Documento do veículo', done: hasVehicleDocument),
      if (driverCategoryNeedsAdditionalPermit(category))
        (
          label: driverAdditionalPermitLabel(category),
          done: hasAdditionalPermit,
        ),
    ];

    return Container(
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
          Text('Checklist documental', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Somente cadastros completos seguem para análise.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    item.done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: item.done
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(item.label, style: AppTypography.bodyMedium),
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

class _DocumentUploadTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final File? file;
  final VoidCallback onTap;

  const _DocumentUploadTile({
    required this.label,
    required this.subtitle,
    required this.file,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedName = file?.path.split('/').last;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: file == null ? AppColors.surfaceBorder : AppColors.primary,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: file == null
                    ? AppColors.surfaceHigh
                    : AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                file == null ? Icons.upload_file_rounded : Icons.check_rounded,
                color: file == null
                    ? AppColors.textTertiary
                    : AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    selectedName ?? subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: selectedName == null
                          ? AppColors.textSecondary
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
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

// ── Formatador de CPF: 000.000.000-00 ─────────────────────────
class _CpfMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length && i < 11; i++) {
      if (i == 3 || i == 6) buffer.write('.');
      if (i == 9) buffer.write('-');
      buffer.write(digits[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ── Formatador de CNPJ: 00.000.000/0000-00 ────────────────────
class _CnpjMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length && i < 14; i++) {
      if (i == 2 || i == 5) buffer.write('.');
      if (i == 8) buffer.write('/');
      if (i == 12) buffer.write('-');
      buffer.write(digits[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
