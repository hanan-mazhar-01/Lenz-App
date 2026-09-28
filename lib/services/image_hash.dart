import 'package:image/image.dart' as img;

import '../core/config/authenticity_engine_config.dart';

/// 64-bit difference hash ("dHash"): robust to resizing and recompression,
/// so re-submitting the same picture (or a screenshot of it) is recognised,
/// while two genuinely different photos of the same item are not merged.
abstract final class ImageHash {
  static String compute(img.Image source) {
    final small = img.copyResize(
      img.grayscale(img.Image.from(source)),
      width: 9,
      height: 8,
      interpolation: img.Interpolation.average,
    );
    var bits = BigInt.zero;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final left = small.getPixel(x, y).r;
        final right = small.getPixel(x + 1, y).r;
        bits = (bits << 1) | (left > right ? BigInt.one : BigInt.zero);
      }
    }
    return bits.toRadixString(16).padLeft(16, '0');
  }

  static int distance(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 64;
    var x = BigInt.parse(a, radix: 16) ^ BigInt.parse(b, radix: 16);
    var count = 0;
    while (x > BigInt.zero) {
      if (x & BigInt.one == BigInt.one) count++;
      x = x >> 1;
    }
    return count;
  }

  static bool isDuplicate(String a, String b) =>
      distance(a, b) <= AuthenticityEngineConfig.duplicateHashDistance;
}
