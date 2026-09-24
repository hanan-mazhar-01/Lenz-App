import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'product.dart';

/// Helper to map category names and keywords to appropriate luxury icons.
class CategoryIconHelper {
  static String? resolveSvg(String categoryName) {
    final lower = categoryName.trim().toLowerCase();
    if (lower.contains('sneak') || lower.contains('shoe') || lower.contains('footwear') || lower.contains('boot') || lower.contains('loafer') || lower.contains('heel')) {
      return 'assets/icons/ic_sneakers.png';
    } else if (lower.contains('bag') || lower.contains('purse') || lower.contains('backpack') || lower.contains('tote') || lower.contains('wallet')) {
      return 'assets/icons/ic_bags.svg';
    } else if (lower.contains('watch') || lower.contains('clock') || lower.contains('timepiece')) {
      return 'assets/icons/ic_watches.svg';
    } else if (lower.contains('cloth') || lower.contains('apparel') || lower.contains('shirt') || lower.contains('jacket') || lower.contains('hoodie') || lower.contains('coat') || lower.contains('dress') || lower.contains('pant')) {
      return 'assets/icons/ic_clothing.svg';
    } else if (lower.contains('access') || lower.contains('belt') || lower.contains('hat') || lower.contains('cap') || lower.contains('scarf') || lower.contains('glove') || lower.contains('glass') || lower.contains('eyewear') || lower.contains('sunglass')) {
      return 'assets/icons/ic_accessories.svg';
    }
    return null;
  }

  static IconData resolveIcon(String categoryName) {
    final lower = categoryName.trim().toLowerCase();
    if (lower.contains('sneak') || lower.contains('shoe') || lower.contains('footwear') || lower.contains('boot') || lower.contains('loafer') || lower.contains('heel')) {
      return Icons.hiking_rounded;
    } else if (lower.contains('bag') || lower.contains('purse') || lower.contains('backpack') || lower.contains('tote') || lower.contains('wallet')) {
      return CupertinoIcons.bag;
    } else if (lower.contains('watch') || lower.contains('clock') || lower.contains('timepiece')) {
      return CupertinoIcons.time;
    } else if (lower.contains('cloth') || lower.contains('apparel') || lower.contains('shirt') || lower.contains('jacket') || lower.contains('hoodie') || lower.contains('coat') || lower.contains('dress') || lower.contains('pant')) {
      return Icons.checkroom_rounded;
    } else if (lower.contains('jewel') || lower.contains('ring') || lower.contains('necklace') || lower.contains('bracelet') || lower.contains('gold') || lower.contains('diamond')) {
      return Icons.diamond_outlined;
    } else if (lower.contains('access') || lower.contains('belt') || lower.contains('hat') || lower.contains('cap') || lower.contains('scarf') || lower.contains('glove')) {
      return CupertinoIcons.sparkles;
    } else if (lower.contains('elect') || lower.contains('phone') || lower.contains('headphone') || lower.contains('earbud') || lower.contains('gadget') || lower.contains('laptop') || lower.contains('camera')) {
      return CupertinoIcons.device_phone_portrait;
    } else if (lower.contains('perfum') || lower.contains('fragran') || lower.contains('cologne') || lower.contains('scent')) {
      return Icons.sanitizer_outlined;
    } else if (lower.contains('art') || lower.contains('paint') || lower.contains('sculpture')) {
      return CupertinoIcons.paintbrush;
    } else if (lower.contains('card') || lower.contains('game') || lower.contains('toy') || lower.contains('figure') || lower.contains('collect')) {
      return CupertinoIcons.gamecontroller;
    } else if (lower.contains('glass') || lower.contains('eyewear') || lower.contains('sunglass')) {
      return CupertinoIcons.eyeglasses;
    } else if (lower.contains('coin') || lower.contains('currency') || lower.contains('money')) {
      return CupertinoIcons.money_dollar_circle;
    }
    return CupertinoIcons.square_grid_2x2;
  }
}

/// Represents a product category (both standard and dynamically discovered).
class CategoryItem {
  final String id;
  final String label;
  final IconData icon;
  final bool isCustom;
  /// Optional SVG asset path (e.g. 'assets/icons/ic_sneakers.svg').
  /// When provided, the UI renders this SVG instead of [icon].
  final String? svgAsset;

  const CategoryItem({
    required this.id,
    required this.label,
    required this.icon,
    this.isCustom = false,
    this.svgAsset,
  });

  factory CategoryItem.fromProductCategory(ProductCategory cat) {
    return defaults.firstWhere(
      (item) => item.category == cat,
      orElse: () => CategoryItem(
        id: cat.name,
        label: cat.label,
        icon: CategoryIconHelper.resolveIcon(cat.label),
        svgAsset: CategoryIconHelper.resolveSvg(cat.label),
      ),
    );
  }

  /// Maps to standard ProductCategory enum if matching, else null.
  ProductCategory? get category {
    for (final c in ProductCategory.values) {
      if (c.name.toLowerCase() == id.toLowerCase() ||
          c.label.toLowerCase() == label.toLowerCase() ||
          (id.toLowerCase() == 'shoes' && (c.name == 'sneakers' || c.label.toLowerCase() == 'sneakers')) ||
          (id.toLowerCase() == 'sneakers' && (c.name == 'sneakers' || c.label.toLowerCase() == 'sneakers'))) {
        return c;
      }
    }
    return null;
  }

  /// The standard 5 foundational luxury categories.
  static final List<CategoryItem> defaults = [
    const CategoryItem(
      id: 'shoes',
      label: 'Shoes',
      icon: Icons.hiking_rounded,
      svgAsset: 'assets/icons/ic_sneakers.png',
      isCustom: false,
    ),
    const CategoryItem(
      id: 'bags',
      label: 'Bags',
      icon: CupertinoIcons.bag,
      svgAsset: 'assets/icons/ic_bags.svg',
      isCustom: false,
    ),
    const CategoryItem(
      id: 'watches',
      label: 'Watches',
      icon: CupertinoIcons.time,
      svgAsset: 'assets/icons/ic_watches.svg',
      isCustom: false,
    ),
    const CategoryItem(
      id: 'clothing',
      label: 'Clothing',
      icon: Icons.checkroom_rounded,
      svgAsset: 'assets/icons/ic_clothing.svg',
      isCustom: false,
    ),
    const CategoryItem(
      id: 'accessories',
      label: 'Accessories',
      icon: CupertinoIcons.sparkles,
      svgAsset: 'assets/icons/ic_accessories.svg',
      isCustom: false,
    ),
  ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'iconCode': icon.codePoint,
        'isCustom': isCustom,
        'svgAsset': svgAsset,
      };

  factory CategoryItem.fromJson(Map<String, dynamic> json) {
    final label = (json['label'] as String?)?.trim() ?? 'Item';
    final id = (json['id'] as String?)?.trim() ?? label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final svgAsset = (json['svgAsset'] as String?) ?? CategoryIconHelper.resolveSvg(label);
    return CategoryItem(
      id: id,
      label: label,
      icon: CategoryIconHelper.resolveIcon(label),
      isCustom: json['isCustom'] as bool? ?? true,
      svgAsset: svgAsset,
    );
  }

  factory CategoryItem.fromName(String name) {
    final clean = name.trim();
    final id = clean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    return CategoryItem(
      id: id,
      label: clean,
      icon: CategoryIconHelper.resolveIcon(clean),
      isCustom: true,
      svgAsset: CategoryIconHelper.resolveSvg(clean),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryItem &&
          runtimeType == other.runtimeType &&
          id.toLowerCase() == other.id.toLowerCase();

  @override
  int get hashCode => id.toLowerCase().hashCode;
}

