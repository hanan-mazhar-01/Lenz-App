import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/config/authenticity_engine_config.dart';
import '../models/evidence_record.dart';
import 'image_preparation_service.dart';
import 'native_image_decoder.dart';

/// An in-memory close-up of one photo's detail, sent with the final combined
/// analysis next to the whole photo. Never saved and never shown.
class DetailCrop {
  final String photoId;
  final String title;
  final PreparedImage image;
  const DetailCrop({required this.photoId, required this.title, required this.image});
}

/// Decides which photos get a close-up and builds them.
///
/// A crop is only made when it shows the detail with clearly more pixels
/// than the whole photo does at upload size (1536 px); for photos captured
/// at about 1080x1920 it rarely does, for 8 MP captures it usually does.
abstract final class DetailCropper {
  /// Pixels the detail's long side gets in the crop vs. in the upload copy.
  static double detailGain({required List<double> box, required int originalWidth, required int originalHeight}) {
    final bw = (box[3] - box[1]).clamp(0.0, 1.0) * originalWidth;
    final bh = (box[2] - box[0]).clamp(0.0, 1.0) * originalHeight;
    final boxLong = max(bw, bh) * 1.16; // incl. margin
    if (boxLong <= 0) return 0;
    final inUpload = boxLong * min(1.0, NativeImageDecoder.uploadSide / max(originalWidth, originalHeight));
    final inCrop = min(boxLong, AuthenticityEngineConfig.detailCropMaxSide.toDouble());
    return inCrop / inUpload;
  }

  /// Photos worth a close-up, most useful first (evidence photos before the
  /// first photo, smaller details first).
  static List<PhotoEvidence> candidates(
    List<PhotoEvidence> photos,
    Map<String, ({int width, int height})> originalSizes, {
    int max = AuthenticityEngineConfig.maxDetailCrops,
  }) {
    final scored = <(PhotoEvidence, double)>[];
    for (final p in photos) {
      final box = p.detailBox;
      final size = originalSizes[p.photoId];
      if (box == null || box.length != 4 || size == null) continue;
      final area = (box[2] - box[0]).abs() * (box[3] - box[1]).abs();
      if (area <= 0 || area > 0.5) continue;
      final gain = detailGain(box: box, originalWidth: size.width, originalHeight: size.height);
      if (gain < 1.3) continue;
      scored.add((p, gain + (p.isInitialPhoto ? 0 : 10)));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(max).map((e) => e.$1).toList();
  }

  static Future<List<DetailCrop>> build(List<PhotoEvidence> photos, ImagePreparationService prep) async {
    if (!AuthenticityEngineConfig.finalDetailCrops) return const [];
    final sizes = <String, ({int width, int height})>{};
    for (final p in photos) {
      if (p.detailBox == null) continue;
      final d = await NativeImageDecoder.decode(p.imagePath);
      if (d != null) sizes[p.photoId] = (width: d.originalWidth, height: d.originalHeight);
    }
    final crops = <DetailCrop>[];
    for (final p in candidates(photos, sizes)) {
      final pixels = await NativeImageDecoder.decodeCrop(p.imagePath, p.detailBox!, maxSide: AuthenticityEngineConfig.detailCropMaxSide);
      if (pixels == null) continue;
      final image = await prep.encodePixels(pixels, maxDimension: AuthenticityEngineConfig.detailCropMaxSide, jpegQuality: 90);
      crops.add(DetailCrop(photoId: p.photoId, title: p.requestTitle, image: image));
      if (kDebugMode) debugPrint('[DetailCropper] close-up of ${p.photoId}: ${image.width}x${image.height}, ${image.byteSize ~/ 1024}KB');
    }
    return crops;
  }
}
