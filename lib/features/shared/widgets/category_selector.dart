import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/vehicle_categories.dart';

class CategorySelectorWidget extends StatefulWidget {
  final void Function(VehicleCategoryInfo) onSelected;
  final VehicleCategoryInfo? initialValue;
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

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.md,
      alignment: WrapAlignment.start,
      children: vehicleCategories.map((cat) {
        final isSelected = _selected?.id == cat.id;

        return GestureDetector(
          onTap: () {
            setState(() => _selected = cat);
            widget.onSelected(cat);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: (MediaQuery.of(context).size.width - 60) / 3, // 3 por linha
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: 4,
            ),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 56,
                  child: Center(
                    child: cat.assetPath != null
                        ? Transform.scale(
                            scaleX: -1,
                            child: Image.asset(
                              cat.assetPath!,
                              width: cat.id == 'truck' ? 56 : 46,
                              height: cat.id == 'truck' ? 56 : 46,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Icon(
                            cat.icon,
                            size: cat.id == 'truck' ? 48 : 38,
                            color: isSelected ? AppColors.primary : AppColors.textSecondary,
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  cat.name,
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall.copyWith(
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
                if (!widget.isForDriver) ...[
                  const SizedBox(height: 2),
                  Text(
                    cat.capacity,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
