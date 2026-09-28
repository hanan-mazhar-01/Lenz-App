import '../core/errors/app_error.dart';
import 'product.dart';
import 'product_identity.dart';

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

  /// Engine v3: per-attribute identity with explicit certainty.
  final ProductIdentity? identity;

  /// Engine v3: bounding box of the item [ymin, xmin, ymax, xmax] in 0..1.
  final List<double>? itemBox;

  /// Engine v3: which part of the product the first photo shows.
  final String visiblePart;

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
    this.identity,
    this.itemBox,
    this.visiblePart = '',
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

    // 0. Not a real photo of the item (a screen, a printed picture or an
    //    internet image): nothing about the item can be checked from it.
    final source = json['image_source']?.toString();
    if (reason == 'not_real_photo' || source == 'SCREEN_OR_PRINT' || source == 'INTERNET_IMAGE') {
      return ProductIdentification(
        status: IdentificationStatus.unusableImage,
        reason: 'not_real_photo',
        productDetected: false,
        identificationConfidence: conf,
        visibleDetails: details,
        missingEvidence: missing,
        message: 'This looks like a picture from the internet or a screen, not the item itself. '
            'Please take a photo of the actual item with the camera.',
        isIdentified: false,
      );
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

    List<String> strings(String k) => [
          for (final e in (json[k] as List? ?? const []))
            if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
        ];
    // Only the supported categories are scanned. A fragrance, cosmetic or
    // gadget the model filed under a catch-all code, or an explicit "OTHER",
    // is refused. A fashion label the keyword fallback can't map (no code
    // given) is treated as an accessory.
    final type = '$rawCat ${json['product_type'] ?? ''}';
    final looksUnsupported = RegExp(
      r'perfume|fragrance|toilette|parfum|cologne|cosmetic|makeup|skincare|lipstick|smartphone|mobile phone|earbud|headphone|earphone|airpods|laptop|tablet|speaker|charger|electronic',
      caseSensitive: false,
    ).hasMatch(type);
    final labelCode = _codeFromLabel(rawCat);
    final code = categoryCode ?? (labelCode == 'OTHER' && !looksUnsupported ? 'ACCESSORY' : labelCode);
    if (!supportedCategoryCodes.contains(code) || (looksUnsupported && code == 'ACCESSORY')) {
      return ProductIdentification(
        status: IdentificationStatus.notProduct,
        reason: 'unsupported_object',
        productDetected: false,
        identificationConfidence: conf,
        visibleDetails: details,
        missingEvidence: missing,
        message: 'No supported item detected. Please scan a watch, bag, shoe, clothing, wallet, eyewear or accessory.',
        isIdentified: false,
      );
    }
    final brandAttr = IdentityAttribute.fromParts(cleanBrand, json['brand_status'],
        basis: json['brand_basis'], source: 'DESIGN');
    final modelAttr = IdentityAttribute.fromParts(json['model'], json['model_status'],
        basis: json['model_basis'], source: 'DESIGN');
    final genAttr = IdentityAttribute.fromParts(json['generation'], json['generation_status'],
        basis: json['generation_basis'], source: 'DESIGN');
    final exactAttr = IdentityAttribute.fromParts(json['exact_model'], json['exact_model_status'],
        basis: 'read from the photo', source: 'MARKING');
    final identity = ProductIdentity(
      categoryCode: code,
      productType: (json['product_type'] as String? ?? '').trim(),
      brand: brandAttr,
      modelFamily: modelAttr,
      generation: genAttr,
      exactModel: exactAttr,
      visibleCharacteristics: strings('visible_characteristics').isNotEmpty ? strings('visible_characteristics') : details,
      distinguishingFeatures: strings('distinguishing_features'),
      uncertainAttributes: strings('uncertain_attributes'),
    );

    List<double>? box;
    final rawBox = json['item_box_2d'];
    if (rawBox is List && rawBox.length == 4 && rawBox.every((v) => v is num)) {
      final b = rawBox.map((v) => ((v as num).toDouble() / 1000).clamp(0.0, 1.0)).toList();
      if (b[2] > b[0] && b[3] > b[1]) box = b;
    }

    return ProductIdentification(
      status: IdentificationStatus.productDetected,
      reason: reason.isNotEmpty ? reason : 'valid_luxury_product',
      productDetected: true,
      productCategory: rawCat,
      brand: cleanBrand,
      product: cleanProduct,
      model: modelAttr.value ?? (json['model'] as String?),
      variant: json['variant'] as String?,
      categoryCode: code,
      identificationConfidence: conf,
      visibleDetails: details,
      missingEvidence: missing,
      message: message.isNotEmpty ? message : 'Item identified successfully.',
      isIdentified: true,
      identity: identity,
      itemBox: box,
      visiblePart: (json['visible_part'] as String? ?? '').trim(),
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
        if (identity != null) 'identity': identity!.toJson(),
        if (visiblePart.isNotEmpty) 'visible_part': visiblePart,
      };

  static const categoryCodes = {
    'WATCH', 'HANDBAG', 'SNEAKER', 'SHOE', 'CLOTHING', 'WALLET',
    'ACCESSORY', 'SUNGLASSES', 'EYEGLASSES', 'OTHER',
  };

  /// Categories the app scans. Anything else (fragrance, electronics,
  /// household items...) is refused even if the model lets it through.
  static const supportedCategoryCodes = {
    'WATCH', 'HANDBAG', 'SNEAKER', 'SHOE', 'CLOTHING', 'WALLET',
    'ACCESSORY', 'SUNGLASSES', 'EYEGLASSES',
  };

  static String _codeFromLabel(String label) => ProductIdentification(
        status: IdentificationStatus.productDetected,
        reason: '',
        productDetected: true,
        productCategory: label,
        identificationConfidence: 0,
        message: '',
      ).resolvedCategoryCode;

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

  static String codeForCategory(ProductCategory c) => switch (c) {
        ProductCategory.watches => 'WATCH',
        ProductCategory.bags => 'HANDBAG',
        ProductCategory.sneakers => 'SNEAKER',
        ProductCategory.clothing => 'CLOTHING',
        ProductCategory.wallets => 'WALLET',
        ProductCategory.eyewear => 'SUNGLASSES',
        ProductCategory.accessories => 'ACCESSORY',
      };

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
    const customLabelled = {'OTHER', 'ACCESSORY'};
    final bool isStandard = !customLabelled.contains(code) || lower == 'accessories';

    final custom = !isStandard && category.trim().isNotEmpty && lower != 'unknown'
        ? category.trim()
        : null;

    return Product(
      id: id ?? 'prod_${DateTime.now().millisecondsSinceEpoch}',
      name: product.isNotEmpty ? product : (category.isNotEmpty ? category : 'Luxury Item'),
      brand: brand.isNotEmpty ? brand : Product.unidentifiedBrand,
      model: model ?? variant ?? Product.unidentifiedModel,
      category: stdCat,
      customCategory: custom,
      imageAsset: imageAsset,
      identificationConfidence: identificationConfidence,
      categoryCode: code,
      identity: identity,
    );
  }
}
