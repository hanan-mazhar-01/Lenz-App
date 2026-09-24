import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/category_item.dart';
import '../../models/product.dart';

class CategoryBrowseCard extends StatelessWidget {
  final String label;
  final IconData icon;
  /// If set, renders an SVG asset instead of [icon].
  final String? svgAsset;
  final bool isSelected;
  final VoidCallback onTap;

  const CategoryBrowseCard({
    super.key,
    required this.label,
    required this.icon,
    this.svgAsset,
    this.isSelected = false,
    required this.onTap,
  });

  factory CategoryBrowseCard.fromItem({
    Key? key,
    required CategoryItem category,
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
    return CategoryBrowseCard(
      key: key,
      label: category.label,
      icon: category.icon,
      svgAsset: category.svgAsset,
      isSelected: isSelected,
      onTap: onTap,
    );
  }

  factory CategoryBrowseCard.fromEnum({
    Key? key,
    required ProductCategory category,
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
    return CategoryBrowseCard(
      key: key,
      label: category.label,
      icon: CategoryIconHelper.resolveIcon(category.label),
      svgAsset: CategoryIconHelper.resolveSvg(category.label),
      isSelected: isSelected,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = isSelected ? Colors.white : AppColors.deepForestGreen;

    Widget iconWidget;
    if (svgAsset != null) {
      if (svgAsset!.toLowerCase().endsWith('.png')) {
        iconWidget = Image.asset(
          svgAsset!,
          width: 30,
          height: 30,
          fit: BoxFit.contain,
          color: iconColor,
        );
      } else {
        iconWidget = SvgPicture.asset(
          svgAsset!,
          width: 30,
          height: 30,
          colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
        );
      }
    } else {
      iconWidget = Icon(icon, size: 26, color: iconColor);
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.deepForestGreen : AppColors.veryLightWarmGray,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.deepForestGreen : const Color(0xFFE8E2DD),
                  width: isSelected ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? AppColors.deepForestGreen.withOpacity(0.22)
                        : AppColors.nearBlack.withOpacity(0.04),
                    blurRadius: isSelected ? 10 : 6,
                    offset: Offset(0, isSelected ? 3 : 2),
                  ),
                ],
              ),
              child: Center(child: iconWidget),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.nearBlack : AppColors.charcoalGray,
                fontSize: 11.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const CategoryFilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.buttonDark : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppColors.border,
            width: 1,
          ),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: AppColors.shadowMedium,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTypography.callout.copyWith(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}
