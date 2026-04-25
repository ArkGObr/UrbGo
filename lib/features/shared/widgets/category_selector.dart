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
            width: (MediaQuery.of(context).size.width - 60) / 3,
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: 4,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
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
            child: Stack(
              children: [
                Column(
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
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      cat.name,
                      textAlign: TextAlign.center,
                      style: AppTypography.labelSmall.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
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
                    // Badges de atributos
                    if (!widget.isForDriver) ...[
                      const SizedBox(height: 4),
                      _CategoryBadges(cat: cat, isSelected: isSelected),
                    ],
                  ],
                ),

                // Ícone ajudante (helper) — canto superior direito
                if (cat.helperSupported)
                  Positioned(
                    top: 0,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : AppColors.surfaceBorder,
                          width: 0.5,
                        ),
                      ),
                      child: Icon(
                        Icons.people_rounded,
                        size: 10,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CategoryBadges extends StatelessWidget {
  final VehicleCategoryInfo cat;
  final bool isSelected;

  const _CategoryBadges({required this.cat, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final badges = <_Badge>[];

    if (cat.isEco) {
      badges.add(const _Badge(
        label: 'Eco',
        icon: Icons.eco_rounded,
        color: Color(0xFF4CAF50),
      ));
    }
    if (cat.isMotoTaxi) {
      badges.add(const _Badge(
        label: 'Corrida',
        icon: Icons.person_rounded,
        color: Color(0xFF2196F3),
      ));
    }
    if (cat.helperSupported) {
      badges.add(const _Badge(
        label: 'Ajudante',
        icon: Icons.handshake_rounded,
        color: Color(0xFFFF9800),
      ));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 2,
      children: badges.map((b) => _BadgeChip(badge: b, isSelected: isSelected)).toList(),
    );
  }
}

class _Badge {
  final String label;
  final IconData icon;
  final Color color;
  const _Badge({required this.label, required this.icon, required this.color});
}

class _BadgeChip extends StatelessWidget {
  final _Badge badge;
  final bool isSelected;

  const _BadgeChip({required this.badge, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: isSelected ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: badge.color.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 8, color: badge.color),
          const SizedBox(width: 2),
          Text(
            badge.label,
            style: TextStyle(
              fontSize: 8,
              color: badge.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
