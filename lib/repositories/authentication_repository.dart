import '../core/config/gemini_config.dart';
import '../core/errors/app_error.dart';
import '../models/authentication_result.dart';
import '../models/evidence.dart';
import '../models/evidence_validation.dart';
import '../models/product.dart';
import '../models/product_identification.dart';
import 'gemini_authentication_repository.dart';

/// Single entry point for the scan pipeline.
///
/// There is no mock or demo path: if inference is unavailable the caller gets
/// a real error, never a fabricated product, score or report (§30, §46).
class AuthenticationRepository {
  final GeminiAuthenticationRepository _gemini;

  AuthenticationRepository({required GeminiAuthenticationRepository geminiRepo})
      : _gemini = geminiRepo;

  bool get isConfigured => GeminiConfig.hasValidKey;

  void _requireConfigured() {
    if (!isConfigured) throw AppError.apiUnauthorized();
  }

  /// Step 1 — identify what the item is from the user's first photo.
  Future<ProductIdentification> identifyProduct(String imagePath) {
    _requireConfigured();
    return _gemini.identifyProduct(imagePath);
  }

  /// Step 2 — the product-specific 5-6 angle capture plan.
  Future<List<EvidenceItem>> getRequiredEvidence(Product product) {
    _requireConfigured();
    return _gemini.getRequiredEvidence(product);
  }

  /// Step 3 — does this photo actually show the requested area, and is it usable?
  Future<EvidenceValidationResult> validateEvidencePhoto({
    required String imagePath,
    required EvidenceItem requestedItem,
    required Product product,
  }) {
    _requireConfigured();
    return _gemini.validateEvidencePhoto(
      imagePathOrAsset: imagePath,
      requestedItem: requestedItem,
      product: product,
    );
  }

  /// Step 4 — analyse every accepted image together and score locally.
  Future<AuthenticationReport> finalizeReport({
    required Product product,
    required List<EvidenceItem> evidenceItems,
    required Map<String, String> capturedImages,
    String? overviewImagePath,
    int identificationConfidence = 0,
  }) {
    _requireConfigured();
    return _gemini.finalizeReport(
      product: product,
      evidenceItems: evidenceItems,
      capturedImages: capturedImages,
      overviewImagePath: overviewImagePath,
      identificationConfidence: identificationConfidence,
    );
  }

  /// Moves a camera/gallery temp file into permanent app storage so reports
  /// keep resolving their images after a restart. [stripExif] mirrors the
  /// "Anonymous Scanning" privacy setting.
  Future<String> persistCapturedImage(
    String tempPath, {
    String prefix = 'evidence',
    bool stripExif = false,
  }) {
    return _gemini.imagePrep.persistCapturedImage(tempPath, prefix: prefix, stripExif: stripExif);
  }

  Future<void> deleteStoredImages(Iterable<String> paths) {
    return _gemini.imagePrep.deleteStoredImages(paths);
  }

  void clearScanCaches() => _gemini.clearScanCaches();

  /// Frees the in-memory decoded/resized image cache (used by "Clear Image
  /// Cache" in Settings). Does not delete the underlying files on disk -
  /// those are only removed when a report/item is actually deleted.
  void clearImageMemoryCache() => _gemini.imagePrep.clearCache();

  /// Real current size of that cache, in bytes.
  int get imageMemoryCacheBytes => _gemini.imagePrep.cacheSizeBytes;
}
