import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
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

  bool _isLoading = false;
  File? _selectedImage;
  String? _currentAvatarUrl;
  File? _cnhImage;
  File? _crlvImage;
  File? _identityImage;
  File? _selfieImage;
  File? _addressImage;
  String? _currentCnhUrl;
  String? _currentCrlvUrl;
  String? _currentIdentityUrl;
  String? _currentSelfieUrl;
  String? _currentAddressUrl;

  @override
  void initState() {
    super.initState();
    // Inicia ouvindo a description e foto se já tiver
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final m = ref.read(motoboyStreamProvider).valueOrNull;
      if (m != null) {
        _descriptionController.text = m.description ?? '';
        setState(() {
          _currentAvatarUrl = m.avatarUrl;
          _currentCnhUrl = m.cnhPhotoUrl;
          _currentCrlvUrl = m.vehicleDocumentUrl;
          _currentIdentityUrl = m.identityDocumentUrl;
          _currentSelfieUrl = m.selfieWithDocumentUrl;
          _currentAddressUrl = m.addressProofUrl;
        });
      }
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
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
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (picked != null) {
      setState(() {
        if (docType == 1) _cnhImage = File(picked.path);
        else if (docType == 2) _crlvImage = File(picked.path);
        else if (docType == 3) _identityImage = File(picked.path);
        else if (docType == 4) _selfieImage = File(picked.path);
        else if (docType == 5) _addressImage = File(picked.path);
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Não autenticado.');

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

      String? cnhUrl = _currentCnhUrl;
      if (_cnhImage != null) {
        final ext = _cnhImage!.path.split('.').last;
        final path = '${user.id}/cnh-${DateTime.now().millisecondsSinceEpoch}.$ext';
        await Supabase.instance.client.storage.from('driver-documents').upload(path, _cnhImage!, fileOptions: const FileOptions(upsert: true));
        cnhUrl = path;
      }

      String? crlvUrl = _currentCrlvUrl;
      if (_crlvImage != null) {
        final ext = _crlvImage!.path.split('.').last;
        final path = '${user.id}/crlv-${DateTime.now().millisecondsSinceEpoch}.$ext';
        await Supabase.instance.client.storage.from('driver-documents').upload(path, _crlvImage!, fileOptions: const FileOptions(upsert: true));
        crlvUrl = path;
      }

      String? identityUrl = _currentIdentityUrl;
      if (_identityImage != null) {
        final ext = _identityImage!.path.split('.').last;
        final path = '${user.id}/identity-${DateTime.now().millisecondsSinceEpoch}.$ext';
        await Supabase.instance.client.storage.from('driver-documents').upload(path, _identityImage!, fileOptions: const FileOptions(upsert: true));
        identityUrl = path;
      }

      String? selfieUrl = _currentSelfieUrl;
      if (_selfieImage != null) {
        final ext = _selfieImage!.path.split('.').last;
        final path = '${user.id}/selfie-${DateTime.now().millisecondsSinceEpoch}.$ext';
        await Supabase.instance.client.storage.from('driver-documents').upload(path, _selfieImage!, fileOptions: const FileOptions(upsert: true));
        selfieUrl = path;
      }

      String? addressUrl = _currentAddressUrl;
      if (_addressImage != null) {
        final ext = _addressImage!.path.split('.').last;
        final path = '${user.id}/addr-${DateTime.now().millisecondsSinceEpoch}.$ext';
        await Supabase.instance.client.storage.from('driver-documents').upload(path, _addressImage!, fileOptions: const FileOptions(upsert: true));
        addressUrl = path;
      }

      final description = _descriptionController.text.trim();

      // Recalcular aprovação
      final motoboy = ref.read(motoboyStreamProvider).valueOrNull!;
      final missing = missingDriverRegistrationItems(
        category: motoboy.vehicleCategory,
        cpf: motoboy.cpf ?? '',
        vehiclePlate: motoboy.vehiclePlate ?? '',
        vehicleModel: motoboy.vehicleModel ?? '',
        vehicleYear: motoboy.vehicleYear?.toString() ?? '',
        cnhNumber: motoboy.cnhNumber ?? '',
        cnhCategory: motoboy.cnhCategory ?? '',
        cnhExpirationDate: motoboy.cnhExpirationDate,
        hasIdentityDocument: identityUrl != null && identityUrl.isNotEmpty,
        hasSelfieWithDocument: selfieUrl != null && selfieUrl.isNotEmpty,
        hasAddressProof: addressUrl != null && addressUrl.isNotEmpty,
        hasCnhPhoto: cnhUrl != null && cnhUrl.isNotEmpty,
        hasVehicleDocument: crlvUrl != null && crlvUrl.isNotEmpty,
        hasAdditionalPermit: motoboy.additionalPermitUrl != null && motoboy.additionalPermitUrl!.isNotEmpty,
      );

      final newStatus = missing.isEmpty ? 'pending_review' : 'pending_documents';

      await Supabase.instance.client
          .from('motoboys')
          .update({
            'avatar_url': avatarUrl,
            'description': description,
            'cnh_photo_url': cnhUrl,
            'vehicle_document_url': crlvUrl,
            'identity_document_url': identityUrl,
            'selfie_with_document_url': selfieUrl,
            'address_proof_url': addressUrl,
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
                      _buildDocumentItem(
                        title: 'Documento de Identidade (Frente e Verso)',
                        file: _identityImage,
                        currentUrl: _currentIdentityUrl,
                        onTap: () => _pickDocumentImage(3),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _buildDocumentItem(
                        title: 'Selfie Segurando Documento',
                        file: _selfieImage,
                        currentUrl: _currentSelfieUrl,
                        onTap: () => _pickDocumentImage(4),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _buildDocumentItem(
                        title: 'Comprovante de Residência',
                        file: _addressImage,
                        currentUrl: _currentAddressUrl,
                        onTap: () => _pickDocumentImage(5),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (driverCategoryNeedsCnh(motoboy.vehicleCategory)) ...[
                        _buildDocumentItem(
                          title: 'CNH',
                          file: _cnhImage,
                          currentUrl: _currentCnhUrl,
                          onTap: () => _pickDocumentImage(1),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (driverCategoryNeedsVehicleDocument(motoboy.vehicleCategory)) ...[
                        _buildDocumentItem(
                          title: 'Documento do Veículo (CRLV)',
                          file: _crlvImage,
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
    final hasDoc = file != null || (currentUrl != null && currentUrl.isNotEmpty);
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
                color: hasDoc ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                hasDoc ? Icons.check_circle_rounded : Icons.insert_drive_file_outlined,
                color: hasDoc ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasDoc ? 'Enviado (Toque para trocar)' : 'Toque para enviar',
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
