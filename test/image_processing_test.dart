import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:replica_detector/services/image_hash.dart';
import 'package:replica_detector/services/image_preparation_service.dart';
import 'package:replica_detector/services/image_quality_checker.dart';

/// A sharp synthetic "engraving": fine text-like strokes on a textured plate.
img.Image sharpScene({int w = 1080, int h = 1440, int seed = 1}) {
  final rnd = Random(seed);
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(120, 118, 115));
  for (var i = 0; i < 4000; i++) {
    final x = rnd.nextInt(w - 20), y = rnd.nextInt(h - 20);
    final c = rnd.nextBool() ? 30 : 220;
    final long = 2 + rnd.nextInt(14), thin = 1 + rnd.nextInt(2);
    // Strokes in both orientations, like engraved lettering.
    final horizontal = rnd.nextBool();
    img.fillRect(im,
        x1: x, y1: y, x2: x + (horizontal ? long : thin), y2: y + (horizontal ? thin : long), color: img.ColorRgb8(c, c, c));
  }
  return im;
}

img.Image motionBlur(img.Image src, int len) {
  final out = img.Image.from(src);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      double r = 0;
      var n = 0;
      for (var k = -len ~/ 2; k <= len ~/ 2; k++) {
        r += src.getPixel((x + k).clamp(0, src.width - 1), y).r;
        n++;
      }
      final v = r / n;
      out.setPixelRgb(x, y, v, v, v);
    }
  }
  return out;
}

void main() {
  test('photos are resized, never cropped into new images, and keep enough pixels for engravings', () {
    expect(ImagePreset.values.map((p) => p.name), ['identification', 'validation', 'evidence']);
    expect(ImagePreset.evidence.maxDimension, greaterThanOrEqualTo(1536));
    expect(ImagePreset.evidence.jpegQuality, greaterThanOrEqualTo(90));
  });

  group('On-device quality checks', () {
    final sharp = sharpScene();

    test('a sharp photo has no blur or glare issues', () {
      final r = ImageQualityChecker.analyzeImageForTesting(sharp);
      expect(r.isUsable, isTrue);
      expect(r.issues.where((i) => i.contains('BLUR') || i.contains('GLARE')), isEmpty, reason: '${r.issues} focus=${r.focusSharpness}');
    });

    test('heavy defocus is flagged as severe blur with a specific fix', () {
      final r = ImageQualityChecker.analyzeImageForTesting(img.gaussianBlur(img.Image.from(sharp), radius: 10));
      expect(r.issues, contains('SEVERE_BLUR'));
      expect(r.hasSevereIssue, isTrue);
      expect(r.correction, contains('focus'));
    });

    test('directional smearing is flagged as motion blur', () {
      final r = ImageQualityChecker.analyzeImageForTesting(motionBlur(img.copyResize(sharp, width: 540), 25));
      expect(r.issues.any((i) => i == 'MOTION_BLUR' || i == 'SLIGHT_MOTION'), isTrue,
          reason: 'aniso=${r.gradientAnisotropy} focus=${r.focusSharpness} ${r.issues}');
    });

    test('a large specular reflection is flagged as severe glare', () {
      final g = img.Image.from(sharp);
      img.fillCircle(g, x: 540, y: 720, radius: 330, color: img.ColorRgb8(255, 255, 255));
      final r = ImageQualityChecker.analyzeImageForTesting(g);
      expect(r.issues, contains('SEVERE_GLARE'));
      expect(r.correction, contains('reflection'));
    });

    test('glare is measured on the detail region, not the whole photo', () {
      final g = img.Image.from(sharp);
      img.fillRect(g, x1: 800, y1: 1100, x2: 1080, y2: 1440, color: img.ColorRgb8(255, 255, 255));
      final whole = ImageQualityChecker.analyzeImageForTesting(g);
      final region = ImageQualityChecker.analyzeImageForTesting(g, region: [0.8, 0.75, 1.0, 1.0]);
      expect(region.glareFraction, greaterThan(whole.glareFraction));
      expect(region.issues, contains('SEVERE_GLARE'));
    });

    test('a smooth background does not make a sharp close-up look blurry', () {
      final im = img.Image(width: 1080, height: 1440);
      img.fill(im, color: img.ColorRgb8(200, 200, 200));
      final detail = sharpScene(w: 360, h: 360, seed: 3);
      img.compositeImage(im, detail, dstX: 360, dstY: 540);
      final r = ImageQualityChecker.analyzeImageForTesting(im);
      expect(r.issues.where((i) => i.contains('BLUR')), isEmpty, reason: 'focus=${r.focusSharpness}');
    });

    test('a small detail region triggers "move closer"', () {
      final r = ImageQualityChecker.analyzeImageForTesting(sharp, region: [0.45, 0.45, 0.55, 0.55]);
      expect(r.regionMinSide, lessThan(384));
      expect(r.issues, contains('TOO_FAR'));
    });

    test('a black frame is rejected before any network call', () {
      final r = ImageQualityChecker.analyzeImageForTesting(img.Image(width: 400, height: 400));
      expect(r.isUsable, isFalse);
      expect(r.reason, 'image_too_dark');
    });
  });

  group('Duplicate photos', () {
    test('the same picture resized and recompressed is a duplicate', () {
      final a = sharpScene(seed: 7);
      final b = img.decodeJpg(img.encodeJpg(img.copyResize(a, width: 700), quality: 70))!;
      expect(ImageHash.isDuplicate(ImageHash.compute(a), ImageHash.compute(b)), isTrue);
    });

    test('two different pictures are not duplicates', () {
      expect(ImageHash.isDuplicate(ImageHash.compute(sharpScene(seed: 1)), ImageHash.compute(sharpScene(seed: 2))), isFalse);
    });
  });
}
