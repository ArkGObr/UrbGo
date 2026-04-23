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

      final description = _descriptionController.text.trim();

      await Supabase.instance.client
          .from('motoboys')
          .update({'avatar_url': avatarUrl, 'description': description})
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
}
