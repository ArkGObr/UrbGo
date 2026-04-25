import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../auth/domain/auth_provider.dart';
import '../../data/rating_repository.dart';
import '../../domain/delivery_model.dart';

class RatingBottomSheet extends ConsumerStatefulWidget {
  final DeliveryModel delivery;

  const RatingBottomSheet({super.key, required this.delivery});

  static Future<void> show(BuildContext context, WidgetRef ref, DeliveryModel delivery) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      isDismissible: false,
      enableDrag: false,
      builder: (_) => RatingBottomSheet(delivery: delivery),
    );
  }

  @override
  ConsumerState<RatingBottomSheet> createState() => _RatingBottomSheetState();
}

class _RatingBottomSheetState extends ConsumerState<RatingBottomSheet> {
  int _selectedRating = 0;
  final _commentCtrl = TextEditingController();
  bool _isSubmitting = false;

  static const _labels = ['', 'Muito ruim', 'Ruim', 'Regular', 'Bom', 'Excelente'];
  static const _emojis = ['', '😤', '😕', '😐', '😊', '🤩'];

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedRating == 0) return;
    final user = ref.read(authNotifierProvider).valueOrNull;
    if (user == null || widget.delivery.motoboyId == null) return;

    setState(() => _isSubmitting = true);
    try {
      await RatingRepository().submitRating(
        deliveryId: widget.delivery.id,
        clientId: user.id,
        motoboyId: widget.delivery.motoboyId!,
        rating: _selectedRating,
        comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar avaliação: $e'),
            backgroundColor: AppColors.surface,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: SafeArea(
        top: false,
        child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl2),

            // Ícone de serviço concluído
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryDeep,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              widget.delivery.isMotoTaxi
                  ? 'Corrida Concluída!'
                  : 'Entrega Concluída!',
              style: AppTypography.h2,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Como foi a experiência com ${widget.delivery.motoboyName ?? 'o ${widget.delivery.driverLabel.toLowerCase()}'}?',
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl2),

            // Estrelas
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRating = star),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      _selectedRating >= star
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 44,
                      color: _selectedRating >= star
                          ? const Color(0xFFFFC107)
                          : AppColors.textTertiary,
                    ),
                  ),
                );
              }),
            ),

            // Label da nota
            const SizedBox(height: AppSpacing.sm),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _selectedRating > 0
                  ? Text(
                      '${_emojis[_selectedRating]}  ${_labels[_selectedRating]}',
                      key: ValueKey(_selectedRating),
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    )
                  : const SizedBox(height: 20, key: ValueKey(0)),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Campo de comentário
            TextField(
              controller: _commentCtrl,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
              maxLines: 3,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: 'Deixe um comentário (opcional)',
                hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.background,
                counterStyle: AppTypography.labelSmall.copyWith(color: AppColors.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(AppSpacing.md),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Botão enviar
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_selectedRating == 0 || _isSubmitting) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.surfaceBorder,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: AppColors.background,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Enviar Avaliação',
                        style: AppTypography.button.copyWith(color: AppColors.background),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Pular
            TextButton(
              onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
              child: Text(
                'Pular',
                style: AppTypography.labelLarge.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
      ),
    );
  }
}
