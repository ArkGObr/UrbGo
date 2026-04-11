import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/utils/currency_formatter.dart';

class CategorySelectorWidget extends StatefulWidget {
  final void Function(VehicleCategoryInfo) onSelected;
  final VehicleCategoryInfo? initialValue;
  /// isForDriver=true: entregador cadastrando (sem mostrar preço)
  /// isForDriver=false: cliente escolhendo (mostra "a partir de R$ X")
  final bool isForDriver;

  const CategorySelectorWidget({
    super.key,
    required this.onSelected,
    this.initialValue,
    this.isForDriver = false,
  });

  @override
  State<CategorySelectorWidget> createState() => _CategorySelectorWidgetState();
}

class _CategorySelectorWidgetState extends State<CategorySelectorWidget> {
  VehicleCategoryInfo? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
  }

  void _openSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryBottomSheet(
        selected: _selected,
        isForDriver: widget.isForDriver,
        onSelected: (cat) {
          setState(() => _selected = cat);
          widget.onSelected(cat);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openSelector,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: _selected != null
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.surfaceBorder,
            width: _selected != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _selected?.icon ?? Icons.local_shipping_rounded,
              size: 22,
              color: _selected != null
                  ? AppColors.primary
                  : AppColors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _selected != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selected!.name,
                          style: AppTypography.labelLarge.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selected!.capacity,
                          style: AppTypography.bodySmall.copyWith(
                            fontSize: 11,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      widget.isForDriver
                          ? 'Selecione o tipo de veículo'
                          : 'Selecione a categoria',
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.textTertiary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom Sheet ────────────────────────────────────────────────
class _CategoryBottomSheet extends StatelessWidget {
  final VehicleCategoryInfo? selected;
  final bool isForDriver;
  final void Function(VehicleCategoryInfo) onSelected;

  const _CategoryBottomSheet({
    required this.selected,
    required this.isForDriver,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.md),
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceBorder,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          const SizedBox(height: AppSpacing.xl2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl2),
            child: Text(
              isForDriver ? 'Tipo de veículo' : 'Categoria de entrega',
              style: AppTypography.h3,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ...vehicleCategories.map((cat) {
            final isSelected = selected?.id == cat.id;
            return _CategoryOption(
              category: cat,
              isSelected: isSelected,
              isForDriver: isForDriver,
              onTap: () => onSelected(cat),
            );
          }),
          SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.lg),
        ],
      ),
    );
  }
}

// ── Category Option Item ──────────────────────────────────────
class _CategoryOption extends StatelessWidget {
  final VehicleCategoryInfo category;
  final bool isSelected;
  final bool isForDriver;
  final VoidCallback onTap;

  const _CategoryOption({
    required this.category,
    required this.isSelected,
    required this.isForDriver,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl2,
          vertical: AppSpacing.xs,
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryDeep : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
            width: isSelected ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          children: [
            // Ícone
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                category.icon,
                size: 24,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            // Textos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    style: AppTypography.labelLarge.copyWith(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    category.description,
                    style: AppTypography.bodySmall.copyWith(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Preço / Capacidade
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isForDriver)
                  Text(
                    CurrencyFormatter.format(PriceCalculator.minFare(category)),
                    style: AppTypography.numericMedium.copyWith(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                Text(
                  category.capacity,
                  style: AppTypography.bodySmall.copyWith(fontSize: 10),
                ),
              ],
            ),
            // Check
            if (isSelected) ...[
              const SizedBox(width: AppSpacing.md),
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
