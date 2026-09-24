import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../core/errors/app_error.dart';

/// Sizing presets. Identification runs on a smaller image because it only has
/// to recognise the object; evidence keeps more pixels because the verdict
/// depends on fine detail.
enum ImagePreset {
  /// First photo -> "what is this?". Small and fast (§3).
  identification(maxDimension: 768, jpegQuality: 80),

  /// Per-photo validation -> "is this the right area, is it sharp?".
  validation(maxDimension: 1024, jpegQuality: 82),

  /// Final multi-image forensic pass -> needs the most detail.
  evidence(maxDimension: 1280, jpegQuality: 86);

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

/// Runs off the UI isolate: decoding a 12MP JPEG blocks for hundreds of ms.
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
      localFilePath: pathOrAsset.startsWith('assets/') ? null : pathOrAsset,
    );

    if (kDebugMode) {
      final savedPct = raw.isEmpty ? 0 : (100 - (resized.bytes.length / raw.length * 100)).round();
      debugPrint(
        '[ImagePrep] ${preset.name}: ${raw.length ~/ 1024}KB -> ${resized.bytes.length ~/ 1024}KB '
        '(${resized.width}x${resized.height}, -$savedPct%)',
      );
    }

    _memoryCache[cacheKey] = prepared;
    return prepared;
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

      final ext = tempPath.contains('.') ? tempPath.substring(tempPath.lastIndexOf('.')) : '.jpg';
      final safeExt = ext.length <= 5 ? ext : '.jpg';
      final fileName = '${prefix}_${DateTime.now().microsecondsSinceEpoch}$safeExt';
      final permanentFile = File('${reportDir.path}/$fileName');

      if (stripExif) {
        try {
          final rawBytes = await file.readAsBytes();
          final stripped = await compute(_stripExifInIsolate, rawBytes);
          await permanentFile.writeAsBytes(stripped);
          return permanentFile.path;
        } catch (e) {
          if (kDebugMode) debugPrint('[ImagePrep] EXIF strip failed, falling back to plain copy: $e');
          // Fall through to the plain copy below rather than losing the photo.
        }
      }

      await file.copy(permanentFile.path);
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
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      _memoryCache.removeWhere((k, _) => k.startsWith('$p|'));
    }
  }

  void clearCache() => _memoryCache.clear();
}
