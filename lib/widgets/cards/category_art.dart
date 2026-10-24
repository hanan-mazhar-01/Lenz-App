import 'package:flutter/material.dart';

import '../../models/authentication_result.dart';
import '../../models/category_item.dart';
import '../../models/product.dart';

/// Maps the app's real categories (standard and discovered ones) onto the
/// prototype's category artwork in `assets/lenz/categories/`.
///
/// Presentation only: returns `null` for categories the artwork does not
/// cover, in which case callers fall back to the category's [IconData].
abstract final class LenzCategoryArt {
  static const String _dir = 'assets/lenz/categories';
  static const String bags = '$_dir/cat_bags.png';
  static const String sneakers = '$_dir/cat_sneakers.png';
  static const String watches = '$_dir/cat_watches.png';
  static const String clothing = '$_dir/cat_clothing.png';
  static const String accessories = '$_dir/cat_accessories.png';

  /// Artwork for free-form category text (id and/or label).
  static String? forText(String text) {
    final s = text.toLowerCase();
    bool has(List<String> words) => words.any(s.contains);
    if (has(const ['sneak', 'shoe', 'footwear', 'boot', 'loafer', 'heel', 'trainer'])) {
      return sneakers;
    }
    if (has(const ['bag', 'purse', 'backpack', 'tote', 'wallet', 'clutch'])) {
      return bags;
    }
    if (has(const ['watch', 'clock', 'timepiece'])) return watches;
    if (has(const [
      'cloth',
      'apparel',
      'shirt',
      'jacket',
      'hoodie',
      'coat',
      'dress',
      'pant',
      'jersey',
    ])) {
      return clothing;
    }
    if (has(const [
      'access',
      'belt',
      'hat',
      'cap',
      'scarf',
      'glove',
      'glass',
      'eyewear',
      'jewel',
      'ring',
      'necklace',
      'bracelet',
    ])) {
      return accessories;
    }
    return null;
  }

  static String? forItem(CategoryItem item) => forText('${item.id} ${item.label}');

  static String? forCategory(ProductCategory category) =>
      forText('${category.name} ${category.label}');

  static String? forProduct(Product product) =>
      forText('${product.category.name} ${product.categoryLabel}');

  static String? forReport(AuthenticationReport report) => forProduct(report.product);
}

/// The category artwork at [size], or [fallbackIcon] in forest green when the
/// category has no artwork.
class LenzCategoryArtImage extends StatelessWidget {
  const LenzCategoryArtImage({
    super.key,
    required this.asset,
    required this.fallbackIcon,
    this.size = 46,
  });

  final String? asset;
  final IconData fallbackIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(fallbackIcon, size: size * .52, color: const Color(0xFF1D4C3A));
    if (asset == null) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: icon),
      );
    }
    return Image.asset(
      asset!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => SizedBox.square(
        dimension: size,
        child: Center(child: icon),
      ),
    );
  }
}
