import '../core/config/gemini_config.dart';
import '../core/errors/app_error.dart';
import '../models/authentication_result.dart';
import '../models/evidence.dart';
import '../models/evidence_record.dart';
import '../models/product.dart';
import '../models/product_identification.dart';
import '../services/evidence_decision_engine.dart';
import '../services/evidence_planner.dart';
import 'gemini_authentication_repository.dart';

export 'gemini_authentication_repository.dart' show ScanContext, PhotoCheckResult;

/// Single entry point for the scan pipeline.
///
/// There is no mock or demo path: if inference is unavailable the caller gets
/// a real error, never a fabricated product, observation or report.
class AuthenticationRepository {
  final GeminiAuthenticationRepository _gemini;

  AuthenticationRepository({required GeminiAuthenticationRepository geminiRepo}) : _gemini = geminiRepo;

  bool get isConfigured => GeminiConfig.hasValidKey;

  void _requireConfigured() {
    if (!isConfigured) throw AppError.apiUnauthorized();
  }

  /// Stage A: what is this, and how sure are we of each attribute?
  Future<ProductIdentification> identifyProduct(String imagePath) {
    _requireConfigured();
    return _gemini.identifyProduct(imagePath);
  }

  ScanContext createContext(Product product) => _gemini.createContext(product);

  /// Stage B: model-specific ranking of the photos worth asking for.
  Future<AiEvidenceRanking> recommendEvidence(ScanContext ctx, {Set<String> covered = const {}}) {
    _requireConfigured();
    return _gemini.recommendEvidence(ctx, covered: covered);
  }

  Future<PhotoEvidence> analyzeInitialPhoto({required ScanContext ctx, required String imagePath, List<double>? itemBox}) {
    _requireConfigured();
    return _gemini.analyzeInitialPhoto(ctx: ctx, imagePath: imagePath, itemBox: itemBox);
  }

  /// Quality and part check for one submitted photo.
  Future<PhotoCheckResult> checkPhoto({
    required ScanContext ctx,
    required String imagePath,
    required String? requestedId,
    List<PhotoEvidence> existing = const [],
  }) {
    _requireConfigured();
    return _gemini.checkPhoto(ctx: ctx, imagePath: imagePath, requestedId: requestedId, existing: existing);
  }

  /// Product-specific analysis of one accepted photo.
  Future<PhotoEvidence> analyzePhoto({required ScanContext ctx, required PhotoCheckResult check, bool keptDespiteLowQuality = false}) {
    _requireConfigured();
    return _gemini.analyzePhoto(ctx: ctx, check: check, keptDespiteLowQuality: keptDespiteLowQuality);
  }

  ScanContext absorbPhoto(ScanContext ctx, PhotoEvidence photo) => _gemini.absorbPhoto(ctx, photo);

  EngineResult evaluate(ScanContext ctx, List<PhotoEvidence> photos) => _gemini.evaluate(ctx, photos);

  EvidencePlan plan(ScanContext ctx, List<PhotoEvidence> photos, EngineResult result,
          {Set<String> skipped = const {}, Map<String, int> retakeSuggestions = const {}}) =>
      _gemini.plan(ctx, photos, result, skipped: skipped, retakeSuggestions: retakeSuggestions);

  List<EvidenceItem> requestItems(ScanContext ctx, EvidencePlan plan, List<PhotoEvidence> photos, Set<String> skipped) =>
      GeminiAuthenticationRepository.requestItems(ctx, plan, photos, skipped);

  /// Final evidence evaluation and the structured report.
  Future<AuthenticationReport> finalizeReport({
    required ScanContext ctx,
    required List<PhotoEvidence> photos,
    Set<String> skipped = const {},
    Map<String, int> retakeSuggestions = const {},
    String? scanId,
  }) {
    _requireConfigured();
    return _gemini.finalizeReport(
      ctx: ctx,
      photos: photos,
      skipped: skipped,
      retakeSuggestions: retakeSuggestions,
      scanId: scanId,
    );
  }

  /// Moves a camera/gallery temp file into permanent app storage so reports
  /// keep resolving their images after a restart. [stripExif] mirrors the
  /// "Anonymous Scanning" privacy setting.
  void prewarmPhoto(String imagePath, {bool initial = false}) => _gemini.prewarmPhoto(imagePath, initial: initial);

  Future<String> persistCapturedImage(String tempPath, {String prefix = 'evidence', bool stripExif = false}) {
    return _gemini.imagePrep.persistCapturedImage(tempPath, prefix: prefix, stripExif: stripExif);
  }

  Future<void> deleteStoredImages(Iterable<String> paths) => _gemini.imagePrep.deleteStoredImages(paths);

  void clearScanCaches() => _gemini.clearScanCaches();

  /// Frees the in-memory decoded/resized image cache (used by "Clear Image
  /// Cache" in Settings). Does not delete the underlying files on disk.
  void clearImageMemoryCache() => _gemini.imagePrep.clearCache();

  /// Real current size of that cache, in bytes.
  int get imageMemoryCacheBytes => _gemini.imagePrep.cacheSizeBytes;
}
