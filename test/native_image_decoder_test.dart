import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:replica_detector/services/image_preparation_service.dart';
import 'package:replica_detector/services/image_quality_checker.dart';
import 'package:replica_detector/models/evidence_record.dart';
import 'package:replica_detector/services/detail_cropper.dart';
import 'package:replica_detector/services/native_image_decoder.dart';

/// A photo-like test image: smooth gradients with sharp random detail.
img.Image _scene(int w, int h, {int seed = 1}) {
  final rnd = Random(seed);
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final base = (x * 180 ~/ w + y * 60 ~/ h);
      final detail = ((x ~/ 3 + y ~/ 5) % 7 == 0) ? 60 : 0;
      im.setPixelRgb(x, y, (base + detail + rnd.nextInt(12)).clamp(0, 255), (base ~/ 2 + detail).clamp(0, 255),
          (200 - base ~/ 2 + rnd.nextInt(8)).clamp(0, 255));
    }
  }
  return im;
}

void main() {
  late Directory dir;
  setUpAll(() => dir = Directory.systemTemp.createTempSync('native_decode_test'));
  tearDownAll(() => dir.deleteSync(recursive: true));
  setUp(() {
    NativeImageDecoder.enabled = true;
    NativeImageDecoder.clearCache();
  });

  String writeJpg(String name, img.Image im) {
    final f = File('${dir.path}/$name.jpg')..writeAsBytesSync(img.encodeJpg(im, quality: 92));
    return f.path;
  }

  group('Area average', () {
    test('matches img.copyResize(average) to within one level', () {
      for (final size in [(2000, 1500, 1024, 768), (1777, 1333, 1024, 768), (1080, 1920, 864, 1536)]) {
        final src = _scene(size.$1, size.$2);
        final expected = img.copyResize(src, width: size.$3, height: size.$4, interpolation: img.Interpolation.average);
        final rgba = src.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
        final got = NativeImageDecoder.areaAverage(rgba, size.$1, size.$2, size.$3, size.$4);
        var worst = 0;
        for (var y = 0; y < size.$4; y += 7) {
          for (var x = 0; x < size.$3; x += 5) {
            final p = expected.getPixel(x, y);
            final o = (y * size.$3 + x) * 4;
            worst = max(worst, max((got[o] - p.r).abs().toInt(), max((got[o + 1] - p.g).abs().toInt(), (got[o + 2] - p.b).abs().toInt())));
          }
        }
        expect(worst, lessThanOrEqualTo(1), reason: '$size');
      }
    });

    test('fits the long side without ever enlarging', () {
      final big = PixelBuffer(Uint8List(3264 * 2448 * 4), 2448, 3264);
      final fit = NativeImageDecoder.fitWithin(big, 1536);
      expect([fit.width, fit.height], [1152, 1536]);
      final small = PixelBuffer(Uint8List(800 * 600 * 4), 800, 600);
      expect(identical(NativeImageDecoder.fitWithin(small, 1024), small), isTrue);
    });
  });

  group('EXIF orientation', () {
    test('a rotated JPEG is left to the Dart decoder, a plain one is not', () {
      final rotated = _scene(64, 32)..exif.imageIfd.orientation = 6;
      expect(NativeImageDecoder.needsDartOrientation(img.encodeJpg(rotated)), isTrue);
      expect(NativeImageDecoder.needsDartOrientation(img.encodeJpg(_scene(64, 32))), isFalse);
      expect(NativeImageDecoder.needsDartOrientation(img.encodePng(_scene(8, 8))), isFalse);
    });

    test('a rotated photo still comes out upright through the fallback', () async {
      final rotated = _scene(2000, 1000)..exif.imageIfd.orientation = 6;
      final path = writeJpg('rotated', rotated);
      expect(await NativeImageDecoder.decode(path), isNull);
      final prepared = await ImagePreparationService().prepareImage(path, preset: ImagePreset.evidence);
      expect([prepared.width, prepared.height], [768, 1536]);
    });
  });

  group('One native decode per photo', () {
    test('keeps the analysis and upload sizes and the captured size', () async {
      final path = writeJpg('portrait', _scene(1224, 1632));
      final d = (await NativeImageDecoder.decode(path))!;
      expect([d.originalWidth, d.originalHeight], [1224, 1632]);
      expect([d.analysis.width, d.analysis.height], [768, 1024]);
      expect([d.upload.width, d.upload.height], [1152, 1536]);
      expect(identical(await NativeImageDecoder.decode(path), d), isTrue, reason: 'decoded once, then shared');
    });

    test('quality results match the Dart path and use the captured size', () async {
      final path = writeJpg('quality', _scene(2448, 1836, seed: 3));
      const region = [0.4, 0.4, 0.6, 0.6];
      final native = await ImageQualityChecker.evaluate(path, region: region);
      NativeImageDecoder.enabled = false;
      final dart = await ImageQualityChecker.evaluate(path, region: region);
      expect(native.issues, dart.issues);
      expect(native.minSide, 1836);
      expect(native.regionMinSide, closeTo(dart.regionMinSide, 2), reason: 'region size in captured pixels');
      expect(native.focusSharpness, closeTo(dart.focusSharpness, dart.focusSharpness * 0.1));
      expect(native.imageHash, isNotEmpty);
    });

    test('uploads have the preset sizes and a warm-up is shared, not repeated', () async {
      final path = writeJpg('upload', _scene(2448, 3264, seed: 5));
      final prep = ImagePreparationService();
      prep.warm(path, ImagePreset.evidence);
      final results = await Future.wait([
        prep.prepareImage(path, preset: ImagePreset.evidence),
        prep.prepareImage(path, preset: ImagePreset.validation),
      ]);
      expect([results[0].width, results[0].height], [1152, 1536]);
      expect([results[1].width, results[1].height], [768, 1024]);
      expect(identical(await prep.prepareImage(path, preset: ImagePreset.evidence), results[0]), isTrue);
      expect(img.decodeJpg(base64Decode(results[0].base64Data))!.width, 1152);
    });
  });

  group('In-memory detail crops', () {
    test('the crop rectangle includes a margin and stays inside the image', () {
      final r = NativeImageDecoder.cropRect([0.4, 0.4, 0.6, 0.6], 1000, 800)!;
      expect(r.x, lessThan(400));
      expect(r.x + r.w, greaterThan(600));
      expect(r.y + r.h, lessThanOrEqualTo(800));
      expect(NativeImageDecoder.cropRect([0.5, 0.5, 0.5, 0.9], 100, 100), isNull, reason: 'degenerate box');
      final edge = NativeImageDecoder.cropRect([0.0, 0.9, 0.2, 1.0], 100, 100)!;
      expect(edge.x + edge.w, lessThanOrEqualTo(100));
    });

    test('decodes only the detail, at up to the crop size, without writing files', () async {
      final path = writeJpg('crop_source', _scene(2448, 3264, seed: 7));
      final before = dir.listSync().length;
      final crop = (await NativeImageDecoder.decodeCrop(path, [0.40, 0.40, 0.55, 0.52], maxSide: 1024))!;
      expect(crop.width, closeTo(0.12 * 1.16 * 2448, 4));
      expect(crop.height, closeTo(0.15 * 1.16 * 3264, 4));
      expect(dir.listSync().length, before);
      final big = (await NativeImageDecoder.decodeCrop(path, [0.1, 0.1, 0.9, 0.9], maxSide: 1024))!;
      expect(big.longSide, 1024);
    });

    test('a close-up is only made when it adds real detail', () {
      // 8 MP capture, small detail: much more detail in the crop.
      expect(DetailCropper.detailGain(box: [0.4, 0.4, 0.55, 0.52], originalWidth: 2448, originalHeight: 3264), greaterThan(1.5));
      // 1080x1920 capture: the upload copy already has almost every pixel.
      expect(DetailCropper.detailGain(box: [0.4, 0.4, 0.55, 0.52], originalWidth: 1080, originalHeight: 1920), lessThan(1.3));
      final photos = [
        PhotoEvidence(photoId: 'a', requestId: 'a', requestTitle: 'A', imagePath: '/a', detailBox: const [0.4, 0.4, 0.55, 0.52]),
        PhotoEvidence(photoId: 'b', requestId: 'b', requestTitle: 'B', imagePath: '/b', detailBox: const [0.0, 0.0, 1.0, 1.0]),
        PhotoEvidence(photoId: 'c', requestId: 'c', requestTitle: 'C', imagePath: '/c'),
      ];
      final picked = DetailCropper.candidates(photos, {
        'a': (width: 2448, height: 3264),
        'b': (width: 2448, height: 3264),
        'c': (width: 2448, height: 3264),
      });
      expect(picked.map((p) => p.photoId), ['a']);
    });
  });
}
