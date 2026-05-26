import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/cep_service.dart';
import '../../../core/services/document_picker_service.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/driver_registration_rules.dart';
import '../domain/motoboy_providers.dart';

class MotoboyProfileScreen extends ConsumerStatefulWidget {
  const MotoboyProfileScreen({super.key});

  @override
  ConsumerState<MotoboyProfileScreen> createState() =>
      _MotoboyProfileScreenState();
}

class _MotoboyProfileScreenState extends ConsumerState<MotoboyProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _addressZipCodeController = TextEditingController();
  final _addressNumberController = TextEditingController();
  final _addressComplementController = TextEditingController();
  final _addressLabelController = TextEditingController();

  bool _isLoading = false;
  bool _loadingCep = false;
  File? _selectedImage;
  String? _currentAvatarUrl;
  File? _crlvFile;
  File? _identityImage;
  File? _selfieImage;
  String? _currentCrlvUrl;
  String? _currentIdentityUrl;
  String? _currentSelfieUrl;

  Timer? _cepDebounce;

  @override
  void initState() {
    super.initState();
    _addressZipCodeController.addListener(_onCepChanged);
    // Inicia ouvindo a description e foto se já tiver
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final m = ref.read(motoboyStreamProvider).valueOrNull;
      if (m != null) {
        _descriptionController.text = m.description ?? '';
        setState(() {
          _currentAvatarUrl = m.avatarUrl;
          _currentCrlvUrl = m.vehicleDocumentUrl;
          _currentIdentityUrl = m.identityDocumentUrl;
          _currentSelfieUrl = m.selfieWithDocumentUrl;
        });
        _addressZipCodeController.text = m.addressZipCode ?? '';
        _addressNumberController.text = m.addressNumber ?? '';
        _addressComplementController.text = m.addressComplement ?? '';
        _addressLabelController.text = m.addressLabel ?? '';
      }
    });
  }

  @override
  void dispose() {
    _cepDebounce?.cancel();
    _descriptionController.dispose();
    _addressZipCodeController.dispose();
    _addressNumberController.dispose();
    _addressComplementController.dispose();
    _addressLabelController.dispose();
    super.dispose();
  }

  void _onCepChanged() {
    final digits = _addressZipCodeController.text.replaceAll(RegExp(r'\D'), '');
    // Só busca se o usuário DIGITOU (não se foi preenchido programaticamente ao carregar)
    if (digits.length != 8) return;

    // Não rebusca se o label já está preenchido com o mesmo CEP
    _cepDebounce?.cancel();
    _cepDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() => _loadingCep = true);
      final result = await CepService.lookup(digits);
      if (!mounted) return;
      setState(() {
        _loadingCep = false;
        if (result != null && _addressLabelController.text.trim().isEmpty) {
          _addressLabelController.text = result.label;
        }
      });
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
      });
    }
  }

  Future<void> _pickDocumentImage(int docType) async {
    // CRLV é sempre PDF
    if (docType == 2) {
      final file = await DocumentPickerService().pickPdf();
      if (file != null) setState(() => _crlvFile = file);
      return;
    }

    // Selfie: câmera frontal direta
    if (docType == 4) {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
      );
      if (picked != null) setState(() => _selfieImage = File(picked.path));
      return;
    }

    // Documento de identidade: câmera ou galeria
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
    );
    if (picked != null) setState(() => _identityImage = File(picked.path));
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Não autenticado.');
      final motoboy = ref.read(motoboyStreamProvider).valueOrNull!;
      final ownerName = motoboy.name.trim().isEmpty
          ? 'Motorista'
          : motoboy.name.trim();

      String? avatarUrl = _currentAvatarUrl;

      // Se escolheu uma nova foto, faz o upload para o Storage
      if (_selectedImage != null) {
        final ext = _selectedImage!.path.split('.').last;
        final uploadPath =
            '${user.id}/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';

        await Supabase.instance.client.storage
            .from('avatars')
            .upload(
              uploadPath,
              _selectedImage!,
              fileOptions: const FileOptions(upsert: true),
            );

        avatarUrl = Supabase.instance.client.storage
            .from('avatars')
            .getPublicUrl(uploadPath);
      }

      String? crlvUrl = _currentCrlvUrl;
      if (_crlvFile != null) {
        crlvUrl = await _uploadDriverDocument(
          userId: user.id,
          ownerName: ownerName,
          documentType: 'crlv',
          file: _crlvFile!,
        );
      }

      String? identityUrl = _currentIdentityUrl;
      if (_identityImage != null) {
        identityUrl = await _uploadDriverDocument(
          userId: user.id,
          ownerName: ownerName,
          documentType: 'rg',
          file: _identityImage!,
        );
      }

      String? selfieUrl = _currentSelfieUrl;
      if (_selfieImage != null) {
        selfieUrl = await _uploadDriverDocument(
          userId: user.id,
          ownerName: ownerName,
          documentType: 'selfie_with_document',
          file: _selfieImage!,
        );
      }

      final description = _descriptionController.text.trim();

      // Recalcular aprovação
      final missing = missingDriverRegistrationItems(
        category: motoboy.vehicleCategory,
        cpf: motoboy.cpf ?? '',
        rgNumber: motoboy.rgNumber ?? '',
        vehiclePlate: motoboy.vehiclePlate ?? '',
        vehicleModel: motoboy.vehicleModel ?? '',
        vehicleYear: motoboy.vehicleYear?.toString() ?? '',
        cnhNumber: motoboy.cnhNumber ?? '',
        cnhCategory: motoboy.cnhCategory ?? '',
        cnhExpirationDate: motoboy.cnhExpirationDate,
        addressZipCode: _addressZipCodeController.text.replaceAll(
          RegExp(r'\D'),
          '',
        ),
        addressNumber: _addressNumberController.text.trim(),
        addressLabel: _addressLabelController.text.trim(),
        hasIdentityDocument: identityUrl != null && identityUrl.isNotEmpty,
        hasSelfieWithDocument: selfieUrl != null && selfieUrl.isNotEmpty,
        hasVehicleDocument: crlvUrl != null && crlvUrl.isNotEmpty,
        hasAdditionalPermit:
            motoboy.additionalPermitUrl != null &&
            motoboy.additionalPermitUrl!.isNotEmpty,
      );

      final newStatus = missing.isEmpty
          ? 'pending_review'
          : 'pending_documents';

      await Supabase.instance.client
          .from('motoboys')
          .update({
            'avatar_url': avatarUrl,
            'description': description,
            'vehicle_document_url': crlvUrl,
            'identity_document_url': identityUrl,
            'selfie_with_document_url': selfieUrl,
            'address_zip_code': _addressZipCodeController.text.replaceAll(
              RegExp(r'\D'),
              '',
            ),
            'address_number': _addressNumberController.text.trim(),
            'address_complement':
                _addressComplementController.text.trim().isEmpty
                ? null
                : _addressComplementController.text.trim(),
            'address_label': _addressLabelController.text.trim(),
            'approval_status': newStatus,
          })
          .eq('id', user.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Perfil atualizado com sucesso!',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.background,
              ),
            ),
            backgroundColor: AppColors.primary,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao salvar: $e',
              style: AppTypography.bodyMedium,
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String> _uploadDriverDocument({
    required String userId,
    required String ownerName,
    required String documentType,
    required File file,
  }) async {
    final ext = file.path.split('.').last;
    final mimeType = _mimeTypeForExtension(ext);
    final path =
        '$userId/${documentType}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await Supabase.instance.client.storage
        .from('driver-documents')
        .upload(
          path,
          file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: mimeType,
            metadata: {
              'owner_name': ownerName,
              'document_type': documentType,
              'mime_type': mimeType,
            },
          ),
        );

    return path;
  }

  String _mimeTypeForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      case 'heic':
        return 'image/heic';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'Meu Perfil',
          style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SafeArea(
        child: ref
            .watch(motoboyStreamProvider)
            .when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (motoboy) => SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Stack(
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceHigh,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                                image: _selectedImage != null
                                    ? DecorationImage(
                                        image: FileImage(_selectedImage!),
                                        fit: BoxFit.cover,
                                      )
                                    : (_currentAvatarUrl != null &&
                                          _currentAvatarUrl!.isNotEmpty)
                                    ? DecorationImage(
                                        image: NetworkImage(_currentAvatarUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child:
                                  (_selectedImage == null &&
                                      (_currentAvatarUrl == null ||
                                          _currentAvatarUrl!.isEmpty))
                                  ? const Center(
                                      child: Icon(
                                        Icons.person_outline,
                                        size: 50,
                                        color: AppColors.textTertiary,
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _pickImage,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    size: 20,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Sua foto inspira maior confiança aos clientes',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl2),
                      Container(
                        padding: AppSpacing.cardPadding,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.surfaceBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: motoboy.reputation.color.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                              child: Icon(
                                motoboy.reputation.icon,
                                color: motoboy.reputation.color,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Nível ${motoboy.reputation.label}',
                                    style: AppTypography.labelLarge,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${motoboy.avgRating.toStringAsFixed(1)} estrelas • ${motoboy.totalRatings} avaliações',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl2),

                      Text(
                        'Mensagem do Entregador',
                        style: AppTypography.h4.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Escreva algo legal sobre o seu trabalho. Essa mensagem aparece para o cliente quando ele solicitar.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Ex: Prezo pela agilidade e cuidado com sua entrega!',
                          hintStyle: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textTertiary,
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceHigh,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(
                              color: AppColors.surfaceBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(
                              color: AppColors.surfaceBorder,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'A descrição é obrigatória.';
                          }
                          if (val.trim().length < 10) {
                            return 'Escreva pelo menos 10 caracteres.';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: AppSpacing.xl3),

                      Text(
                        'Endereço',
                        style: AppTypography.h4.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Mantenha o CEP, número e complemento atualizados.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _addressZipCodeController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: InputDecoration(
                          labelText: 'CEP',
                          hintText: '00000000',
                          prefixIcon: _loadingCep
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
                              : const Icon(Icons.pin_drop_outlined),
                        ),
                        validator: (value) {
                          final digits =
                              value?.replaceAll(RegExp(r'\D'), '') ?? '';
                          if (digits.length != 8) return 'CEP inválido.';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _addressLabelController,
                        decoration: const InputDecoration(
                          labelText: 'Endereço (preenchido pelo CEP)',
                          hintText: 'Digite o CEP acima para preencher',
                          prefixIcon: Icon(Icons.map_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe o endereço base do CEP.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _addressNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Número',
                          prefixIcon: Icon(Icons.numbers_rounded),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe o número.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _addressComplementController,
                        decoration: const InputDecoration(
                          labelText: 'Complemento',
                          hintText: 'Opcional',
                          prefixIcon: Icon(Icons.add_home_work_outlined),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xl3),

                      Text(
                        'Documentos',
                        style: AppTypography.h4.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Verifique e atualize seus documentos obrigatórios.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (driverCategoryNeedsRg(motoboy.vehicleCategory)) ...[
                        _buildDocumentItem(
                          title: 'Foto do RG (Frente e Verso)',
                          file: _identityImage,
                          currentUrl: _currentIdentityUrl,
                          onTap: () => _pickDocumentImage(3),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _buildDocumentItem(
                        title: 'Selfie para Reconhecimento Facial',
                        file: _selfieImage,
                        currentUrl: _currentSelfieUrl,
                        onTap: () => _pickDocumentImage(4),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (driverCategoryNeedsVehicleDocument(
                        motoboy.vehicleCategory,
                      )) ...[
                        _buildDocumentItem(
                          title: 'Documento do Veículo (CRLV em PDF)',
                          file: _crlvFile,
                          currentUrl: _currentCrlvUrl,
                          onTap: () => _pickDocumentImage(2),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      const SizedBox(height: AppSpacing.xl3),

                      PrimaryButton(
                        label: 'Salvar Perfil',
                        isLoading: _isLoading,
                        onPressed: _saveProfile,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildDocumentItem({
    required String title,
    required File? file,
    required String? currentUrl,
    required VoidCallback onTap,
  }) {
    final hasDoc =
        file != null || (currentUrl != null && currentUrl.isNotEmpty);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: hasDoc
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                hasDoc
                    ? Icons.check_circle_rounded
                    : Icons.insert_drive_file_outlined,
                color: hasDoc ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    hasDoc
                        ? 'Enviado (Toque para trocar)'
                        : 'Toque para enviar',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
