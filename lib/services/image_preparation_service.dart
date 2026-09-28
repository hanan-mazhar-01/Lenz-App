import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../core/errors/app_error.dart';
import 'image_origin.dart';
import 'native_image_decoder.dart';

/// Sizing presets. Only the user's own photo is ever sent, resized; the app
/// creates no additional images from it.
enum ImagePreset {
  /// First photo -> "what is this?".
  identification(maxDimension: 1024, jpegQuality: 85),

  /// Per-photo quality and part check.
  validation(maxDimension: 1024, jpegQuality: 85),

  /// The photo for the product-specific analysis. Kept large enough that
  /// engravings and small text survive.
  evidence(maxDimension: 1536, jpegQuality: 90);

  final int maxDimension;
  final int jpegQuality;
  const ImagePreset({required this.maxDimension, required this.jpegQuality});
}

class PreparedImage {
  final String base64Data;
  final String mimeType;
  final int byteSize;
  final int width;
  final int height;
  final String? localFilePath;

  const PreparedImage({
    required this.base64Data,
    required this.mimeType,
    required this.byteSize,
    required this.width,
    required this.height,
    this.localFilePath,
  });

  Map<String, dynamic> toInlineData() {
    return {
      'inline_data': {
        'mime_type': mimeType,
        'data': base64Data,
      },
    };
  }
}

class _ResizeRequest {
  final Uint8List bytes;
  final int maxDimension;
  final int jpegQuality;
  const _ResizeRequest(this.bytes, this.maxDimension, this.jpegQuality);
}

class _ResizeResult {
  final Uint8List bytes;
  final int width;
  final int height;
  const _ResizeResult(this.bytes, this.width, this.height);
}

class _EncodeRequest {
  final PixelBuffer pixels;
  final int maxDimension;
  final int jpegQuality;
  const _EncodeRequest(this.pixels, this.maxDimension, this.jpegQuality);
}

/// Runs off the UI isolate: resizes an already decoded (upright) photo and
/// encodes it. Much cheaper than decoding the full-resolution original.
_ResizeResult _encodeDecoded(_EncodeRequest req) {
  final src = req.pixels.toImage();
  img.Image out = src;
  final longest = src.width > src.height ? src.width : src.height;
  if (longest > req.maxDimension) {
    out = src.width >= src.height
        ? img.copyResize(src, width: req.maxDimension, interpolation: img.Interpolation.average)
        : img.copyResize(src, height: req.maxDimension, interpolation: img.Interpolation.average);
  }
  final encoded = img.encodeJpg(out, quality: req.jpegQuality);
  return _ResizeResult(Uint8List.fromList(encoded), out.width, out.height);
}

/// Fallback when the native decoder can't be used. Runs off the UI isolate;
/// on a low-end phone this takes seconds for a full-resolution photo.
_ResizeResult _resizeInIsolate(_ResizeRequest req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported or corrupt image data');
  }

  // Honour the EXIF orientation flag so a portrait capture isn't analysed sideways.
  final oriented = img.bakeOrientation(decoded);

  img.Image out = oriented;
  final longest = oriented.width > oriented.height ? oriented.width : oriented.height;
  if (longest > req.maxDimension) {
    if (oriented.width >= oriented.height) {
      out = img.copyResize(oriented, width: req.maxDimension, interpolation: img.Interpolation.average);
    } else {
      out = img.copyResize(oriented, height: req.maxDimension, interpolation: img.Interpolation.average);
    }
  }

  final encoded = img.encodeJpg(out, quality: req.jpegQuality);
  return _ResizeResult(Uint8List.fromList(encoded), out.width, out.height);
}

/// Runs off the UI isolate: decodes, strips all EXIF directories (which is
/// where GPS coordinates and other metadata live), and re-encodes. Returns
/// the original bytes unchanged if the image can't be decoded, rather than
/// failing the capture over a metadata-privacy nicety.
Uint8List _stripExifInIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  decoded.exif.clear();
  return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
}

class ImagePreparationService {
  final Map<String, PreparedImage> _memoryCache = {};

  /// Origin hints by stored path, read from the ORIGINAL file before any
  /// EXIF stripping (see [ImageOrigin]).
  final Map<String, String?> _originHints = {};

  /// Where the photo seems to come from, or null for an ordinary camera
  /// photo (or when unknown).
  String? originHint(String storedPath) => _originHints[storedPath];
  final Map<String, Future<PreparedImage>> _inFlight = {};

  /// Starts preparing [pathOrAsset] for [preset] in the background, so the
  /// upload is ready by the time it is needed (for example the analysis
  /// upload is prepared while the photo check is still with Gemini).
  /// Errors are ignored here; the real call reports them.
  void warm(String pathOrAsset, ImagePreset preset) {
    unawaited(prepareImage(pathOrAsset, preset: preset).then((_) {}, onError: (Object _) {}));
  }

  /// Real total size of the in-memory decoded-image cache, for display in
  /// Settings' "Clear Image Cache" row instead of a hardcoded number.
  int get cacheSizeBytes => _memoryCache.values.fold(0, (sum, img) => sum + img.byteSize);

  /// Loads an image from an asset path or the filesystem, downscales it to the
  /// preset, and returns base64 JPEG ready for inline upload.
  ///
  /// Throws [AppError] when the image genuinely cannot be read — it never
  /// substitutes a stand-in image, because a silent substitution would make the
  /// model analyse something the user never photographed.
  Future<PreparedImage> prepareImage(
    String pathOrAsset, {
    ImagePreset preset = ImagePreset.evidence,
  }) async {
    final cacheKey = '$pathOrAsset|${preset.name}';
    final cached = _memoryCache[cacheKey];
    if (cached != null) return cached;
    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;

    final future = _prepare(pathOrAsset, preset);
    _inFlight[cacheKey] = future;
    try {
      final prepared = await future;
      _memoryCache[cacheKey] = prepared;
      return prepared;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<PreparedImage> _prepare(String pathOrAsset, ImagePreset preset) async {
    final watch = Stopwatch()..start();
    final isAsset = pathOrAsset.startsWith('assets/');
    if (!isAsset) {
      if (!await File(pathOrAsset).exists()) {
        throw AppError.unknown(
          detail: 'The photo for this step is no longer available on the device. Please recapture it.',
        );
      }
      // Fast path: the photo decoded once natively, shared with the
      // quality checks and the other upload size.
      final decoded = await NativeImageDecoder.decode(pathOrAsset);
      if (decoded != null) {
        final _ResizeResult resized;
        try {
          resized = await compute(
            _encodeDecoded,
            _EncodeRequest(decoded.forMaxDimension(preset.maxDimension), preset.maxDimension, preset.jpegQuality),
          );
        } catch (e) {
          throw AppError.unknown(detail: 'That image could not be processed. Please retake the photo.', original: e);
        }
        if (kDebugMode) {
          debugPrint('[ImagePrep] ${preset.name}: ${decoded.originalWidth}x${decoded.originalHeight} -> '
              '${resized.bytes.length ~/ 1024}KB (${resized.width}x${resized.height}) in '
              '${watch.elapsedMilliseconds}ms (native decode)');
        }
        return PreparedImage(
          base64Data: base64Encode(resized.bytes),
          mimeType: 'image/jpeg',
          byteSize: resized.bytes.length,
          width: resized.width,
          height: resized.height,
          localFilePath: pathOrAsset,
        );
      }
    }

    final Uint8List raw;
    try {
      if (pathOrAsset.startsWith('assets/')) {
        final byteData = await rootBundle.load(pathOrAsset);
        raw = byteData.buffer.asUint8List();
      } else {
        final file = File(pathOrAsset);
        if (!await file.exists()) {
          throw AppError.unknown(
            detail: 'The photo for this step is no longer available on the device. Please recapture it.',
          );
        }
        raw = await file.readAsBytes();
      }
    } on AppError {
      rethrow;
    } catch (e) {
      throw AppError.unknown(detail: 'Could not read the captured image.', original: e);
    }

    if (raw.isEmpty) {
      throw AppError.unknown(detail: 'The captured image file is empty. Please retake the photo.');
    }

    _ResizeResult resized;
    try {
      resized = await compute(
        _resizeInIsolate,
        _ResizeRequest(raw, preset.maxDimension, preset.jpegQuality),
      );
    } catch (e) {
      throw AppError.unknown(detail: 'That image could not be processed. Please retake the photo.', original: e);
    }

    final prepared = PreparedImage(
      base64Data: base64Encode(resized.bytes),
      mimeType: 'image/jpeg',
      byteSize: resized.bytes.length,
      width: resized.width,
      height: resized.height,
      localFilePath: isAsset ? null : pathOrAsset,
    );

    if (kDebugMode) {
      final savedPct = raw.isEmpty ? 0 : (100 - (resized.bytes.length / raw.length * 100)).round();
      debugPrint(
        '[ImagePrep] ${preset.name}: ${raw.length ~/ 1024}KB -> ${resized.bytes.length ~/ 1024}KB '
        '(${resized.width}x${resized.height}, -$savedPct%) in ${watch.elapsedMilliseconds}ms (Dart decode)',
      );
    }
    return prepared;
  }

  /// Encodes pixels already in memory (e.g. an in-memory detail crop) as an
  /// upload-ready JPEG. Nothing is written to disk.
  Future<PreparedImage> encodePixels(PixelBuffer pixels, {int maxDimension = 1024, int jpegQuality = 90}) async {
    final resized = await compute(_encodeDecoded, _EncodeRequest(pixels, maxDimension, jpegQuality));
    return PreparedImage(
      base64Data: base64Encode(resized.bytes),
      mimeType: 'image/jpeg',
      byteSize: resized.bytes.length,
      width: resized.width,
      height: resized.height,
    );
  }

  /// Copies a camera/gallery temp file into app documents so the report still
  /// resolves its images after the OS clears the cache directory.
  ///
  /// When [stripExif] is true (the "Anonymous Scanning" privacy setting),
  /// the persisted copy has all EXIF metadata - including GPS location -
  /// removed before it's saved, uploaded to Cloudinary, or sent to Gemini.
  Future<String> persistCapturedImage(
    String tempPath, {
    String prefix = 'scan',
    bool stripExif = false,
  }) async {
    try {
      final file = File(tempPath);
      if (!await file.exists()) return tempPath;

      final docsDir = await getApplicationDocumentsDirectory();
      final reportDir = Directory('${docsDir.path}/vericheck_evidence');
      if (!await reportDir.exists()) {
        await reportDir.create(recursive: true);
      }

      // Already inside our permanent store — nothing to do (already
      // persisted once; re-stripping here would be a no-op at best).
      if (tempPath.startsWith(reportDir.path)) return tempPath;

      String? origin;
      try {
        origin = ImageOrigin.hint(await file.readAsBytes());
      } catch (_) {
        // Unknown origin: no hint.
      }

      final ext = tempPath.contains('.') ? tempPath.substring(tempPath.lastIndexOf('.')) : '.jpg';
      final safeExt = ext.length <= 5 ? ext : '.jpg';
      final fileName = '${prefix}_${DateTime.now().microsecondsSinceEpoch}$safeExt';
      final permanentFile = File('${reportDir.path}/$fileName');

      if (stripExif) {
        try {
          final rawBytes = await file.readAsBytes();
          final stripped = await compute(_stripExifInIsolate, rawBytes);
          await permanentFile.writeAsBytes(stripped);
          _originHints[permanentFile.path] = origin;
          return permanentFile.path;
        } catch (e) {
          if (kDebugMode) debugPrint('[ImagePrep] EXIF strip failed, falling back to plain copy: $e');
          // Fall through to the plain copy below rather than losing the photo.
        }
      }

      await file.copy(permanentFile.path);
      _originHints[permanentFile.path] = origin;
      return permanentFile.path;
    } catch (e) {
      if (kDebugMode) debugPrint('[ImagePrep] persist failed: $e');
      return tempPath;
    }
  }

  /// Removes stored evidence images that no surviving report references.
  Future<void> deleteStoredImages(Iterable<String> paths) async {
    for (final p in paths) {
      if (p.isEmpty || p.startsWith('assets/')) continue;
      // Also removes "_detail.jpg" copies left by an earlier test build.
      final dot = p.lastIndexOf('.');
      final leftover = '${dot > 0 ? p.substring(0, dot) : p}_detail.jpg';
      for (final path in {p, leftover}) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      _memoryCache.removeWhere((k, _) => k.startsWith('$p|'));
    }
  }

  void clearCache() => _memoryCache.clear();
}
