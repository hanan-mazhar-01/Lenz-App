import 'product_identity.dart';

enum ProductCategory {
  sneakers('Shoes'),
  bags('Bags'),
  watches('Watches'),
  clothing('Clothing'),
  wallets('Wallets'),
  eyewear('Eyewear'),
  accessories('Accessories');

  final String label;
  const ProductCategory(this.label);
}

class Product {
  final String id;
  final String name;
  final String brand;
  final String model;
  final ProductCategory category;
  final String? customCategory;
  final String imageAsset;
  final double identificationConfidence;

  /// Fine-grained inspection code from identification, e.g. SUNGLASSES vs
  /// EYEGLASSES or SNEAKER vs SHOE. Null for reports from engine v1.
  final String? categoryCode;

  /// Per-attribute identity with certainty (engine v3). Null for older reports.
  final ProductIdentity? identity;

  /// Evidence profile used for this product (engine v3).
  final String? profileId;

  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.category,
    this.customCategory,
    required this.imageAsset,
    this.identificationConfidence = 0.92,
    this.categoryCode,
    this.identity,
    this.profileId,
  });

  Product copyWith({
    String? name,
    String? brand,
    String? model,
    String? imageAsset,
    ProductIdentity? identity,
    String? profileId,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        brand: brand ?? this.brand,
        model: model ?? this.model,
        category: category,
        customCategory: customCategory,
        imageAsset: imageAsset ?? this.imageAsset,
        identificationConfidence: identificationConfidence,
        categoryCode: categoryCode,
        identity: identity ?? this.identity,
        profileId: profileId ?? this.profileId,
      );

  /// Display placeholders used when identification couldn't read a brand or
  /// model. They are UI copy only and must never be treated as facts.
  static const String unidentifiedBrand = 'Luxury';
  static const String unidentifiedModel = 'Standard';

  bool get hasIdentifiedBrand => brand.trim().isNotEmpty && brand != unidentifiedBrand;
  bool get hasIdentifiedModel => model.trim().isNotEmpty && model != unidentifiedModel;

  String get categoryLabel => customCategory ?? category.label;

  String get subtitle => '$categoryLabel · $brand';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'model': model,
      'category': category.name,
      if (customCategory != null) 'customCategory': customCategory,
      'imageAsset': imageAsset,
      'identificationConfidence': identificationConfidence,
      if (categoryCode != null) 'categoryCode': categoryCode,
      if (identity != null) 'identity': identity!.toJson(),
      if (profileId != null) 'profileId': profileId,
    };
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    ProductCategory cat = ProductCategory.accessories;
    final catStr = (json['category'] as String?)?.toLowerCase().trim() ?? '';
    bool foundStandard = false;
    for (final c in ProductCategory.values) {
      if (c.name.toLowerCase() == catStr || c.label.toLowerCase() == catStr) {
        cat = c;
        foundStandard = true;
        break;
      }
    }

    String? customCat = json['customCategory'] as String?;
    if (customCat == null && !foundStandard && catStr.isNotEmpty && catStr != 'unknown') {
      customCat = json['category'] as String?;
    }

    return Product(
      id: json['id'] as String? ?? 'p_custom',
      name: json['name'] as String? ?? 'Luxury Item',
      brand: json['brand'] as String? ?? 'Unknown',
      model: json['model'] as String? ?? 'Unknown Model',
      category: cat,
      customCategory: customCat,
      imageAsset: json['imageAsset'] as String? ?? '',
      identificationConfidence: (json['identificationConfidence'] as num?)?.toDouble() ?? 0.9,
      categoryCode: json['categoryCode'] as String?,
      identity: json['identity'] is Map
          ? ProductIdentity.fromJson(Map<String, dynamic>.from(json['identity'] as Map))
          : null,
      profileId: json['profileId'] as String?,
    );
  }
}

