enum ProductCategory {
  sneakers('Shoes'),
  bags('Bags'),
  watches('Watches'),
  clothing('Clothing'),
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

  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.category,
    this.customCategory,
    required this.imageAsset,
    this.identificationConfidence = 0.92,
  });

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
    );
  }
}

