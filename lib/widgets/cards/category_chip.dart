import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/category_item.dart';
import '../../models/product.dart';
import '../ui/ui.dart';
import 'category_art.dart';

/// The prototype's category card (`.cat`): 112px wide white card, 64px art
/// tile, label and an optional "N checks" line. Uses the Lenz category art
/// when the category has one, else the category's SVG/icon on mint.
class CategoryBrowseCard extends StatelessWidget {
  final String label;
  final IconData icon;

  /// If set, renders an SVG asset instead of [icon] (when no [imageAsset]).
  final String? svgAsset;
  final bool isSelected;
  final VoidCallback onTap;

  /// Lenz category artwork (`assets/lenz/categories/...`).
  final String? imageAsset;

  /// Secondary line, e.g. "2 checks".
  final String? caption;

  const CategoryBrowseCard({
    super.key,
    required this.label,
    required this.icon,
    this.svgAsset,
    this.isSelected = false,
    required this.onTap,
    this.imageAsset,
    this.caption,
  });

  factory CategoryBrowseCard.fromItem({
    Key? key,
    required CategoryItem category,
    bool isSelected = false,
    required VoidCallback onTap,
    String? caption,
  }) {
    return CategoryBrowseCard(
      key: key,
      label: category.label,
      icon: category.icon,
      svgAsset: category.svgAsset,
      isSelected: isSelected,
      onTap: onTap,
      imageAsset: LenzCategoryArt.forItem(category),
      caption: caption,
    );
  }

  factory CategoryBrowseCard.fromEnum({
    Key? key,
    required ProductCategory category,
    bool isSelected = false,
    required VoidCallback onTap,
    String? caption,
  }) {
    return CategoryBrowseCard(
      key: key,
      label: category.label,
      icon: CategoryIconHelper.resolveIcon(category.label),
      svgAsset: CategoryIconHelper.resolveSvg(category.label),
      isSelected: isSelected,
      onTap: onTap,
      imageAsset: LenzCategoryArt.forCategory(category),
      caption: caption,
    );
  }

  Widget _art() {
    if (imageAsset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          imageAsset!,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _iconTile(),
        ),
      );
    }
    return _iconTile();
  }

  Widget _iconTile() {
    const color = LenzColors.forest2;
    Widget glyph;
    final svg = svgAsset;
    if (svg != null && svg.toLowerCase().endsWith('.png')) {
      glyph = Image.asset(svg, width: 30, height: 30, color: color);
    } else if (svg != null) {
      glyph = SvgPicture.asset(
        svg,
        width: 30,
        height: 30,
        colorFilter: const ColorFilter.mode(color, BlendMode.srcIn),
      );
    } else {
      glyph = Icon(icon, size: 28, color: color);
    }
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: LenzColors.mint2, borderRadius: BorderRadius.circular(20)),
      alignment: Alignment.center,
      child: glyph,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LenzPressable(
      onTap: onTap,
      pressedScale: .94,
      semanticLabel: caption == null ? label : '$label, $caption',
      child: AnimatedContainer(
        duration: LenzMotion.chip,
        curve: LenzMotion.ease,
        width: 112,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        decoration: BoxDecoration(
          color: LenzColors.paper,
          borderRadius: BorderRadius.circular(LenzRadii.card),
          border: Border.all(
            color: isSelected ? LenzColors.forest2 : LenzColors.line,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: LenzShadows.sh1,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _art(),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: LenzText.item.copyWith(fontSize: 14),
            ),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(
                caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: LenzText.tiny.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Filter chip in the Lenz style (`.chip` / `.chip.on`).
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
    return LenzChip(label: label, selected: isSelected, onTap: onTap);
  }
}
