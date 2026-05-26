import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/services/cep_service.dart';
import '../../../core/services/document_picker_service.dart';
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
  final _rgNumberCtrl = TextEditingController();
  final _cnhNumberCtrl = TextEditingController();
  final _cnhCategoryCtrl = TextEditingController();
  final _addressZipCtrl = TextEditingController();
  final _addressNumberCtrl = TextEditingController();
  final _addressComplementCtrl = TextEditingController();
  final _addressLabelCtrl = TextEditingController();
  final _addressZipFocus = FocusNode();

  int _currentStep = 0;
  String _selectedRole = 'client';
  String _clientType = 'cpf'; // 'cpf' ou 'cnpj'
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  VehicleCategoryInfo? _selectedCategory;
  DateTime? _cnhExpirationDate;
  File? _identityDocumentFile;
  File? _selfieWithDocumentFile;
  File? _vehicleDocumentFile;
  File? _additionalPermitFile;
  bool _loadingAddress = false;
  Timer? _addressDebounce;

  @override
  void initState() {
    super.initState();
    _addressZipCtrl.addListener(_onAddressZipChanged);
  }

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
    _rgNumberCtrl.dispose();
    _cnhNumberCtrl.dispose();
    _cnhCategoryCtrl.dispose();
    _addressZipCtrl.dispose();
    _addressNumberCtrl.dispose();
    _addressComplementCtrl.dispose();
    _addressLabelCtrl.dispose();
    _addressZipFocus.dispose();
    _addressDebounce?.cancel();
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
        rgNumber: _rgNumberCtrl.text.trim(),
        vehiclePlate: _plateCtrl.text.trim(),
        vehicleModel: _modelCtrl.text.trim(),
        vehicleYear: _yearCtrl.text.trim(),
        cnhNumber: _cnhNumberCtrl.text.trim(),
        cnhCategory: _cnhCategoryCtrl.text.trim(),
        cnhExpirationDate: _cnhExpirationDate,
        addressZipCode: _addressZipCtrl.text.replaceAll(RegExp(r'\D'), ''),
        addressNumber: _addressNumberCtrl.text.trim(),
        addressLabel: _addressLabelCtrl.text.trim(),
        hasIdentityDocument: _identityDocumentFile != null,
        hasSelfieWithDocument: _selfieWithDocumentFile != null,
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
          rgNumber: _selectedRole == 'motoboy' &&
                  _selectedCategory != null &&
                  driverCategoryNeedsRg(_selectedCategory!.category)
              ? _rgNumberCtrl.text.trim()
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
          addressZipCode: _selectedRole == 'motoboy'
              ? _addressZipCtrl.text.replaceAll(RegExp(r'\D'), '')
              : null,
          addressNumber: _selectedRole == 'motoboy'
              ? _addressNumberCtrl.text.trim()
              : null,
          addressComplement: _selectedRole == 'motoboy'
              ? _addressComplementCtrl.text.trim().isEmpty
                    ? null
                    : _addressComplementCtrl.text.trim()
              : null,
          addressLabel: _selectedRole == 'motoboy'
              ? _addressLabelCtrl.text.trim()
              : null,
          identityDocumentFile: _selectedRole == 'motoboy'
              ? _identityDocumentFile
              : null,
          selfieWithDocumentFile: _selectedRole == 'motoboy'
              ? _selfieWithDocumentFile
              : null,
          cnhPhotoFile: null,
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

  Future<void> _pickSelfie() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() {
      _selfieWithDocumentFile = File(picked.path);
    });
  }

  Future<void> _pickPdfDocument(void Function(File file) onSelected) async {
    final file = await DocumentPickerService().pickPdf();
    if (file == null) return;

    setState(() {
      onSelected(file);
    });
  }

  void _onAddressZipChanged() {
    final zipDigits = _addressZipCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (zipDigits.length < 8) {
      _addressDebounce?.cancel();
      if (_addressLabelCtrl.text.isNotEmpty) {
        setState(() => _addressLabelCtrl.clear());
      }
      return;
    }

    _addressDebounce?.cancel();
    setState(() => _loadingAddress = true);
    _addressDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final result = await CepService.lookup(zipDigits);
      if (!mounted) return;
      if (_addressZipCtrl.text.replaceAll(RegExp(r'\D'), '') == zipDigits) {
        setState(() {
          _loadingAddress = false;
          if (result != null) {
            _addressLabelCtrl.text = result.label;
            _addressZipFocus.unfocus();
          } else {
            _addressLabelCtrl.clear();
          }
        });
      }
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
    final totalSteps = _selectedRole == 'client' ? 3 : 4;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xl2,
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                bottom: AppSpacing.md,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (_currentStep > 0) {
                        setState(() => _currentStep--);
                      } else {
                        context.go('/login');
                      }
                    },
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
            ),

            // Progress Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Row(
                children: List.generate(totalSteps, (index) {
                  final isActive = index <= _currentStep;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                        right: index < totalSteps - 1 ? AppSpacing.xs : 0,
                      ),
                      height: 4,
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primary
                            : AppColors.surfaceBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Form Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_currentStep == 0) _buildStep0Role(),
                      if (_currentStep == 1) _buildStep1PersonalInfo(),
                      if (_currentStep == 2) _buildStep2Details(),
                      if (_currentStep == 3 && _selectedRole == 'motoboy')
                        _buildStep3Documents(),

                      const SizedBox(height: AppSpacing.xl3),

                      PrimaryButton(
                        label: _currentStep < totalSteps - 1
                            ? 'Próximo'
                            : 'Criar conta',
                        onPressed: isLoading
                            ? null
                            : () {
                                if (_formKey.currentState!.validate()) {
                                  if (_currentStep < totalSteps - 1) {
                                    setState(() => _currentStep++);
                                  } else {
                                    _submit();
                                  }
                                }
                              },
                        isLoading: isLoading,
                      ),
                      const SizedBox(height: AppSpacing.xl2),

                      if (_currentStep == 0)
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
          ],
        ),
      ),
    );
  }

  Widget _buildStep0Role() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tipo de conta', style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.md),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _RoleCard(
                  icon: Icons.business_rounded,
                  label: 'Sou Cliente',
                  subtitle: 'Crio pedidos',
                  value: 'client',
                  selected: _selectedRole == 'client',
                  onTap: () => setState(() => _selectedRole = 'client'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _RoleCard(
                  icon: Icons.person_rounded,
                  label: 'Sou Motorista',
                  subtitle: 'Faço corridas e entregas',
                  value: 'motoboy',
                  selected: _selectedRole == 'motoboy',
                  onTap: () => setState(() => _selectedRole = 'motoboy'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep1PersonalInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Informações Pessoais', style: AppTypography.h3),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
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
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          inputFormatters: [_PhoneMaskFormatter()],
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
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
        TextFormField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
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
        TextFormField(
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
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
        TextFormField(
          controller: _confirmPasswordCtrl,
          obscureText: _obscureConfirm,
          textInputAction: TextInputAction.next,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
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
            if (v != _passwordCtrl.text) return 'As senhas não coincidem';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildStep2Details() {
    if (_selectedRole == 'client') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Detalhes da Conta', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.lg),
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
              DropdownMenuItem(value: 'cnpj', child: Text('Empresa (CNPJ)')),
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
              LengthLimitingTextInputFormatter(_clientType == 'cpf' ? 11 : 14),
              _clientType == 'cpf' ? _CpfMaskFormatter() : _CnpjMaskFormatter(),
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
              if (_clientType == 'cpf' && digits.length != 11)
                return 'CPF deve ter 11 dígitos';
              if (_clientType == 'cnpj' && digits.length != 14)
                return 'CNPJ deve ter 14 dígitos';
              return null;
            },
          ),
        ],
      );
    } else {
      // Motoboy Details
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Detalhes do Entregador', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.lg),
          Text('Categoria do entregador', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'O cadastro será analisado com documentos obrigatórios de acordo com a categoria.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          CategorySelectorWidget(
            isForDriver: true,
            onSelected: (cat) => setState(() => _selectedCategory = cat),
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
            validator: (v) => Validators.cpf(v),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_selectedCategory != null &&
              driverCategoryNeedsRg(_selectedCategory!.category)) ...[
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _rgNumberCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Número do RG',
                hintText: 'Somente números',
                prefixIcon: Icon(
                  Icons.badge_outlined,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
              validator: (v) => Validators.required(v, field: 'Número do RG'),
            ),
          ],
          if (_selectedCategory != null &&
              driverCategoryNeedsPlate(_selectedCategory!.category)) ...[
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
              validator: (v) => Validators.required(v, field: 'Placa'),
            ),
            const SizedBox(height: AppSpacing.lg),
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
                  Validators.required(v, field: 'Modelo do veículo'),
            ),
            const SizedBox(height: AppSpacing.lg),
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
                if (v == null || v.isEmpty)
                  return 'Ano do veículo é obrigatório';
                final year = int.tryParse(v);
                if (year == null || year < 1980 || year > 2035)
                  return 'Ano inválido';
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
                labelText: 'Número de Registro da CNH',
                prefixIcon: Icon(
                  Icons.credit_card_outlined,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
              validator: (v) => Validators.required(v, field: 'Número da CNH'),
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
                  Validators.required(v, field: 'Categoria da CNH'),
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
            const SizedBox(height: AppSpacing.lg),
          ],
          Text('Endereço', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Busque o endereço pelo CEP e informe número e complemento.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _addressZipCtrl,
            focusNode: _addressZipFocus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
              _CepMaskFormatter(),
            ],
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'CEP',
              hintText: '00000-000',
              prefixIcon: _loadingAddress
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.location_searching_rounded,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
              suffixIcon: _addressLabelCtrl.text.trim().isNotEmpty
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.primary,
                      size: 20,
                    )
                  : null,
            ),
            validator: (v) {
              final digits = v?.replaceAll(RegExp(r'\D'), '') ?? '';
              if (digits.length != 8) return 'CEP inválido';
              if (_addressLabelCtrl.text.trim().isEmpty) {
                return 'CEP não encontrado. Verifique e tente novamente';
              }
              return null;
            },
          ),
          if (_addressLabelCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _addressLabelCtrl.text.trim(),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            controller: _addressNumberCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z/-]')),
              LengthLimitingTextInputFormatter(10),
            ],
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textPrimary,
            ),
            decoration: const InputDecoration(
              labelText: 'Número',
              prefixIcon: Icon(
                Icons.numbers_rounded,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ),
            validator: (v) => Validators.required(v, field: 'Número'),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            controller: _addressComplementCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textPrimary,
            ),
            decoration: const InputDecoration(
              labelText: 'Complemento',
              hintText: 'Opcional',
              prefixIcon: Icon(
                Icons.add_home_work_outlined,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildStep3Documents() {
    if (_selectedCategory == null) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Envio de Documentos', style: AppTypography.h3),
        const SizedBox(height: AppSpacing.lg),
        _DocumentsChecklistCard(
          category: _selectedCategory!.category,
          hasIdentityDocument: _identityDocumentFile != null,
          hasSelfieWithDocument: _selfieWithDocumentFile != null,
          hasVehicleDocument: _vehicleDocumentFile != null,
          hasAdditionalPermit: _additionalPermitFile != null,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (driverCategoryNeedsRg(_selectedCategory!.category)) ...[
          _DocumentUploadTile(
            label: 'Foto do documento de identificação',
            subtitle: 'RG com foto (frente e verso)',
            file: _identityDocumentFile,
            onTap: () => _pickDocument((file) => _identityDocumentFile = file),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _DocumentUploadTile(
          label: 'Selfie para reconhecimento facial',
          subtitle: 'A câmera frontal será aberta automaticamente',
          file: _selfieWithDocumentFile,
          onTap: _pickSelfie,
        ),
        if (driverCategoryNeedsVehicleDocument(
          _selectedCategory!.category,
        )) ...[
          const SizedBox(height: AppSpacing.md),
          _DocumentUploadTile(
            label: 'Documento do veículo',
            subtitle: 'Envie o CRLV em PDF',
            file: _vehicleDocumentFile,
            onTap: () =>
                _pickPdfDocument((file) => _vehicleDocumentFile = file),
          ),
        ],
        if (driverCategoryNeedsAdditionalPermit(
          _selectedCategory!.category,
        )) ...[
          const SizedBox(height: AppSpacing.md),
          _DocumentUploadTile(
            label: driverAdditionalPermitLabel(_selectedCategory!.category),
            subtitle: 'Envie a licença complementar exigida para operar',
            file: _additionalPermitFile,
            onTap: () => _pickDocument((file) => _additionalPermitFile = file),
          ),
        ],
      ],
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
  final bool hasVehicleDocument;
  final bool hasAdditionalPermit;

  const _DocumentsChecklistCard({
    required this.category,
    required this.hasIdentityDocument,
    required this.hasSelfieWithDocument,
    required this.hasVehicleDocument,
    required this.hasAdditionalPermit,
  });

  @override
  Widget build(BuildContext context) {
    final items = <({String label, bool done})>[
      if (driverCategoryNeedsRg(category))
        (label: 'Foto do documento de identificação', done: hasIdentityDocument),
      (label: 'Selfie para reconhecimento facial', done: hasSelfieWithDocument),
      if (driverCategoryNeedsVehicleDocument(category))
        (label: 'Documento do veículo em PDF', done: hasVehicleDocument),
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


// ── Conta dígitos antes de [upToOffset] no texto bruto ────────
int _digitsBeforeOffset(String text, int upToOffset) {
  int count = 0;
  final end = upToOffset.clamp(0, text.length);
  for (int i = 0; i < end; i++) {
    final c = text.codeUnitAt(i);
    if (c >= 48 && c <= 57) count++;
  }
  return count;
}

// ── Posição no texto formatado após [targetDigits] dígitos ────
int _cursorAfterDigits(String text, int targetDigits) {
  int count = 0;
  for (int i = 0; i < text.length; i++) {
    if (count == targetDigits) return i;
    final c = text.codeUnitAt(i);
    if (c >= 48 && c <= 57) count++;
  }
  return text.length;
}

// ── Formatador de telefone: (XX) XXXXX-XXXX ───────────────────
class _PhoneMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final digitsBeforeCursor = _digitsBeforeOffset(raw, newValue.selection.end);

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
      selection: TextSelection.collapsed(
        offset: _cursorAfterDigits(text, digitsBeforeCursor),
      ),
    );
  }
}

class _CepMaskFormatter extends TextInputFormatter {
  static String format(String digits) {
    final cleaned = digits.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < cleaned.length && i < 8; i++) {
      if (i == 5) buffer.write('-');
      buffer.write(cleaned[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final digitsBeforeCursor = _digitsBeforeOffset(raw, newValue.selection.end);
    final text = format(digits);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: _cursorAfterDigits(text, digitsBeforeCursor),
      ),
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
    final raw = newValue.text;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final digitsBeforeCursor = _digitsBeforeOffset(raw, newValue.selection.end);

    final buffer = StringBuffer();
    for (int i = 0; i < digits.length && i < 11; i++) {
      if (i == 3 || i == 6) buffer.write('.');
      if (i == 9) buffer.write('-');
      buffer.write(digits[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: _cursorAfterDigits(text, digitsBeforeCursor),
      ),
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
    final raw = newValue.text;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final digitsBeforeCursor = _digitsBeforeOffset(raw, newValue.selection.end);

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
      selection: TextSelection.collapsed(
        offset: _cursorAfterDigits(text, digitsBeforeCursor),
      ),
    );
  }
}
