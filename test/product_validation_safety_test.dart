import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:replica_detector/models/product_identification.dart';
import 'package:replica_detector/services/image_quality_checker.dart';

void main() {
  group('ProductIdentification Safety & Validation', () {
    test('Human detection returns not_product with null brand and model', () {
      final json = {
        'status': 'not_product',
        'reason': 'human_detected',
        'product_detected': false,
        'product_category': null,
        'brand': null,
        'model': null,
        'identification_confidence': 0.0,
        'message': 'Please scan a luxury item such as a handbag, watch, shoe, wallet, jewelry, or other supported product.',
      };

      final ident = ProductIdentification.fromJson(json);

      expect(ident.status, IdentificationStatus.notProduct);
      expect(ident.productDetected, isFalse);
      expect(ident.brand, isEmpty);
      expect(ident.model, isNull);
      expect(ident.reason, 'human_detected');
      expect(() => ident.toProduct(imageAsset: '/tmp/test.jpg'), throwsException);
    });

    test('Dark image returns unusable_image', () {
      final json = {
        'status': 'unusable_image',
        'reason': 'image_too_dark',
        'product_detected': false,
        'product_category': null,
        'brand': null,
        'model': null,
        'identification_confidence': 0.0,
        'message': 'Image is too dark to analyze. Please move to a brighter area and scan the item again.',
      };

      final ident = ProductIdentification.fromJson(json);

      expect(ident.status, IdentificationStatus.unusableImage);
      expect(ident.productDetected, isFalse);
      expect(ident.reason, 'image_too_dark');
      expect(ident.message, contains('too dark'));
      expect(() => ident.toProduct(imageAsset: '/tmp/test.jpg'), throwsException);
    });

    test('Blank / empty image returns unusable_image', () {
      final json = {
        'status': 'unusable_image',
        'reason': 'no_visible_content',
        'product_detected': false,
        'product_category': null,
        'brand': null,
        'model': null,
        'identification_confidence': 0.0,
        'message': 'No visible item detected. Please point the camera at a product and try again.',
      };

      final ident = ProductIdentification.fromJson(json);

      expect(ident.status, IdentificationStatus.unusableImage);
      expect(ident.productDetected, isFalse);
      expect(ident.reason, 'no_visible_content');
    });

    test('Blurry / low-quality image returns unusable_image', () {
      final json = {
        'status': 'unusable_image',
        'reason': 'insufficient_visual_quality',
        'product_detected': false,
        'product_category': null,
        'brand': null,
        'model': null,
        'identification_confidence': 0.0,
        'message': "The image isn't clear enough to analyze. Please capture a sharper photo with the item fully visible.",
      };

      final ident = ProductIdentification.fromJson(json);

      expect(ident.status, IdentificationStatus.unusableImage);
      expect(ident.productDetected, isFalse);
      expect(ident.reason, 'insufficient_visual_quality');
    });

    test('Irrelevant object (furniture, wall, animal, car) returns not_product', () {
      final json = {
        'status': 'not_product',
        'reason': 'unsupported_object',
        'product_detected': false,
        'product_category': 'Furniture',
        'brand': null,
        'model': null,
        'identification_confidence': 0.1,
        'message': 'No supported luxury item detected. Please scan a supported product.',
      };

      final ident = ProductIdentification.fromJson(json);

      expect(ident.status, IdentificationStatus.notProduct);
      expect(ident.productDetected, isFalse);
      expect(ident.reason, 'unsupported_object');
    });

    test('Never hallucinates "Unknown Luxury Item" on missing or unknown category', () {
      final json = {
        'status': 'product_detected',
        'reason': '',
        'product_detected': true,
        'product_category': 'Unknown',
        'brand': 'Unknown',
        'product': 'Unknown Luxury Item',
        'identification_confidence': 0.85,
      };

      final ident = ProductIdentification.fromJson(json);

      // Must be demoted to notProduct rather than creating an Unknown Luxury Item
      expect(ident.productDetected, isFalse);
      expect(ident.status, IdentificationStatus.notProduct);
    });

    test('Confidence < 0.70 is flagged as insufficient evidence', () {
      final json = {
        'status': 'product_detected',
        'reason': 'valid_product',
        'product_detected': true,
        'product_category': 'Watches',
        'brand': 'Rolex',
        'product': 'Rolex Submariner',
        'identification_confidence': 0.65, // Below 0.70 threshold
      };

      final ident = ProductIdentification.fromJson(json);

      expect(ident.status, IdentificationStatus.insufficientEvidence);
      expect(ident.productDetected, isFalse);
    });

    test('Valid luxury product with confidence >= 0.85 passes correctly', () {
      final json = {
        'status': 'product_detected',
        'reason': 'valid_luxury_product',
        'product_detected': true,
        'product_category': 'Watches',
        'brand': 'Audemars Piguet',
        'product': 'Royal Oak',
        'model': '15500ST',
        'identification_confidence': 0.94,
        'visible_details': ['tapisserie dial', 'integrated bracelet', 'octagonal bezel'],
        'message': 'Item identified successfully.',
      };

      final ident = ProductIdentification.fromJson(json);

      expect(ident.status, IdentificationStatus.productDetected);
      expect(ident.productDetected, isTrue);
      expect(ident.brand, 'Audemars Piguet');
      expect(ident.product, 'Royal Oak');
      expect(ident.model, '15500ST');
      expect(ident.identificationConfidence, 0.94);

      final product = ident.toProduct(imageAsset: '/tmp/ap.jpg');
      expect(product.brand, 'Audemars Piguet');
      expect(product.name, 'Royal Oak');
      expect(product.model, '15500ST');
    });
  });

  group('Local ImageQualityChecker Tests', () {
    test('Pure black image is rejected as image_too_dark', () {
      final blackImg = img.Image(width: 64, height: 64);
      img.fill(blackImg, color: img.ColorRgb8(0, 0, 0));
      final bytes = Uint8List.fromList(img.encodeJpg(blackImg));

      // Fast check on bytes via internal analyzer
      final res = ImageQualityChecker.analyzeBytesForTesting(bytes);
      expect(res.isUsable, isFalse);
      expect(res.status, LocalQualityStatus.imageTooDark);
      expect(res.reasonCode, 'image_too_dark');
    });

    test('Pure flat gray image with zero variance is rejected as no_visible_content', () {
      final flatImg = img.Image(width: 64, height: 64);
      img.fill(flatImg, color: img.ColorRgb8(128, 128, 128));
      final bytes = Uint8List.fromList(img.encodeJpg(flatImg));

      final res = ImageQualityChecker.analyzeBytesForTesting(bytes);
      expect(res.isUsable, isFalse);
      expect(res.status, LocalQualityStatus.noVisibleContent);
      expect(res.reasonCode, 'no_visible_content');
    });

    test('Normal textured/contrasted image passes local check', () {
      final testImg = img.Image(width: 64, height: 64);
      for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 64; x++) {
          final val = (x * 4 + y * 2) % 256;
          testImg.setPixelRgb(x, y, val, 255 - val, val);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(testImg));

      final res = ImageQualityChecker.analyzeBytesForTesting(bytes);
      expect(res.isUsable, isTrue);
      expect(res.status, LocalQualityStatus.usable);
    });
  });

  group('Only the supported categories are scanned', () {
    Map<String, dynamic> detected({String? code, String category = 'Watches', String type = 'watch', String? brand = 'Casio'}) => {
          'status': 'product_detected',
          'reason': 'valid_luxury_product',
          'product_detected': true,
          'category_code': code,
          'product_category': category,
          'product_type': type,
          'brand': brand,
          'product_name': '$brand item',
          'confidence': 0.9,
        };

    test('watches, bags, shoes, clothing, wallets, eyewear and accessories are accepted', () {
      for (final code in ['WATCH', 'HANDBAG', 'SNEAKER', 'SHOE', 'CLOTHING', 'WALLET', 'ACCESSORY', 'SUNGLASSES', 'EYEGLASSES']) {
        final id = ProductIdentification.fromJson(detected(code: code));
        expect(id.status, IdentificationStatus.productDetected, reason: code);
      }
    });

    test('a replica imitating a known brand is still scanned', () {
      final id = ProductIdentification.fromJson(detected(code: 'SNEAKER', category: 'Sneakers', type: 'sneaker', brand: 'Michael Kors'));
      expect(id.status, IdentificationStatus.productDetected);
    });

    test('perfume, cosmetics and gadgets are refused even when filed as accessories', () {
      for (final type in ['eau de toilette', 'perfume', 'lipstick', 'wireless earbuds', 'headphones', 'smartphone']) {
        final id = ProductIdentification.fromJson(detected(code: 'ACCESSORY', category: 'Accessories', type: type));
        expect(id.status, IdentificationStatus.notProduct, reason: type);
        expect(id.reason, 'unsupported_object');
        expect(() => id.toProduct(imageAsset: '/tmp/x.jpg'), throwsException);
      }
    });

    test('an unknown code or an old ELECTRONICS / COSMETICS / OTHER code is refused', () {
      for (final code in ['OTHER', 'ELECTRONICS', 'COSMETICS']) {
        final id = ProductIdentification.fromJson(detected(code: code, category: code == 'OTHER' ? 'Other' : code, type: code == 'COSMETICS' ? 'perfume' : 'gadget'));
        expect(id.status, IdentificationStatus.notProduct, reason: code);
      }
      final fragrance = ProductIdentification.fromJson(detected(category: 'Fragrance', type: 'eau de toilette'));
      expect(fragrance.status, IdentificationStatus.notProduct);
    });

    test('a generic unbranded item the model refuses stays refused', () {
      final id = ProductIdentification.fromJson({
        'status': 'not_product',
        'reason': 'unsupported_object',
        'product_detected': false,
        'confidence': 0.9,
        'message': 'This looks like a generic, unbranded item.',
      });
      expect(id.status, IdentificationStatus.notProduct);
      expect(id.message, contains('unbranded'));
    });
  });

  group('Pictures of pictures are refused', () {
    Map<String, dynamic> detectedAs(String source) => {
          'image_source': source,
          'status': 'product_detected',
          'reason': 'valid_luxury_product',
          'product_detected': true,
          'category_code': 'WATCH',
          'product_category': 'Watches',
          'product_type': 'smartwatch',
          'brand': 'Apple',
          'product_name': 'Apple Watch',
          'confidence': 0.95,
        };

    test('an internet image or a photo of a screen is refused, even if the model identified it', () {
      for (final source in ['INTERNET_IMAGE', 'SCREEN_OR_PRINT']) {
        final id = ProductIdentification.fromJson(detectedAs(source));
        expect(id.status, IdentificationStatus.unusableImage, reason: source);
        expect(id.reason, 'not_real_photo');
        expect(id.message, contains('take a photo of the actual item'));
        expect(() => id.toProduct(imageAsset: '/tmp/x.jpg'), throwsException);
      }
    });

    test('the refusal reason alone is enough', () {
      final id = ProductIdentification.fromJson({
        'status': 'unusable_image',
        'reason': 'not_real_photo',
        'product_detected': false,
        'confidence': 0.9,
        'message': 'x',
      });
      expect(id.reason, 'not_real_photo');
    });

    test('a real photo of the item is identified normally', () {
      expect(ProductIdentification.fromJson(detectedAs('PHYSICAL_ITEM')).status, IdentificationStatus.productDetected);
    });
  });
}
