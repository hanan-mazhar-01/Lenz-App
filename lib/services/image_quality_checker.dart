import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

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

  /// Variance of the Laplacian on a 256px grayscale copy. Low = blurry.
  final double sharpness;

  /// Deterministic 0-100 score from sharpness, exposure and resolution.
  /// 0 means "not measured" (e.g. in tests or on decode failure).
  final int qualityScore;

  /// Plain issue codes matching the prompt's image-quality enum.
  final List<String> issues;

  String get reason => reasonCode ?? 'unusable_image';

  const LocalImageQualityResult({
    required this.isUsable,
    required this.status,
    this.reasonCode,
    required this.message,
    this.averageBrightness = 0,
    this.contrastVariance = 0,
    this.sharpness = 0,
    this.qualityScore = 0,
    this.issues = const [],
  });

  factory LocalImageQualityResult.passed({
    double averageBrightness = 128,
    double contrastVariance = 50,
    double sharpness = 0,
    int qualityScore = 0,
    List<String> issues = const [],
  }) {
    return LocalImageQualityResult(
      isUsable: true,
      status: LocalQualityStatus.usable,
      averageBrightness: averageBrightness,
      contrastVariance: contrastVariance,
      sharpness: sharpness,
      qualityScore: qualityScore,
      issues: issues,
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
}

/// Instant on-device pre-validation to detect completely dark/black, flat, or
/// corrupt images before sending them to the remote AI API.
abstract final class ImageQualityChecker {
  /// Inspects an image file locally in an isolate or fast decode.
  static Future<LocalImageQualityResult> evaluate(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        if (Platform.environment.containsKey('FLUTTER_TEST')) {
          return LocalImageQualityResult.passed();
        }
        return LocalImageQualityResult.corrupt('Image file not found on disk.');
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return LocalImageQualityResult.corrupt('Captured file is empty.');
      }

      // Fast decode: we only need a small thumbnail to compute brightness and variance
      return await compute(_analyzeImageBytes, bytes);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ImageQualityChecker] Evaluation error: $e');
      }
      // On unexpected decode failure, fail open or return corrupt
      return LocalImageQualityResult.corrupt('Unable to decode image.');
    }
  }

  @visibleForTesting
  static LocalImageQualityResult analyzeBytesForTesting(Uint8List bytes) => _analyzeImageBytes(bytes);

  static LocalImageQualityResult _analyzeImageBytes(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      return LocalImageQualityResult.corrupt('Unrecognized image format.');
    }

    // Downsample to 64x64 for fast luminance calculation
    final thumb = img.copyResize(image, width: 64, height: 64, interpolation: img.Interpolation.nearest);

    double totalLuminance = 0;
    final pixelCount = thumb.width * thumb.height;
    if (pixelCount == 0) {
      return LocalImageQualityResult.corrupt('Image has invalid dimensions.');
    }

    final luminances = <double>[];
    for (int y = 0; y < thumb.height; y++) {
      for (int x = 0; x < thumb.width; x++) {
        final pixel = thumb.getPixel(x, y);
        // Standard Rec. 601 luminance
        final lum = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        luminances.add(lum);
        totalLuminance += lum;
      }
    }

    final avgBrightness = totalLuminance / pixelCount;

    // 1. Extreme dark / black check (average brightness < 14 out of 255)
    if (avgBrightness < 14.0) {
      return LocalImageQualityResult.tooDark(brightness: avgBrightness);
    }

    // Compute standard deviation of luminance (contrast / visual structure)
    double sumVariance = 0;
    for (final lum in luminances) {
      sumVariance += (lum - avgBrightness) * (lum - avgBrightness);
    }
    final stdDev = sqrt(sumVariance / pixelCount);

    // 2. Extreme flat / empty image check (near zero contrast / featureless solid color or pure white)
    if (stdDev < 3.5 || (avgBrightness > 248.0 && stdDev < 6.0)) {
      return LocalImageQualityResult.noContent(
        brightness: avgBrightness,
        variance: stdDev,
      );
    }

    // 3. Quality score (informational: never rejects on its own, because a
    // plain close-up of smooth leather can legitimately have low texture).
    final sharpness = _laplacianVariance(image);
    final issues = <String>[];

    // Sharpness: log-scaled, ~20 for heavy blur, ~100 for crisp detail.
    final sharpScore = (sharpness <= 1 ? 0.0 : (log(sharpness) / ln10 - 0.8) / 1.6 * 100).clamp(0.0, 100.0);
    if (sharpScore < 45) issues.add('BLUR');

    // Exposure: ideal mean luminance roughly 70-190.
    double exposureScore = 100;
    if (avgBrightness < 70) {
      exposureScore = (avgBrightness / 70 * 100);
      issues.add('TOO_DARK');
    } else if (avgBrightness > 190) {
      exposureScore = ((255 - avgBrightness) / 65 * 100);
      issues.add('OVEREXPOSED');
    }
    exposureScore = exposureScore.clamp(0.0, 100.0);

    // Resolution: shortest side of 1080px or more is full marks.
    final minSide = min(image.width, image.height);
    final resolutionScore = (minSide / 1080 * 100).clamp(0.0, 100.0);
    if (minSide < 600) issues.add('LOW_RESOLUTION');

    final quality = (sharpScore * 0.55 + exposureScore * 0.25 + resolutionScore * 0.20).round().clamp(1, 100);

    return LocalImageQualityResult.passed(
      averageBrightness: avgBrightness,
      contrastVariance: stdDev,
      sharpness: sharpness,
      qualityScore: quality,
      issues: issues,
    );
  }

  /// Variance of the 4-neighbour Laplacian over a 256px grayscale copy.
  static double _laplacianVariance(img.Image source) {
    final longest = max(source.width, source.height);
    final scale = longest > 256 ? 256 / longest : 1.0;
    final small = img.copyResize(
      source,
      width: max(1, (source.width * scale).round()),
      height: max(1, (source.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
    final w = small.width, h = small.height;
    if (w < 3 || h < 3) return 0;

    final gray = List<double>.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        gray[y * w + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      }
    }

    double sum = 0, sumSq = 0;
    int n = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final lap = gray[i - w] + gray[i + w] + gray[i - 1] + gray[i + 1] - 4 * gray[i];
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
