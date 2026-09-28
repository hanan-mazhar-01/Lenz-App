import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Raw RGBA pixels of one image.
class PixelBuffer {
  final Uint8List rgba;
  final int width;
  final int height;

  const PixelBuffer(this.rgba, this.width, this.height);

  int get longSide => max(width, height);

  img.Image toImage() => img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgba.buffer,
        bytesOffset: rgba.offsetInBytes,
        numChannels: 4,
      );
}

/// A photo decoded once, kept as the two sizes the app works with. Both are
/// area-averaged from the full-resolution decode, exactly as the Dart path
/// always resized, so quality measurements keep their calibration.
class DecodedPhoto {
  /// Long side at most [NativeImageDecoder.analysisSide]: quality checks and
  /// the identification / photo-check uploads.
  final PixelBuffer analysis;

  /// Long side at most [NativeImageDecoder.uploadSide]: the analysis upload.
  final PixelBuffer upload;

  /// The photo as captured.
  final int originalWidth;
  final int originalHeight;

  const DecodedPhoto({
    required this.analysis,
    required this.upload,
    required this.originalWidth,
    required this.originalHeight,
  });

  /// The smallest stored size that still covers [maxDimension].
  PixelBuffer forMaxDimension(int maxDimension) =>
      analysis.longSide >= min(maxDimension, max(originalWidth, originalHeight)) ? analysis : upload;
}

/// Decodes each photo once with the phone's own image decoder instead of
/// the pure-Dart one. On the test phone (Helio P35, debug build) the Dart
/// decoder needed about ten seconds per 8 MP photo, and every photo was
/// decoded four times: the quality check, the photo-check upload, the
/// detail-region check and the analysis upload. All four now share one
/// native decode.
///
/// Returns null whenever it can't be sure to give the same picture the Dart
/// decoder would (a JPEG with an EXIF rotation flag, any error); callers
/// then fall back to the Dart decoder.
abstract final class NativeImageDecoder {
  static const int analysisSide = 1024;
  static const int uploadSide = 1536;

  /// Off in unit tests that exercise the Dart-decoder path.
  static bool enabled = true;

  static const int _maxCached = 3;
  static final Map<String, Future<DecodedPhoto?>> _cache = {};

  static Future<DecodedPhoto?> decode(String path) {
    if (!enabled) return Future.value(null);
    final hit = _cache.remove(path);
    if (hit != null) {
      _cache[path] = hit; // most recently used
      return hit;
    }
    final future = _decode(path);
    _cache[path] = future;
    while (_cache.length > _maxCached) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  static void evict(String path) => _cache.remove(path);

  @visibleForTesting
  static void clearCache() => _cache.clear();

  static Future<DecodedPhoto?> _decode(String path) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final data = await file.readAsBytes();
      if (data.isEmpty || needsDartOrientation(data)) return null;

      buffer = await ui.ImmutableBuffer.fromUint8List(data);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      if (w <= 0 || h <= 0) return null;
      // Full resolution: the platform decoder is not asked to resize,
      // because its filter is softer than the area average the quality
      // thresholds were calibrated on.
      codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      image = frame.image;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;
      final full = PixelBuffer(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), image.width, image.height);
      image.dispose();
      image = null;
      final sizes = await compute(_workingSizes, full);
      return DecodedPhoto(analysis: sizes.$1, upload: sizes.$2, originalWidth: w, originalHeight: h);
    } catch (e) {
      if (kDebugMode) debugPrint('[NativeImageDecoder] falling back to the Dart decoder: $e');
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// The full-resolution pixels inside [box] (normalised [ymin, xmin, ymax,
  /// xmax], widened by [margin] on each side), scaled to at most [maxSide].
  /// Nothing is written to disk. Returns null when the photo can't be
  /// decoded natively (same rules as [decode]).
  static Future<PixelBuffer?> decodeCrop(String path, List<double> box, {int maxSide = 1024, double margin = 0.08}) async {
    if (!enabled || box.length != 4) return null;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final data = await file.readAsBytes();
      if (data.isEmpty || needsDartOrientation(data)) return null;
      buffer = await ui.ImmutableBuffer.fromUint8List(data);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      image = frame.image;
      final w = image.width, h = image.height;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;
      final rect = cropRect(box, w, h, margin: margin);
      if (rect == null) return null;
      final src = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
      final out = Uint8List(rect.w * rect.h * 4);
      for (var y = 0; y < rect.h; y++) {
        final from = ((rect.y + y) * w + rect.x) * 4;
        out.setRange(y * rect.w * 4, (y + 1) * rect.w * 4, src, from);
      }
      return await compute(_fitCrop, (PixelBuffer(out, rect.w, rect.h), maxSide));
    } catch (e) {
      if (kDebugMode) debugPrint('[NativeImageDecoder] crop skipped: $e');
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static PixelBuffer _fitCrop((PixelBuffer, int) req) => fitWithin(req.$1, req.$2);

  /// Pixel rectangle for a normalised box plus margin, clamped to the image.
  /// Null when the box is degenerate.
  static ({int x, int y, int w, int h})? cropRect(List<double> box, int width, int height, {double margin = 0.08}) {
    final y0 = box[0].clamp(0.0, 1.0), x0 = box[1].clamp(0.0, 1.0);
    final y1 = box[2].clamp(0.0, 1.0), x1 = box[3].clamp(0.0, 1.0);
    if (y1 - y0 < 0.01 || x1 - x0 < 0.01) return null;
    final mx = (x1 - x0) * margin, my = (y1 - y0) * margin;
    final left = ((x0 - mx).clamp(0.0, 1.0) * width).floor();
    final top = ((y0 - my).clamp(0.0, 1.0) * height).floor();
    final right = ((x1 + mx).clamp(0.0, 1.0) * width).ceil().clamp(left + 1, width);
    final bottom = ((y1 + my).clamp(0.0, 1.0) * height).ceil().clamp(top + 1, height);
    return (x: left, y: top, w: right - left, h: bottom - top);
  }

  static (PixelBuffer, PixelBuffer) _workingSizes(PixelBuffer full) =>
      (fitWithin(full, analysisSide), fitWithin(full, uploadSide));

  /// Scales [src] so its long side is at most [maxSide] (never enlarges),
  /// with the same rounding as `img.copyResize(width: / height: ...)`.
  static PixelBuffer fitWithin(PixelBuffer src, int maxSide) {
    if (src.longSide <= maxSide) return src;
    final int dw, dh;
    if (src.width >= src.height) {
      dw = maxSide;
      dh = (maxSide * (src.height / src.width)).round();
    } else {
      dh = maxSide;
      dw = (maxSide * (src.width / src.height)).round();
    }
    return PixelBuffer(areaAverage(src.rgba, src.width, src.height, dw, dh), dw, dh);
  }

  /// Area-average downscale of RGBA bytes with the same integer source
  /// windows as `img.copyResize(interpolation: Interpolation.average)`, but
  /// on raw bytes, which is many times faster than going pixel by pixel
  /// through `img.Image`.
  static Uint8List areaAverage(Uint8List src, int sw, int sh, int dw, int dh) {
    final dx = sw / dw, dy = sh / dh;
    final x0 = Int32List(dw), x1 = Int32List(dw);
    for (var x = 0; x < dw; x++) {
      final a = (x * dx).toInt();
      var b = ((x + 1) * dx).toInt();
      if (b == a) b++;
      x0[x] = min(a, sw - 1);
      x1[x] = min(b, sw);
    }
    final y0 = Int32List(dh), y1 = Int32List(dh);
    for (var y = 0; y < dh; y++) {
      final a = (y * dy).toInt();
      var b = ((y + 1) * dy).toInt();
      if (b == a) b++;
      y0[y] = min(a, sh - 1);
      y1[y] = min(b, sh);
    }
    final out = Uint8List(dw * dh * 4);
    final acc = Int32List(dw * 4);
    for (var y = 0; y < dh; y++) {
      acc.fillRange(0, acc.length, 0);
      for (var sy = y0[y]; sy < y1[y]; sy++) {
        final row = sy * sw * 4;
        for (var x = 0; x < dw; x++) {
          var r = 0, g = 0, b = 0, a = 0;
          for (var i = row + x0[x] * 4, end = row + x1[x] * 4; i < end; i += 4) {
            r += src[i];
            g += src[i + 1];
            b += src[i + 2];
            a += src[i + 3];
          }
          final j = x * 4;
          acc[j] += r;
          acc[j + 1] += g;
          acc[j + 2] += b;
          acc[j + 3] += a;
        }
      }
      final rows = y1[y] - y0[y];
      var o = y * dw * 4;
      for (var x = 0; x < dw; x++) {
        final n = rows * (x1[x] - x0[x]);
        final j = x * 4;
        out[o++] = acc[j] ~/ n;
        out[o++] = acc[j + 1] ~/ n;
        out[o++] = acc[j + 2] ~/ n;
        out[o++] = acc[j + 3] ~/ n;
      }
    }
    return out;
  }

  /// True for a JPEG whose EXIF asks for a rotation or flip. Those keep
  /// using the Dart decoder, which has always applied the flag. Camera
  /// captures carry no such flag (their pixels are already upright).
  @visibleForTesting
  static bool needsDartOrientation(Uint8List data) {
    if (data.length < 4 || data[0] != 0xFF || data[1] != 0xD8) return false;
    try {
      final orientation = img.decodeJpgExif(data)?.imageIfd.orientation;
      return orientation != null && orientation > 1;
    } catch (_) {
      return true;
    }
  }
}
