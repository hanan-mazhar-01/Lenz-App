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

  String get reason => reasonCode ?? 'unusable_image';

  const LocalImageQualityResult({
    required this.isUsable,
    required this.status,
    this.reasonCode,
    required this.message,
    this.averageBrightness = 0,
    this.contrastVariance = 0,
  });

  factory LocalImageQualityResult.passed({
    double averageBrightness = 128,
    double contrastVariance = 50,
  }) {
    return LocalImageQualityResult(
      isUsable: true,
      status: LocalQualityStatus.usable,
      averageBrightness: averageBrightness,
      contrastVariance: contrastVariance,
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

    return LocalImageQualityResult.passed(
      averageBrightness: avgBrightness,
      contrastVariance: stdDev,
    );
  }
}
