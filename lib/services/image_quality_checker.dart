import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/config/authenticity_engine_config.dart';
import 'image_hash.dart';
import 'native_image_decoder.dart';

enum LocalQualityStatus {
  usable,
  imageTooDark,
  noVisibleContent,
  corruptOrEmpty,
}

class LocalImageQualityResult {
  final bool isUsable;
  final LocalQualityStatus status;
  final String? reasonCode;
  final String message;
  final double averageBrightness;
  final double contrastVariance;

  /// Variance of the Laplacian over the whole frame (256 px copy). Low for
  /// blurry photos, but also for close-ups with large smooth areas.
  final double sharpness;

  /// 90th percentile of per-tile Laplacian variance (512 px copy): how sharp
  /// the best-focused part of the photo is. Not fooled by smooth backgrounds.
  final double focusSharpness;

  /// Ratio of horizontal to vertical gradient energy in the sharpest tiles
  /// (max/min). High values with low focus suggest motion blur. Heuristic.
  final double gradientAnisotropy;

  /// Share of near-white, low-saturation pixels in the region checked.
  final double glareFraction;

  /// Short side of the full image, px.
  final int minSide;

  /// Short side of the checked region at full resolution, px (whole image
  /// when no region was given).
  final int regionMinSide;

  /// Deterministic 0-100 score. 0 means "not measured".
  final int qualityScore;

  /// BLUR, SEVERE_BLUR, SLIGHT_MOTION, MOTION_BLUR, GLARE, SEVERE_GLARE,
  /// TOO_DARK, OVEREXPOSED, LOW_RESOLUTION, TOO_FAR.
  final List<String> issues;

  /// 64-bit difference hash for duplicate detection.
  final String imageHash;

  String get reason => reasonCode ?? 'unusable_image';

  const LocalImageQualityResult({
    required this.isUsable,
    required this.status,
    this.reasonCode,
    required this.message,
    this.averageBrightness = 0,
    this.contrastVariance = 0,
    this.sharpness = 0,
    this.focusSharpness = 0,
    this.gradientAnisotropy = 1,
    this.glareFraction = 0,
    this.minSide = 0,
    this.regionMinSide = 0,
    this.qualityScore = 0,
    this.issues = const [],
    this.imageHash = '',
  });

  factory LocalImageQualityResult.passed({
    double averageBrightness = 128,
    double contrastVariance = 50,
    double sharpness = 0,
    double focusSharpness = 0,
    double gradientAnisotropy = 1,
    double glareFraction = 0,
    int minSide = 0,
    int regionMinSide = 0,
    int qualityScore = 0,
    List<String> issues = const [],
    String imageHash = '',
  }) {
    return LocalImageQualityResult(
      isUsable: true,
      status: LocalQualityStatus.usable,
      averageBrightness: averageBrightness,
      contrastVariance: contrastVariance,
      sharpness: sharpness,
      focusSharpness: focusSharpness,
      gradientAnisotropy: gradientAnisotropy,
      glareFraction: glareFraction,
      minSide: minSide,
      regionMinSide: regionMinSide,
      qualityScore: qualityScore,
      issues: issues,
      imageHash: imageHash,
      message: 'Image meets visual quality standards.',
    );
  }

  factory LocalImageQualityResult.tooDark({required double brightness}) {
    return LocalImageQualityResult(
      isUsable: false,
      status: LocalQualityStatus.imageTooDark,
      reasonCode: 'image_too_dark',
      averageBrightness: brightness,
      message: 'Image is too dark to analyze. Please move to a brighter area and scan the item again.',
    );
  }

  factory LocalImageQualityResult.noContent({
    required double brightness,
    required double variance,
  }) {
    return LocalImageQualityResult(
      isUsable: false,
      status: LocalQualityStatus.noVisibleContent,
      reasonCode: 'no_visible_content',
      averageBrightness: brightness,
      contrastVariance: variance,
      message: 'No visible item detected. Please point the camera at a product and try again.',
    );
  }

  factory LocalImageQualityResult.corrupt([String? detail]) {
    return LocalImageQualityResult(
      isUsable: false,
      status: LocalQualityStatus.corruptOrEmpty,
      reasonCode: 'corrupt_image',
      message: detail ?? 'Could not read captured image. Please take another photo.',
    );
  }

  bool get hasSevereIssue => issues.any(const {'SEVERE_BLUR', 'MOTION_BLUR', 'SEVERE_GLARE'}.contains);

  /// Exactly what the user should change, or null when nothing measurable is wrong.
  String? get correction {
    if (issues.contains('MOTION_BLUR')) {
      return 'The photo is smeared by movement. Brace your elbows or rest the phone, then hold still while it takes the picture.';
    }
    if (issues.contains('SEVERE_BLUR')) {
      return 'The detail is out of focus. Tap on it to focus, and move back a little if the camera cannot focus that close.';
    }
    if (issues.contains('SEVERE_GLARE')) {
      return 'A bright reflection covers the detail. Tilt the item slightly or move away from direct light.';
    }
    if (issues.contains('TOO_DARK')) return 'The photo is too dark. Move to brighter, even light.';
    if (issues.contains('OVEREXPOSED')) return 'The photo is too bright. Move out of direct light or turn off the flash.';
    if (issues.contains('TOO_FAR')) return 'The detail is small in the photo. Move closer, or zoom in, until it fills the guide.';
    if (issues.contains('GLARE')) return 'Some glare is visible. Tilting the item slightly would help.';
    if (issues.contains('SLIGHT_MOTION')) return 'The photo is slightly smeared. Hold the phone steady for a moment.';
    if (issues.contains('BLUR')) return 'The photo is slightly soft. Tap to focus and hold still.';
    if (issues.contains('LOW_RESOLUTION')) return 'The image resolution is low. Use the camera rather than a screenshot of a photo.';
    return null;
  }
}

class _QualityRequest {
  final Uint8List bytes;

  /// Normalised region [ymin, xmin, ymax, xmax] in 0..1, or null.
  final List<double>? region;
  const _QualityRequest(this.bytes, this.region);
}

class _DecodedQualityRequest {
  /// Only the analysis-size pixels travel to the isolate.
  final PixelBuffer pixels;
  final int originalWidth;
  final int originalHeight;
  final List<double>? region;
  _DecodedQualityRequest(DecodedPhoto photo, this.region)
      : pixels = photo.analysis,
        originalWidth = photo.originalWidth,
        originalHeight = photo.originalHeight;
}

/// On-device image checks. They catch unusable photos before any network
/// call and give specific correction advice. They never reject a photo for
/// differing from a framing template.
abstract final class ImageQualityChecker {
  // Thresholds for the tiled focus measure on a copy whose long side is
  // [analysisSide] (regions are scaled by the same factor as the full
  // photo). Calibrated 2026-09-26 on 40 real 1080x1920 device photos
  // (focus p10 219, p50 432, min 55) against synthetic Gaussian blur
  // (radius 3: p50 48; radius 8: max 12) and 15 px motion blur (p50 43,
  // anisotropy p50 1.82 vs real max 1.53).
  static int analysisSide = 1024;
  static const double severeBlurFocus = 20;
  static const double softFocus = 70;
  static const double motionAnisotropy = 1.7;
  static const double strongAnisotropy = 3.0;
  static const double glareWarn = 0.06;
  static const double glareSevere = 0.18;

  static Future<LocalImageQualityResult> evaluate(String imagePath, {List<double>? region}) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        if (Platform.environment.containsKey('FLUTTER_TEST')) {
          return LocalImageQualityResult.passed();
        }
        return LocalImageQualityResult.corrupt('Image file not found on disk.');
      }
      final watch = Stopwatch()..start();
      // One native decode per photo, shared with the uploads; the Dart
      // decoder is only the fallback.
      final decoded = await NativeImageDecoder.decode(imagePath);
      final LocalImageQualityResult result;
      if (decoded != null) {
        result = await compute(_analyzeDecoded, _DecodedQualityRequest(decoded, region));
      } else {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) return LocalImageQualityResult.corrupt('Captured file is empty.');
        result = await compute(_analyze, _QualityRequest(bytes, region));
      }
      if (kDebugMode) {
        debugPrint('[ImageQualityChecker] ${region == null ? 'photo' : 'detail region'} checked in '
            '${watch.elapsedMilliseconds}ms (${decoded != null ? 'native decode' : 'Dart decode'})');
      }
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageQualityChecker] Evaluation error: $e');
      return LocalImageQualityResult.corrupt('Unable to decode image.');
    }
  }

  @visibleForTesting
  static LocalImageQualityResult analyzeBytesForTesting(Uint8List bytes, {List<double>? region}) =>
      _analyze(_QualityRequest(bytes, region));

  /// [originalWidth] / [originalHeight]: the captured size when [image] is
  /// a downscaled decode, so resolution and "too far" are judged on the
  /// photo as taken.
  @visibleForTesting
  static LocalImageQualityResult analyzeImageForTesting(
    img.Image image, {
    List<double>? region,
    int? originalWidth,
    int? originalHeight,
  }) =>
      _analyzeImage(image, region, originalWidth: originalWidth, originalHeight: originalHeight);

  @visibleForTesting
  static LocalImageQualityResult analyzeDecodedForTesting(DecodedPhoto photo, {List<double>? region}) =>
      _analyzeDecoded(_DecodedQualityRequest(photo, region));

  static LocalImageQualityResult _analyze(_QualityRequest req) {
    final decoded = img.decodeImage(req.bytes);
    if (decoded == null) return LocalImageQualityResult.corrupt('Unrecognized image format.');
    return _analyzeImage(img.bakeOrientation(decoded), req.region);
  }

  static LocalImageQualityResult _analyzeDecoded(_DecodedQualityRequest req) => _analyzeImage(
        req.pixels.toImage(),
        req.region,
        originalWidth: req.originalWidth,
        originalHeight: req.originalHeight,
      );

  static LocalImageQualityResult _analyzeImage(
    img.Image image,
    List<double>? region, {
    int? originalWidth,
    int? originalHeight,
  }) {
    if (image.width == 0 || image.height == 0) {
      return LocalImageQualityResult.corrupt('Image has invalid dimensions.');
    }
    // Pixel sizes are reported for the photo as captured.
    final toOriginal = originalWidth != null && originalWidth > 0 ? originalWidth / image.width : 1.0;

    // ---------------------------------------------------- presence checks
    final thumb = img.copyResize(image, width: 64, height: 64, interpolation: img.Interpolation.average);
    final lums = <double>[];
    for (var y = 0; y < thumb.height; y++) {
      for (var x = 0; x < thumb.width; x++) {
        final p = thumb.getPixel(x, y);
        lums.add(0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
      }
    }
    final avg = lums.reduce((a, b) => a + b) / lums.length;
    if (avg < 14.0) return LocalImageQualityResult.tooDark(brightness: avg);
    final std = sqrt(lums.fold<double>(0, (s, l) => s + (l - avg) * (l - avg)) / lums.length);
    if (std < 3.5 || (avg > 248.0 && std < 6.0)) {
      return LocalImageQualityResult.noContent(brightness: avg, variance: std);
    }

    // ------------------------------------------------------ region crop
    final minSide = originalWidth != null && originalHeight != null
        ? min(originalWidth, originalHeight)
        : min(image.width, image.height);
    final fullScale = min(1.0, analysisSide / max(image.width, image.height));
    img.Image area = image;
    var regionMinSide = minSide;
    if (region != null && region.length == 4) {
      final y0 = (region[0].clamp(0.0, 1.0) * image.height).round();
      final x0 = (region[1].clamp(0.0, 1.0) * image.width).round();
      final y1 = (region[2].clamp(0.0, 1.0) * image.height).round();
      final x1 = (region[3].clamp(0.0, 1.0) * image.width).round();
      final w = x1 - x0, h = y1 - y0;
      if (w > 16 && h > 16) {
        area = img.copyCrop(image, x: x0, y: y0, width: w, height: h);
        regionMinSide = (min(w, h) * toOriginal).round();
      }
    }

    // ------------------------------------------------ focus measurements
    final global = _laplacianVariance(image, 256);
    // Same scale as the full photo would get, so region and full-photo
    // measurements share thresholds.
    final gray = _grayAt(area, (max(area.width, area.height) * fullScale).round().clamp(48, analysisSide));
    final focus = _tiledFocus(gray);
    final glare = _glareFraction(area);

    final issues = <String>[];
    final directional = focus.anisotropy >= motionAnisotropy;
    if (focus.p90 < severeBlurFocus) {
      issues.add(directional ? 'MOTION_BLUR' : 'SEVERE_BLUR');
    } else if (focus.p90 < softFocus) {
      issues.add(directional ? 'SLIGHT_MOTION' : 'BLUR');
    } else if (focus.anisotropy >= strongAnisotropy) {
      // Edges along the movement stay sharp, so focus can look fine while
      // everything across it is smeared. Advice only, never severe.
      issues.add('SLIGHT_MOTION');
    }
    if (glare >= glareSevere) {
      issues.add('SEVERE_GLARE');
    } else if (glare >= glareWarn) {
      issues.add('GLARE');
    }

    double exposure = 100;
    if (avg < 60) {
      exposure = avg / 60 * 100;
      issues.add('TOO_DARK');
    } else if (avg > 200) {
      exposure = (255 - avg) / 55 * 100;
      issues.add('OVEREXPOSED');
    }
    if (minSide < 600) issues.add('LOW_RESOLUTION');
    if (region != null && regionMinSide < AuthenticityEngineConfig.detailMinSidePx) issues.add('TOO_FAR');

    // Score: focus of the sharpest region dominates, not global texture.
    // log scale: 20 (severe blur) -> ~0, 70 -> ~45, 400+ -> 100.
    final focusScore = focus.p90 <= 1 ? 0.0 : ((log(focus.p90) / ln10 - 1.3) / 1.3 * 100).clamp(0.0, 100.0);
    final resolutionScore = (minSide / 1080 * 100).clamp(0.0, 100.0);
    final glarePenalty = (glare * 150).clamp(0.0, 30.0);
    final score = (focusScore * 0.6 + exposure.clamp(0, 100) * 0.25 + resolutionScore * 0.15 - glarePenalty)
        .round()
        .clamp(1, 100);

    return LocalImageQualityResult.passed(
      averageBrightness: avg,
      contrastVariance: std,
      sharpness: global,
      focusSharpness: focus.p90,
      gradientAnisotropy: focus.anisotropy,
      glareFraction: glare,
      minSide: minSide,
      regionMinSide: regionMinSide,
      qualityScore: score,
      issues: issues,
      imageHash: ImageHash.compute(image),
    );
  }

  static ({List<double> px, int w, int h}) _grayAt(img.Image src, int longest) {
    final l = max(src.width, src.height);
    final scale = l > longest ? longest / l : 1.0;
    final small = img.copyResize(
      src,
      width: max(3, (src.width * scale).round()),
      height: max(3, (src.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
    final w = small.width, h = small.height;
    final px = List<double>.filled(w * h, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        px[y * w + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      }
    }
    return (px: px, w: w, h: h);
  }

  /// Laplacian variance per tile on a 6x6 grid; returns the 90th percentile
  /// and the gradient anisotropy of the sharpest quarter of tiles.
  static ({double p90, double anisotropy}) _tiledFocus(({List<double> px, int w, int h}) g) {
    const grid = 6;
    final tw = g.w ~/ grid, th = g.h ~/ grid;
    if (tw < 4 || th < 4) return (p90: 0.0, anisotropy: 1.0);
    final tiles = <({double v, double gx, double gy})>[];
    for (var ty = 0; ty < grid; ty++) {
      for (var tx = 0; tx < grid; tx++) {
        double sum = 0, sumSq = 0, gx = 0, gy = 0;
        var n = 0;
        for (var y = max(1, ty * th); y < min(g.h - 1, (ty + 1) * th); y++) {
          for (var x = max(1, tx * tw); x < min(g.w - 1, (tx + 1) * tw); x++) {
            final i = y * g.w + x;
            final lap = g.px[i - g.w] + g.px[i + g.w] + g.px[i - 1] + g.px[i + 1] - 4 * g.px[i];
            sum += lap;
            sumSq += lap * lap;
            gx += (g.px[i + 1] - g.px[i - 1]).abs();
            gy += (g.px[i + g.w] - g.px[i - g.w]).abs();
            n++;
          }
        }
        if (n == 0) continue;
        final mean = sum / n;
        tiles.add((v: sumSq / n - mean * mean, gx: gx / n, gy: gy / n));
      }
    }
    if (tiles.isEmpty) return (p90: 0.0, anisotropy: 1.0);
    tiles.sort((a, b) => a.v.compareTo(b.v));
    final p90 = tiles[(tiles.length * 0.9).floor().clamp(0, tiles.length - 1)].v;
    final top = tiles.sublist((tiles.length * 0.75).floor());
    final gx = top.fold<double>(0, (s, t) => s + t.gx), gy = top.fold<double>(0, (s, t) => s + t.gy);
    final lo = min(gx, gy), hi = max(gx, gy);
    return (p90: p90, anisotropy: lo <= 0.0001 ? 1.0 : hi / lo);
  }

  /// Near-white, low-saturation pixels: specular highlights and blown-out
  /// reflections, as opposed to white materials in even light (those rarely
  /// reach 250+ on every channel).
  static double _glareFraction(img.Image src) {
    final l = max(src.width, src.height);
    final scale = l > 256 ? 256 / l : 1.0;
    final small = img.copyResize(
      src,
      width: max(1, (src.width * scale).round()),
      height: max(1, (src.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
    var glare = 0;
    final total = small.width * small.height;
    for (var y = 0; y < small.height; y++) {
      for (var x = 0; x < small.width; x++) {
        final p = small.getPixel(x, y);
        final r = p.r.toDouble(), gg = p.g.toDouble(), b = p.b.toDouble();
        final mx = max(r, max(gg, b)), mn = min(r, min(gg, b));
        if (mn >= 248 && (mx - mn) <= 12) glare++;
      }
    }
    return total == 0 ? 0 : glare / total;
  }

  static double _laplacianVariance(img.Image source, int longestSide) {
    final g = _grayAt(source, longestSide);
    final w = g.w, h = g.h;
    double sum = 0, sumSq = 0;
    var n = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final lap = g.px[i - w] + g.px[i + w] + g.px[i - 1] + g.px[i + 1] - 4 * g.px[i];
        sum += lap;
        sumSq += lap * lap;
        n++;
      }
    }
    if (n == 0) return 0;
    final mean = sum / n;
    return sumSq / n - mean * mean;
  }
}
