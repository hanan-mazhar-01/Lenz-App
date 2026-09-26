import '../core/errors/app_error.dart';
import 'product.dart';

enum IdentificationStatus {
  productDetected('product_detected'),
  notProduct('not_product'),
  unusableImage('unusable_image'),
  insufficientEvidence('insufficient_evidence');

  final String value;
  const IdentificationStatus(this.value);

  static IdentificationStatus fromString(String? val) {
    if (val == null) return IdentificationStatus.notProduct;
    final clean = val.trim().toLowerCase();
    switch (clean) {
      case 'product_detected':
      case 'product':
      case 'valid_product':
        return IdentificationStatus.productDetected;
      case 'unusable_image':
      case 'unusable':
        return IdentificationStatus.unusableImage;
      case 'insufficient_evidence':
      case 'insufficient':
      case 'more_details_needed':
        return IdentificationStatus.insufficientEvidence;
      case 'not_product':
      default:
        return IdentificationStatus.notProduct;
    }
  }
}

class ProductIdentification {
  final IdentificationStatus status;
  final String reason;
  final bool productDetected;
  final String? productCategory;
  final String? _brand;
  final String? _product;
  final String? model;
  final String? variant;

  /// Engine v2 inspection code: WATCH, HANDBAG, SNEAKER, SHOE, CLOTHING,
  /// WALLET, ACCESSORY, SUNGLASSES, EYEGLASSES or OTHER.
  final String? categoryCode;
  final double identificationConfidence;
  final List<String> visibleDetails;
  final List<String> missingEvidence;
  final String message;
  final bool isIdentified;

  const ProductIdentification({
    required this.status,
    required this.reason,
    required this.productDetected,
    this.productCategory,
    String? brand,
    String? product,
    this.model,
    this.variant,
    this.categoryCode,
    required this.identificationConfidence,
    this.visibleDetails = const [],
    this.missingEvidence = const [],
    required this.message,
    this.isIdentified = true,
  })  : _brand = brand,
        _product = product;

  String get category => productCategory ?? 'Unknown';
  String get brand => _brand ?? '';
  String get product => _product ?? '';

  factory ProductIdentification.unusable({
    required String reason,
    required String message,
  }) =>
      ProductIdentification(
        status: IdentificationStatus.unusableImage,
        reason: reason,
        productDetected: false,
        identificationConfidence: 0.0,
        message: message,
        isIdentified: false,
      );

  factory ProductIdentification.notProduct({
    required String reason,
    required String message,
  }) =>
      ProductIdentification(
        status: IdentificationStatus.notProduct,
        reason: reason,
        productDetected: false,
        identificationConfidence: 0.0,
        message: message,
        isIdentified: false,
      );

  factory ProductIdentification.fromJson(Map<String, dynamic> json) {
    final rawCat = (json['product_category'] as String? ?? json['category'] as String? ?? '').trim();
    final rawBrand = (json['brand'] as String? ?? '').trim();
    final rawProd = (json['product'] as String? ?? json['product_name'] as String? ?? '').trim();
    final rawCode = (json['category_code'] as String? ?? '').trim().toUpperCase();
    final categoryCode = categoryCodes.contains(rawCode) ? rawCode : null;

    final bool hasValidCategory = rawCat.isNotEmpty &&
        rawCat.toLowerCase() != 'unknown' &&
        rawCat.toLowerCase() != 'not_identifiable';
    final bool hasValidBrand = rawBrand.isNotEmpty &&
        rawBrand.toLowerCase() != 'unknown' &&
        rawBrand.toLowerCase() != 'not_identifiable';

    final statusStr = json['status'] as String?;
    final bool hasExplicitStatus = statusStr != null;
    final IdentificationStatus parsedStatus = hasExplicitStatus
        ? IdentificationStatus.fromString(statusStr)
        : ((hasValidCategory && hasValidBrand)
            ? IdentificationStatus.productDetected
            : IdentificationStatus.notProduct);

    final rawDetected = json['product_detected'];
    bool detected = false;
    if (rawDetected is bool) {
      detected = rawDetected;
    } else if (rawDetected is String) {
      detected = rawDetected.toLowerCase() == 'true';
    } else if (hasExplicitStatus) {
      detected = parsedStatus == IdentificationStatus.productDetected;
    } else {
      detected = parsedStatus == IdentificationStatus.productDetected;
    }

    final reason = (json['reason'] as String? ?? '').trim();
    final message = (json['message'] as String? ?? '').trim();

    final confRaw = json['identification_confidence'] ?? json['confidence'] ?? 0.0;
    double conf = 0.0;
    if (confRaw is num) {
      conf = confRaw.toDouble();
    } else if (confRaw is String) {
      conf = double.tryParse(confRaw) ?? 0.0;
    }
    if (conf > 1.0) conf = conf / 100.0;
    if (conf > 0.99) conf = 0.99;
    if (conf < 0) conf = 0;

    final details = <String>[];
    if (json['visible_details'] is List) {
      for (final item in json['visible_details'] as List) {
        if (item != null && item.toString().trim().isNotEmpty) {
          details.add(item.toString().trim());
        }
      }
    }

    final missing = <String>[];
    if (json['missing_evidence'] is List) {
      for (final item in json['missing_evidence'] as List) {
        if (item != null && item.toString().trim().isNotEmpty) {
          missing.add(item.toString().trim());
        }
      }
    }

    // 1. Unusable Image (Too dark, blank, blurry)
    if (parsedStatus == IdentificationStatus.unusableImage ||
        reason == 'image_too_dark' ||
        reason == 'no_visible_content' ||
        reason == 'insufficient_visual_quality') {
      return ProductIdentification(
        status: IdentificationStatus.unusableImage,
        reason: reason.isNotEmpty ? reason : 'insufficient_visual_quality',
        productDetected: false,
        productCategory: null,
        brand: null,
        product: null,
        model: null,
        variant: null,
        identificationConfidence: conf,
        visibleDetails: details,
        missingEvidence: missing,
        message: message.isNotEmpty
            ? message
            : 'The image is not clear or bright enough to analyze. Please capture a sharper photo.',
        isIdentified: false,
      );
    }

    // 2. Not a supported product (Human, furniture, food, wall, floor, animal, car, etc.)
    if (!detected ||
        parsedStatus == IdentificationStatus.notProduct ||
        reason == 'human_detected' ||
        reason == 'unsupported_object' ||
        !hasValidCategory) {
      return ProductIdentification(
        status: IdentificationStatus.notProduct,
        reason: reason.isNotEmpty ? reason : 'unsupported_object',
        productDetected: false,
        productCategory: null,
        brand: null,
        product: null,
        model: null,
        variant: null,
        identificationConfidence: conf,
        visibleDetails: details,
        missingEvidence: missing,
        message: message.isNotEmpty
            ? message
            : 'No supported luxury product detected. Please scan a luxury item such as a handbag, watch, shoe, wallet, or jewelry.',
        isIdentified: false,
      );
    }

    // 3. Partial or Insufficient Evidence
    if (parsedStatus == IdentificationStatus.insufficientEvidence ||
        reason == 'partial_product_insufficient_evidence' ||
        conf < 0.70) {
      return ProductIdentification(
        status: IdentificationStatus.insufficientEvidence,
        reason: reason.isNotEmpty ? reason : 'partial_product_insufficient_evidence',
        productDetected: false,
        productCategory: (json['product_category'] as String? ?? json['category'] as String?)?.trim(),
        brand: null,
        product: null,
        model: null,
        variant: null,
        identificationConfidence: conf,
        visibleDetails: details,
        missingEvidence: missing,
        message: message.isNotEmpty
            ? message
            : "There isn't enough visible detail to reliably identify this item. Please capture a clearer full-view photo.",
        isIdentified: false,
      );
    }

    // 4. Valid product detected with sufficient confidence (>= 0.70)
    // Check if category is actually a supported luxury item category
    if (rawCat.isEmpty || rawCat.toLowerCase() == 'unknown' || rawCat.toLowerCase() == 'not_identifiable') {
      return ProductIdentification(
        status: IdentificationStatus.notProduct,
        reason: 'unsupported_object',
        productDetected: false,
        productCategory: null,
        brand: null,
        product: null,
        model: null,
        variant: null,
        identificationConfidence: conf,
        visibleDetails: details,
        missingEvidence: missing,
        message: 'Could not detect a supported luxury product in this photo.',
        isIdentified: false,
      );
    }

    final cleanBrand = (rawBrand.isNotEmpty && rawBrand.toLowerCase() != 'unknown' && rawBrand.toLowerCase() != 'not_identifiable')
        ? rawBrand
        : null;

    String cleanProduct;
    if (rawProd.isNotEmpty && rawProd.toLowerCase() != 'unknown' && rawProd.toLowerCase() != 'luxury item' && rawProd.toLowerCase() != 'unknown luxury item') {
      cleanProduct = rawProd;
    } else if (cleanBrand != null) {
      cleanProduct = '$cleanBrand $rawCat';
    } else {
      cleanProduct = rawCat;
    }

    return ProductIdentification(
      status: IdentificationStatus.productDetected,
      reason: reason.isNotEmpty ? reason : 'valid_luxury_product',
      productDetected: true,
      productCategory: rawCat,
      brand: cleanBrand,
      product: cleanProduct,
      model: json['model'] as String?,
      variant: json['variant'] as String?,
      categoryCode: categoryCode,
      identificationConfidence: conf,
      visibleDetails: details,
      missingEvidence: missing,
      message: message.isNotEmpty ? message : 'Item identified successfully.',
      isIdentified: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.value,
        'reason': reason,
        'product_detected': productDetected,
        'product_category': productCategory,
        'brand': _brand,
        'product': _product,
        if (model != null) 'model': model,
        if (variant != null) 'variant': variant,
        if (categoryCode != null) 'category_code': categoryCode,
        'identification_confidence': identificationConfidence,
        'visible_details': visibleDetails,
        'missing_evidence': missingEvidence,
        'message': message,
        'is_identified': isIdentified,
      };

  static const categoryCodes = {
    'WATCH', 'HANDBAG', 'SNEAKER', 'SHOE', 'CLOTHING', 'WALLET',
    'ACCESSORY', 'SUNGLASSES', 'EYEGLASSES', 'OTHER',
  };

  /// The inspection code, falling back to keyword matching on the free-text
  /// category for engine v1 responses.
  String get resolvedCategoryCode {
    if (categoryCode != null) return categoryCode!;
    final l = category.toLowerCase();
    if (l.contains('sunglass')) return 'SUNGLASSES';
    if (l.contains('glasses') || l.contains('eyewear') || l.contains('optical') || l.contains('spectacle') || l.contains('frames')) {
      return 'EYEGLASSES';
    }
    if (l.contains('watch') || l.contains('timepiece')) return 'WATCH';
    if (l.contains('wallet') || l.contains('card holder') || l.contains('cardholder')) return 'WALLET';
    if (l.contains('bag') || l.contains('purse') || l.contains('tote')) return 'HANDBAG';
    if (l.contains('sneaker') || l.contains('trainer')) return 'SNEAKER';
    if (l.contains('shoe') || l.contains('footwear') || l.contains('boot') || l.contains('loafer') || l.contains('heel')) {
      return 'SHOE';
    }
    if (l.contains('cloth') || l.contains('apparel') || l.contains('jacket') || l.contains('hoodie') || l.contains('shirt')) {
      return 'CLOTHING';
    }
    if (l.contains('access') || l.contains('belt') || l.contains('jewel')) return 'ACCESSORY';
    return 'OTHER';
  }

  static ProductCategory categoryForCode(String code) => switch (code) {
        'WATCH' => ProductCategory.watches,
        'HANDBAG' => ProductCategory.bags,
        'SNEAKER' || 'SHOE' => ProductCategory.sneakers,
        'CLOTHING' => ProductCategory.clothing,
        'WALLET' => ProductCategory.wallets,
        'SUNGLASSES' || 'EYEGLASSES' => ProductCategory.eyewear,
        _ => ProductCategory.accessories,
      };

  ProductCategory get resolvedProductCategory => categoryForCode(resolvedCategoryCode);

  Product toProduct({required String imageAsset, String? id}) {
    if (!productDetected || productCategory == null) {
      throw AppError.unknown(
        detail: message.isNotEmpty ? message : 'No supported luxury product was detected.',
      );
    }

    final code = resolvedCategoryCode;
    final stdCat = categoryForCode(code);
    final lower = category.toLowerCase().trim();
    final bool isStandard = code != 'OTHER' && code != 'ACCESSORY' || lower == 'accessories';

    final custom = !isStandard && category.trim().isNotEmpty && lower != 'unknown'
        ? category.trim()
        : null;

    return Product(
      id: id ?? 'prod_${DateTime.now().millisecondsSinceEpoch}',
      name: product.isNotEmpty ? product : (category.isNotEmpty ? category : 'Luxury Item'),
      brand: brand.isNotEmpty ? brand : 'Luxury',
      model: model ?? variant ?? 'Standard',
      category: stdCat,
      customCategory: custom,
      imageAsset: imageAsset,
      identificationConfidence: identificationConfidence,
      categoryCode: code,
    );
  }
}
