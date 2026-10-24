import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/config/authenticity_engine_config.dart';
import '../core/errors/app_error.dart';
import '../data/evidence_profiles.dart';
import '../models/authentication_result.dart';
import '../models/capture_guide.dart';
import '../models/evidence.dart';
import '../models/evidence_record.dart';
import '../models/evidence_validation.dart';
import '../models/photo_quality.dart';
import '../models/product.dart';
import '../models/product_identification.dart';
import '../models/product_identity.dart';
import '../models/product_reference.dart';
import '../services/api_usage.dart';
import '../services/assessment_builder.dart';
import '../services/authenticity_prompts.dart';
import '../services/detail_cropper.dart';
import '../services/evidence_decision_engine.dart';
import '../services/evidence_planner.dart';
import '../services/final_verdict_validator.dart';
import '../services/gemini_service.dart';
import '../services/image_hash.dart';
import '../services/image_preparation_service.dart';
import '../services/image_quality_checker.dart';
import '../services/scan_consistency_service.dart';

/// Everything the pipeline knows about the product during one scan.
class ScanContext {
  final Product product;
  final ResolvedProfile profile;
  final AiEvidenceRanking? ranking;

  const ScanContext({required this.product, required this.profile, this.ranking});

  ProductIdentity get identity => profile.identity;

  ScanContext copyWith({Product? product, ResolvedProfile? profile, AiEvidenceRanking? ranking}) => ScanContext(
        product: product ?? this.product,
        profile: profile ?? this.profile,
        ranking: ranking ?? this.ranking,
      );
}

/// Result of checking one submitted photo, before it becomes evidence.
class PhotoCheckResult {
  final String imagePath;
  final String? requestedId;

  /// The request this photo satisfies, or "none".
  final String matchedRequestId;
  final String partShown;
  final LocalImageQualityResult local;
  final PhotoQualitySummary quality;

  /// Normalised [ymin, xmin, ymax, xmax] of the detail, when found.
  final List<double>? detailBox;

  /// Validation record shown on the photo review screen.
  final EvidenceValidationResult validation;

  /// Set when this is the same picture as an earlier photo.
  final String? duplicateOfPhotoId;

  const PhotoCheckResult({
    required this.imagePath,
    required this.requestedId,
    required this.matchedRequestId,
    required this.partShown,
    required this.local,
    required this.quality,
    required this.detailBox,
    required this.validation,
    this.duplicateOfPhotoId,
  });

  bool get isDuplicate => duplicateOfPhotoId != null;

  /// The requested part is visible (possibly with a quality warning).
  bool get showsRequestedPart => validation.matchToRequestedEvidence;
}

/// Real inference pipeline for engine v3. Every value it returns originates
/// in a model response, an on-device measurement or the local decision
/// engine. A failed or malformed call surfaces as an [AppError]; it is never
/// turned into an "Unable to verify" result.
class GeminiAuthenticationRepository {
  final GeminiService _geminiService;
  final ImagePreparationService _imagePrep;

  final Map<String, ProductIdentification> _identificationCache = {};

  /// Model-specific photo rankings, kept for the app session so repeat
  /// scans of the same model are asked for the same photos.
  static final Map<String, AiEvidenceRanking> _rankingCache = {};

  final ApiUsageLog usage = ApiUsageLog();

  /// How the final verdict is made (the harness compares both modes).
  final FinalStageMode finalStageMode;

  /// Correlation id of the current scan: sent with every request so app and
  /// Cloud Function logs can be joined, and used by the backend as the
  /// billing session.
  String _scanId = _newScanId();

  GeminiAuthenticationRepository({
    GeminiService? geminiService,
    ImagePreparationService? imagePrep,
    this.finalStageMode = AuthenticityEngineConfig.finalStageMode,
  })  : _geminiService = geminiService ?? GeminiService(),
        _imagePrep = imagePrep ?? ImagePreparationService();

  ImagePreparationService get imagePrep => _imagePrep;

  String get scanSessionId => _scanId;

  static String _newScanId() =>
      'scan_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0xFFFFF).toRadixString(16)}';

  void clearScanCaches() {
    _identificationCache.clear();
    usage.clear();
    _scanId = _newScanId();
  }

  @visibleForTesting
  static void clearRankingCache() => _rankingCache.clear();

  // ---------------------------------------------------------------------------
  // Model call helper: usage accounting, one retry on malformed output.
  // ---------------------------------------------------------------------------

  Future<T> _call<T>({
    required String label,
    required String prompt,
    required List<Map<String, dynamic>> images,
    required Map<String, dynamic> schema,
    required int maxOutputTokens,
    required Duration timeout,
    required T Function(Map<String, dynamic> json) parse,
    String? thinkingLevel,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      final started = DateTime.now();
      final response = await _geminiService.generateStructuredContent(
        prompt: attempt == 1
            ? prompt
            : '$prompt\n\nYour previous answer did not match the required JSON structure. Return every required field.',
        inlineImages: images.isEmpty ? null : images,
        requestTypeLabel: label,
        maxOutputTokens: maxOutputTokens,
        timeout: timeout,
        responseSchema: schema,
        scanId: _scanId,
        thinkingLevel: thinkingLevel,
      );
      usage.add(ApiCallUsage.fromResponse(
        label: label,
        response: response,
        prompt: prompt,
        images: images.length,
        durationMs: DateTime.now().difference(started).inMilliseconds,
      ));
      try {
        return parse(response);
      } on FormatException catch (e) {
        lastError = e;
        if (kDebugMode) debugPrint('[Auth] $label: malformed response ($e), attempt $attempt');
      }
    }
    throw AppError.invalidResponse(original: lastError);
  }

  // ---------------------------------------------------------------------------
  // 1. Product recognition
  // ---------------------------------------------------------------------------

  /// Starts preparing both upload sizes of a new photo in the background,
  /// so they are ready when the on-device check and Gemini calls need them.
  void prewarmPhoto(String imagePath, {bool initial = false}) {
    _imagePrep.warm(imagePath, initial ? ImagePreset.identification : ImagePreset.validation);
    _imagePrep.warm(imagePath, ImagePreset.evidence);
  }

  Future<ProductIdentification> identifyProduct(String imagePath) async {
    final cached = _identificationCache[imagePath];
    if (cached != null) return cached;

    prewarmPhoto(imagePath, initial: true);
    final prepared = await _imagePrep.prepareImage(imagePath, preset: ImagePreset.identification);
    final origin = _imagePrep.originHint(imagePath);
    final identification = await _call<ProductIdentification>(
      label: 'product_identification_and_validation',
      prompt: origin == null
          ? AuthenticityPrompts.identificationPrompt
          : '${AuthenticityPrompts.identificationPrompt}\nIMAGE FILE (a hint only; decide image_source from what you see): $origin',
      images: [prepared.toInlineData()],
      schema: AuthenticityPrompts.identificationSchema,
      maxOutputTokens: 1200,
      timeout: const Duration(seconds: 60),
      parse: (json) {
        if (json['status'] == null && json['product_detected'] == null) {
          throw const FormatException('identification without status');
        }
        return ProductIdentification.fromJson(json);
      },
    );
    _identificationCache[imagePath] = identification;
    return identification;
  }

  /// Resolves the evidence profile for an identified product.
  ScanContext createContext(Product product) {
    final identity = product.identity ?? _identityFromProduct(product);
    final profile = EvidenceProfileRegistry.resolve(identity);
    return ScanContext(product: product.copyWith(identity: identity, profileId: profile.id), profile: profile);
  }

  static ProductIdentity _identityFromProduct(Product p) => ProductIdentity(
        categoryCode: p.categoryCode ?? ProductIdentification.codeForCategory(p.category),
        brand: p.hasIdentifiedBrand
            ? IdentityAttribute(value: p.brand, status: AttributeStatus.probable, source: IdentitySource.design)
            : IdentityAttribute.unknown,
        modelFamily: p.hasIdentifiedModel
            ? IdentityAttribute(value: p.model, status: AttributeStatus.probable, source: IdentitySource.design)
            : IdentityAttribute.unknown,
      );

  /// Folds identity information revealed by a photo (device screen, label)
  /// into the context, re-resolving the profile if it changes.
  ScanContext absorbPhoto(ScanContext ctx, PhotoEvidence photo) {
    final hasIdentity = photo.brand.isKnown || photo.modelFamily.isKnown || photo.generation.isKnown || photo.exactModel.isKnown;
    if (!hasIdentity) return ctx;
    final merged = ctx.identity.mergedWith(
      brand: photo.brand.isKnown ? photo.brand : null,
      modelFamily: photo.modelFamily.isKnown ? photo.modelFamily : null,
      generation: photo.generation.isKnown ? photo.generation : null,
      exactModel: photo.exactModel.isKnown ? photo.exactModel : null,
      sourceLabel: photo.requestTitle,
    );
    final profile = EvidenceProfileRegistry.resolve(merged);
    final name = [merged.modelFamily.value].whereType<String>().join(' ');
    final product = ctx.product.copyWith(
      identity: merged,
      profileId: profile.id,
      brand: merged.brand.value ?? ctx.product.brand,
      name: name.isEmpty ? ctx.product.name : name,
      model: [merged.modelFamily.value, merged.generation.value].whereType<String>().join(' ').trim().isEmpty
          ? ctx.product.model
          : [merged.modelFamily.value, merged.generation.value].whereType<String>().join(' ').trim(),
    );
    // A different profile means a different candidate list: drop the old
    // ranking so it is recomputed for the new profile.
    return ScanContext(product: product, profile: profile, ranking: profile.id == ctx.profile.id ? ctx.ranking : null);
  }

  // ---------------------------------------------------------------------------
  // 2. Evidence recommendation (text only)
  // ---------------------------------------------------------------------------

  Future<AiEvidenceRanking> recommendEvidence(ScanContext ctx, {Set<String> covered = const {}}) async {
    final id = ctx.identity;
    final key = '${ctx.profile.id}|${id.brand.value}|${id.modelFamily.value}|${id.generation.value}'.toLowerCase();
    final cached = _rankingCache[key];
    if (cached != null) return cached;
    final validIds = {for (final r in ctx.profile.profile.requests) r.id};
    final ranking = await _call<AiEvidenceRanking>(
      label: 'evidence_recommendation',
      prompt: AuthenticityPrompts.recommendationPrompt(profile: ctx.profile, coveredRequestIds: covered),
      images: const [],
      schema: AuthenticityPrompts.recommendationSchema(ctx.profile),
      maxOutputTokens: 1500,
      timeout: const Duration(seconds: 60),
      parse: (json) {
        if (json['ranked'] is! List) throw const FormatException('ranking without "ranked"');
        return AiEvidenceRanking.fromJson(json, validIds);
      },
    );
    _rankingCache[key] = ranking;
    return ranking;
  }

  // ---------------------------------------------------------------------------
  // 3. Image-quality and part check
  // ---------------------------------------------------------------------------

  Future<PhotoCheckResult> checkPhoto({
    required ScanContext ctx,
    required String imagePath,
    required String? requestedId,
    List<PhotoEvidence> existing = const [],
  }) async {
    final requested = requestedId == null ? null : ctx.profile.request(requestedId);
    // The check upload and the analysis upload are prepared while the
    // on-device check runs, from the same single decode.
    prewarmPhoto(imagePath);
    final local = await ImageQualityChecker.evaluate(imagePath);
    final requestTitle = requested?.title ?? 'Additional photo';

    if (!local.isUsable) {
      return PhotoCheckResult(
        imagePath: imagePath,
        requestedId: requestedId,
        matchedRequestId: 'none',
        partShown: '',
        local: local,
        quality: PhotoQualitySummary(issues: const ['UNUSABLE'], fix: local.message, score: 0),
        detailBox: null,
        validation: _validation(
          requestedId: requestedId ?? 'additional',
          requestedTitle: requestTitle,
          partShown: 'nothing usable',
          match: false,
          qualityScore: 0,
          reason: local.message,
          fix: local.message,
        ),
      );
    }

    // The same picture as before adds nothing and must not count twice.
    for (final p in existing) {
      if (p.imageHash.isNotEmpty && local.imageHash.isNotEmpty && ImageHash.isDuplicate(p.imageHash, local.imageHash)) {
        return PhotoCheckResult(
          imagePath: imagePath,
          requestedId: requestedId,
          matchedRequestId: 'none',
          partShown: p.requestTitle,
          local: local,
          quality: const PhotoQualitySummary(),
          detailBox: null,
          duplicateOfPhotoId: p.photoId,
          validation: _validation(
            requestedId: requestedId ?? 'additional',
            requestedTitle: requestTitle,
            partShown: 'the same photo as "${p.requestTitle}"',
            match: false,
            qualityScore: local.qualityScore,
            reason: 'This is the same picture as your "${p.requestTitle}" photo.',
            fix: 'Take a new photo of the ${requestTitle.toLowerCase()} instead.',
          ),
        );
      }
    }

    final prepared = await _imagePrep.prepareImage(imagePath, preset: ImagePreset.validation);
    final json = await _call<Map<String, dynamic>>(
      label: 'evidence_validation:${requestedId ?? 'additional'}',
      prompt: AuthenticityPrompts.photoCheckPrompt(
        profile: ctx.profile,
        requested: requested,
        localIssues: local.issues,
        originHint: _imagePrep.originHint(imagePath),
      ),
      images: [prepared.toInlineData()],
      schema: AuthenticityPrompts.photoCheckSchema(ctx.profile),
      maxOutputTokens: 700,
      timeout: const Duration(seconds: 60),
      parse: (j) {
        for (final k in ['matched_request_id', 'usable', 'detail_readability', 'shows_requested_part']) {
          if (j[k] == null) throw FormatException('photo check without $k');
        }
        return j;
      },
    );

    // A picture of a picture (screen, print, internet image) is refused: the
    // real material, depth and construction cannot be seen in it. A
    // screenshot is only fine where the request allows one (device info).
    final source = json['image_source']?.toString() ?? 'PHYSICAL_ITEM';
    final notReal = source == 'SCREEN_OR_PRINT' ||
        source == 'INTERNET_IMAGE' ||
        (source == 'DEVICE_SCREENSHOT' && !(requested?.screenshotOk ?? false));
    if (notReal) {
      if (kDebugMode) debugPrint('[PhotoCheck] refused: image_source=$source');
      return PhotoCheckResult(
        imagePath: imagePath,
        requestedId: requestedId,
        matchedRequestId: 'none',
        partShown: 'a picture from the internet or a screen',
        local: local,
        quality: const PhotoQualitySummary(issues: ['NOT_A_REAL_PHOTO']),
        detailBox: null,
        validation: _validation(
          requestedId: requestedId ?? 'additional',
          requestedTitle: requestTitle,
          partShown: 'a picture from the internet or a screen',
          match: false,
          qualityScore: 0,
          reason: 'This looks like a picture from the internet or a screen, not the item itself.',
          fix: 'Take a photo of the actual item with the camera, not a picture of it.',
        ),
      );
    }

    final validIds = {for (final r in ctx.profile.profile.requests) r.id};
    var matched = json['matched_request_id']?.toString() ?? 'none';
    if (!validIds.contains(matched)) matched = 'none';
    final showsProduct = json['shows_product'] != false;
    final partShown = (json['part_shown']?.toString() ?? '').trim();

    // The photo must show the part that was asked for. A photo of another
    // part is refused (it is never quietly used for a different part), so
    // the user is told what is wrong and what to photograph instead.
    final showsRequested = requestedId == null ? matched != 'none' : json['shows_requested_part'] == true;
    final requestedConfidence =
        ((json['requested_part_confidence'] as num?)?.toInt() ?? (showsRequested ? 80 : 0)).clamp(0, 100);
    final rightPart = showsProduct && showsRequested && requestedConfidence >= 50;
    if (rightPart && requestedId != null) matched = requestedId;
    final box = _parseBox(json['detail_box_2d']);

    // Measure focus and glare on the detail itself, not the whole frame.
    final regional = box == null ? local : await ImageQualityChecker.evaluate(imagePath, region: box);
    final issues = <String>{
      ...((json['issues'] as List?) ?? const []).map((e) => e.toString()).where((e) => e != 'NONE'),
      ...regional.issues,
    }.toList();
    final readability = json['detail_readability']?.toString() ?? 'NA';
    final modelFix = (json['fix']?.toString() ?? '').trim();
    final quality = PhotoQualitySummary(
      issues: issues,
      detailReadability: readability,
      fix: modelFix.isNotEmpty ? modelFix : (regional.correction ?? ''),
      score: ((json['quality_score'] as num?)?.toInt() ?? regional.qualityScore).clamp(0, 100),
      measuredScore: regional.qualityScore,
    );

    final EvidenceValidationResult validation;
    if (!rightPart) {
      final seen = !showsProduct
          ? (partShown.isEmpty ? 'something other than this item' : partShown)
          : (partShown.isNotEmpty ? partShown : (ctx.profile.request(matched)?.title ?? 'a different part'));
      validation = _validation(
        requestedId: requestedId ?? 'additional',
        requestedTitle: requestTitle,
        partShown: seen,
        match: false,
        matchConfidence: 0,
        qualityScore: quality.score,
        reason: 'This photo shows ${seen.toLowerCase()}, not the ${requestTitle.toLowerCase()}.',
        // Tell the user exactly what to photograph instead.
        fix: requested?.instruction ?? (modelFix.isNotEmpty ? modelFix : 'Photograph one of the listed parts of the item.'),
        issues: issues,
      );
    } else {
      // Right part: poor quality is a warning the user may override.
      final severe = regional.hasSevereIssue || readability == 'NOT_READABLE' || json['usable'] == false;
      validation = _validation(
        requestedId: requestedId ?? matched,
        requestedTitle: ctx.profile.request(matched)?.title ?? requestTitle,
        partShown: partShown,
        match: true,
        matchConfidence: requestedConfidence,
        qualityScore: severe ? 30 : quality.score.clamp(45, 100),
        reason: json['reason']?.toString() ?? '',
        fix: quality.fix,
        issues: issues,
      );
    }

    return PhotoCheckResult(
      imagePath: imagePath,
      requestedId: requestedId,
      matchedRequestId: matched,
      partShown: partShown,
      local: regional,
      quality: quality,
      detailBox: box,
      validation: validation,
    );
  }

  static List<double>? _parseBox(dynamic raw) {
    if (raw is! List || raw.length != 4 || !raw.every((v) => v is num)) return null;
    final b = raw.map((v) => ((v as num).toDouble() / 1000).clamp(0.0, 1.0)).toList();
    if (b[2] <= b[0] || b[3] <= b[1]) return null;
    return b;
  }

  static EvidenceValidationResult _validation({
    required String requestedId,
    required String requestedTitle,
    required String partShown,
    required bool match,
    int? matchConfidence,
    required int qualityScore,
    required String reason,
    String fix = '',
    List<String> issues = const [],
  }) {
    return EvidenceValidationResult(
      requestedEvidenceId: requestedId,
      requestedEvidenceTitle: requestedTitle,
      evidenceTypeDetected: partShown,
      matchToRequestedEvidence: match,
      matchConfidence: match ? (matchConfidence ?? 90) : 0,
      quality: PhotoQualityResult(
        qualityScore: qualityScore,
        qualityStatus: PhotoQualityStatus.fromScore(qualityScore),
        explanation: reason,
        sharpness: issues.any((i) => i.contains('BLUR') || i == 'OUT_OF_FOCUS' || i == 'MOTION') ? 40 : qualityScore,
        lighting: issues.any((i) => i == 'TOO_DARK') ? 40 : qualityScore,
        framing: issues.contains('TOO_FAR') || issues.contains('PARTIAL') ? 40 : qualityScore,
        detail: qualityScore,
        improvementTips: fix.isEmpty ? const [] : [fix],
      ),
      usabilityScore: match ? qualityScore.clamp(41, 100) : 0,
      authenticationUsefulness: match ? qualityScore : 0,
      reason: reason,
      issues: issues,
      fix: fix,
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Product-specific visual analysis
  // ---------------------------------------------------------------------------

  /// Analyses the first (identification) photo against the profile, so it
  /// counts as evidence and the planner knows which part it already shows.
  Future<PhotoEvidence> analyzeInitialPhoto({
    required ScanContext ctx,
    required String imagePath,
    List<double>? itemBox,
  }) async {
    final local = await ImageQualityChecker.evaluate(imagePath, region: itemBox);
    return _analyze(
      ctx: ctx,
      photoId: 'overview',
      imagePath: imagePath,
      requestId: null,
      box: itemBox,
      quality: PhotoQualitySummary(
        issues: local.issues,
        fix: local.correction ?? '',
        score: local.qualityScore,
        measuredScore: local.qualityScore,
      ),
      imageHash: local.imageHash,
      isInitial: true,
    );
  }

  Future<PhotoEvidence> analyzePhoto({
    required ScanContext ctx,
    required PhotoCheckResult check,
    bool keptDespiteLowQuality = false,
  }) {
    final requestId = check.matchedRequestId != 'none' ? check.matchedRequestId : check.requestedId;
    return _analyze(
      ctx: ctx,
      photoId: requestId ?? 'photo_${DateTime.now().millisecondsSinceEpoch}',
      imagePath: check.imagePath,
      requestId: requestId,
      box: check.detailBox,
      quality: check.quality,
      imageHash: check.local.imageHash,
      keptDespiteLowQuality: keptDespiteLowQuality,
    );
  }

  Future<PhotoEvidence> _analyze({
    required ScanContext ctx,
    required String photoId,
    required String imagePath,
    required String? requestId,
    required List<double>? box,
    required PhotoQualitySummary quality,
    required String imageHash,
    bool isInitial = false,
    bool keptDespiteLowQuality = false,
  }) async {
    final full = await _imagePrep.prepareImage(imagePath, preset: ImagePreset.evidence);
    final validIds = {for (final r in ctx.profile.profile.requests) r.id};
    final aiChecks = requestId == null ? const <String>[] : (ctx.ranking?.entries[requestId]?.checks ?? const <String>[]);

    final parsed = await _call<({String matched, PhotoEvidence evidence})>(
      label: 'photo_analysis:${requestId ?? photoId}',
      prompt: AuthenticityPrompts.photoAnalysisPrompt(
        profile: ctx.profile,
        requestId: requestId,
        isInitialPhoto: isInitial,
        aiChecks: aiChecks,
      ),
      images: [full.toInlineData()],
      schema: AuthenticityPrompts.photoAnalysisSchema(ctx.profile),
      maxOutputTokens: 3000,
      timeout: const Duration(seconds: 75),
      parse: (json) {
        final list = json['assessments'];
        if (list is! List) throw const FormatException('analysis without assessments');
        final assessments = [
          for (final a in list.whereType<Map>()) CheckpointAssessment.fromJson(Map<String, dynamic>.from(a)),
        ];
        var matched = json['matched_request_id']?.toString() ?? 'none';
        if (!validIds.contains(matched)) matched = 'none';
        final idj = json['identity_evidence'] is Map ? Map<String, dynamic>.from(json['identity_evidence'] as Map) : const {};
        IdentityAttribute attr(String k) => IdentityAttribute.fromParts(idj[k], idj['status'],
            basis: idj['basis'], source: idj['source']);
        final resolvedRequest = requestId ?? (matched == 'none' ? null : matched);
        final title = resolvedRequest == null
            ? 'First photo'
            : (ctx.profile.request(resolvedRequest)?.title ?? 'Photo');
        return (
          matched: matched,
          evidence: PhotoEvidence(
            photoId: photoId,
            requestId: resolvedRequest ?? 'overview',
            requestTitle: isInitial ? 'First photo${resolvedRequest == null ? '' : ' ($title)'}' : title,
            imagePath: imagePath,
            isInitialPhoto: isInitial,
            keptDespiteLowQuality: keptDespiteLowQuality,
            quality: quality,
            assessments: assessments,
            observedText: [
              for (final t in (json['observed_text'] as List? ?? const []))
                if (t.toString().trim().isNotEmpty) t.toString().trim(),
            ],
            summary: json['photo_summary']?.toString() ?? '',
            brand: attr('brand'),
            modelFamily: attr('model_family'),
            generation: attr('generation'),
            exactModel: attr('exact_model'),
            imageHash: imageHash,
            analysisModel: (json['_meta'] as Map?)?['model']?.toString() ?? AuthenticityEngineConfig.defaultModel,
            detailBox: box,
          ),
        );
      },
    );
    return parsed.evidence;
  }

  // ---------------------------------------------------------------------------
  // Live evaluation and planning (local, no network)
  // ---------------------------------------------------------------------------

  EngineResult evaluate(ScanContext ctx, List<PhotoEvidence> photos, {FinalEvaluation? finalEvaluation}) =>
      EvidenceDecisionEngine.evaluate(profile: ctx.profile, photos: photos, finalEvaluation: finalEvaluation);

  EvidencePlan plan(
    ScanContext ctx,
    List<PhotoEvidence> photos,
    EngineResult result, {
    Set<String> skipped = const {},
    Map<String, int> retakeSuggestions = const {},
  }) =>
      EvidencePlanner.plan(
        profile: ctx.profile,
        photos: photos,
        result: result,
        ranking: ctx.ranking,
        skipped: skipped,
        retakeSuggestions: retakeSuggestions,
      );

  // ---------------------------------------------------------------------------
  // 5. Final evidence evaluation + report
  // ---------------------------------------------------------------------------

  Future<FinalEvaluation> finalEvaluation(ScanContext ctx, List<PhotoEvidence> photos, EngineResult preliminary) {
    final mismatches = preliminary.recordsNeedingVariationCheck;
    final keys = {for (final r in mismatches) AuthenticityPrompts.recordKey(r)};
    final provisional = switch (preliminary.verdict) {
      Verdict.likelyAuthentic => 'visually consistent with authentic, pending this check',
      Verdict.likelyReplica => 'likely replica, pending this check',
      Verdict.inconclusive => 'not yet enough evidence either way',
    };
    return _call<FinalEvaluation>(
      // Kept for billing: the Cloud Function charges one scan credit for
      // this label, exactly once per completed scan.
      label: 'multi_image_forensic_observations',
      prompt: AuthenticityPrompts.finalEvaluationPrompt(
        profile: ctx.profile,
        photos: photos,
        mismatches: mismatches,
        supporting: preliminary.supporting,
        provisionalVerdict: provisional,
      ),
      images: const [],
      schema: AuthenticityPrompts.finalEvaluationSchema(mismatches),
      maxOutputTokens: 2500,
      timeout: const Duration(seconds: 75),
      parse: (json) {
        if (json['variation_checks'] is! List || json['identity_consistent'] is! bool) {
          throw const FormatException('final evaluation missing required fields');
        }
        final checks = <String, VariationResult>{};
        for (final v in (json['variation_checks'] as List).whereType<Map>()) {
          final key = v['key']?.toString() ?? '';
          if (!keys.contains(key)) continue;
          checks[key] = VariationResult(
            VariationCheck.parse(v['legitimate_variation']?.toString()),
            v['explanation']?.toString() ?? '',
          );
        }
        // An omitted check is an incomplete answer, not evidence: retried,
        // then surfaced as an error rather than becoming "unable to verify".
        final missing = keys.difference(checks.keys.toSet());
        if (missing.isNotEmpty) throw FormatException('variation checks missing for $missing');
        return FinalEvaluation(
          contradictions: [
            for (final c in (json['cross_photo_contradictions'] as List? ?? const []).whereType<Map>())
              if ((c['description']?.toString() ?? '').trim().isNotEmpty)
                CrossPhotoContradiction(
                  description: c['description'].toString().trim(),
                  photoIds: (c['photo_ids'] as List? ?? const []).map((e) => e.toString()).toList(),
                  severity: c['severity']?.toString() ?? 'moderate',
                  identityRelated: c['identity_related'] == true,
                ),
          ],
          variationChecks: checks,
          identityConsistent: json['identity_consistent'] == true,
          explanation: json['notes']?.toString() ?? '',
          remainingUncertainty: [
            for (final u in (json['remaining_uncertainty'] as List? ?? const []))
              if (u.toString().trim().isNotEmpty) u.toString().trim(),
          ].take(3).toList(),
          model: (json['_meta'] as Map?)?['model']?.toString() ?? AuthenticityEngineConfig.defaultModel,
        );
      },
    );
  }

  /// Engine v4 final stage: every photo (plus in-memory close-ups) in ONE
  /// call, compared with each other, with Gemini's own knowledge of the
  /// product and with the app checklist. No external research.
  Future<({CombinedAnalysis analysis, Map<String, dynamic> images})> combinedAnalysis(
    ScanContext ctx,
    List<PhotoEvidence> photos,
    ProductReference checklist,
    EngineResult preliminary,
  ) async {
    final ordered = [...photos.where((p) => p.isInitialPhoto), ...photos.where((p) => !p.isInitialPhoto)];

    // Whole photos at analysis size; smaller if the request would be too big.
    var preset = ImagePreset.evidence;
    var prepared = await Future.wait(ordered.map((p) => _imagePrep.prepareImage(p.imagePath, preset: preset)));
    int chars(Iterable<PreparedImage> xs) => xs.fold(0, (n, x) => n + x.base64Data.length);
    if (chars(prepared) > AuthenticityEngineConfig.finalImageBudgetChars) {
      preset = ImagePreset.validation;
      prepared = await Future.wait(ordered.map((p) => _imagePrep.prepareImage(p.imagePath, preset: preset)));
    }
    var used = chars(prepared);
    final crops = <DetailCrop>[];
    for (final c in await DetailCropper.build(ordered, _imagePrep)) {
      if (used + c.image.base64Data.length > AuthenticityEngineConfig.finalImageBudgetChars) break;
      used += c.image.base64Data.length;
      crops.add(c);
    }

    final images = <Map<String, dynamic>>[];
    final described = <({String id, String description})>[];
    final imageToPhoto = <String, String>{};
    final photoImageId = <String, String>{};
    for (var i = 0; i < ordered.length; i++) {
      final p = ordered[i];
      final id = 'P${i + 1}';
      photoImageId[p.photoId] = id;
      imageToPhoto[id] = p.photoId;
      images.add(prepared[i].toInlineData());
      final template = ctx.profile.request(p.requestId);
      final quality = p.quality.issues.where((x) => x != 'NONE').toList();
      described.add((
        id: id,
        description: '${p.isInitialPhoto ? 'First photo (whole item)' : p.requestTitle}'
            '${template == null || p.isInitialPhoto ? '' : ' - asked for: ${template.instruction}'}'
            '${p.keptDespiteLowQuality ? ' [kept despite a quality warning]' : ''}'
            '${quality.isEmpty ? '' : ' [photo issues: ${quality.join(', ').toLowerCase()}]'}',
      ));
    }
    for (var i = 0; i < crops.length; i++) {
      final c = crops[i];
      final id = 'C${i + 1}';
      imageToPhoto[id] = c.photoId;
      images.add(c.image.toInlineData());
      described.add((id: id, description: 'close-up of ${photoImageId[c.photoId]} (${c.title}) cut from the full-resolution photo'));
    }

    final claimFor = {
      for (final c in checklist.claims)
        if (c.checkpointId != null) c.checkpointId!: c.id,
    };
    // Differences first, so they are never cut off.
    final prior = [
      ...preliminary.records.where((r) => r.direction == EvidenceDirection.supportsCounterfeit),
      ...preliminary.records.where((r) => r.direction != EvidenceDirection.supportsCounterfeit && r.direction != EvidenceDirection.neutral),
    ];
    final earlier = <String>[
      for (final p in ordered)
        if (p.summary.isNotEmpty) '${photoImageId[p.photoId]} ${p.requestTitle}: ${p.summary}',
      for (final r in prior.take(18))
        '${claimFor[r.featureId] == null ? '' : '[${claimFor[r.featureId]}] '}${photoImageId[r.photoId] ?? r.photoId} ${r.featureName}: ${r.observation} (${switch (r.direction) {
          EvidenceDirection.supportsAuthentic => 'looked consistent',
          EvidenceDirection.supportsCounterfeit => 'looked different',
          _ => 'unclear',
        }})',
    ];

    final claimIds = [for (final c in checklist.claims) ...[c.id, if (c.checkpointId != null) c.checkpointId!]];
    final requestIds = [for (final r in ctx.profile.profile.requests) r.id];
    final analysis = await _call<CombinedAnalysis>(
      // Same label as the engine v3 final call, so the Cloud Function that
      // is deployed today still charges exactly one credit per scan.
      label: 'multi_image_forensic_observations',
      prompt: AuthenticityPrompts.combinedAnalysisPrompt(
        profile: ctx.profile,
        images: described,
        checklist: checklist,
        earlierObservations: earlier,
      ),
      images: images,
      schema: AuthenticityPrompts.combinedAnalysisSchema(
        imageIds: [...imageToPhoto.keys],
        claimIds: claimIds,
        requestIds: requestIds,
      ),
      maxOutputTokens: AuthenticityEngineConfig.finalMaxOutputTokens,
      timeout: AuthenticityEngineConfig.finalTimeout,
      thinkingLevel: AuthenticityEngineConfig.finalThinkingLevel,
      parse: (json) => CombinedAnalysis.parse(
        json,
        imageToPhoto: imageToPhoto,
        claimIds: claimIds.toSet(),
        requestIds: requestIds.toSet(),
      ),
    );
    return (
      analysis: analysis,
      images: <String, dynamic>{
        'preset': preset.name,
        'photos': ordered.length,
        'crops': crops.length,
        'image_kb': (used * 3 / 4 / 1024).round(),
        'manifest': [for (final d in described) '${d.id}: ${d.description}'],
      },
    );
  }

  Future<AuthenticationReport> finalizeReport({
    required ScanContext ctx,
    required List<PhotoEvidence> photos,
    Set<String> skipped = const {},
    Map<String, int> retakeSuggestions = const {},
    String? scanId,
  }) async {
    if (photos.isEmpty) {
      throw AppError.unknown(detail: 'There is no photo to analyse. Capture the item first.');
    }
    final startedAt = DateTime.now();
    final working = List<PhotoEvidence>.from(photos);

    final preliminary = evaluate(ctx, working);
    final EngineResult result;
    final Map<String, dynamic> finalLog;
    final List<String> contradictions;
    final List<String> extraChecks;
    ProductReference? checklist;
    String? geminiReasoning;
    List<String> geminiSummaryPoints = const [];
    if (finalStageMode == FinalStageMode.legacyTextOnly) {
      final finalEval = await finalEvaluation(ctx, working, preliminary);
      result = evaluate(ctx, working, finalEvaluation: finalEval);
      finalLog = {'mode': 'legacy_text_only', ...finalEval.toJson()};
      contradictions = finalEval.contradictions.map((c) => c.description).toList();
      extraChecks = const [];
    } else {
      // No external research: Gemini's own knowledge (in the combined call)
      // plus the app checklist for this product type.
      checklist = ProductReference.checklist(ctx.profile);
      final combined = await combinedAnalysis(ctx, working, checklist, preliminary);
      geminiReasoning = combined.analysis.reasoning;
      geminiSummaryPoints = combined.analysis.summaryPoints;
      result = FinalVerdictValidator.validate(
        profile: ctx.profile,
        photos: working,
        checklist: checklist,
        analysis: combined.analysis,
        preliminary: preliminary,
      );
      finalLog = {'mode': 'combined', 'images': combined.images, ...combined.analysis.toJson()};
      contradictions = combined.analysis.contradictions.map((c) => c.description).toList();
      extraChecks = combined.analysis.independentVerification;
      if (kDebugMode) {
        final byComparison = <String, int>{};
        for (final f in combined.analysis.findings) {
          byComparison[f.comparison] = (byComparison[f.comparison] ?? 0) + 1;
        }
        debugPrint('[FinalStage] scan=$_scanId proposed=${combined.analysis.proposedVerdict} final=${result.verdict.code} '
            'findings=$byComparison images=${combined.images['photos']}+${combined.images['crops']} crops '
            '(${combined.images['image_kb']}KB, ${combined.images['preset']})');
        debugPrint('[VerdictTrace] cid=$_scanId '
            '1_model=${ctx.profile.id} '
            '1_gen=${ctx.profile.generation?.id ?? "none"} '
            '2_photos=${combined.images["photos"]} '
            '3_crops=${combined.images["crops"]} '
            '4_status=success '
            '4_finish_reason=${(finalLog["_meta"] as Map?)?["finishReason"] ?? "STOP"} '
            '5_raw_verdict=${combined.analysis.proposedVerdict} '
            '6_parsed_verdict=${switch (combined.analysis.proposedVerdict) { "AUTHENTIC" => Verdict.likelyAuthentic.code, "REPLICA" => Verdict.likelyReplica.code, _ => Verdict.inconclusive.code }} '
            '7_validated_verdict=${result.verdict.code} '
            '8_app_verdict=${result.verdict.code} '
            '9_ui_verdict=${result.verdict.label}');
        for (final t in result.trace) {
          debugPrint('[FinalStage]   $t');
        }
        for (final g in result.gaps) {
          debugPrint('[FinalStage]   not sure because: ${g.description}');
        }
      }
    }

    final plan = this.plan(ctx, working, result, skipped: skipped, retakeSuggestions: retakeSuggestions);
    final assessment = AssessmentBuilder.build(
      profile: ctx.profile,
      photos: working,
      result: result,
      plan: plan,
      categoryLabel: ctx.product.categoryLabel,
      geminiReasoning: geminiReasoning,
    );
    final violations = assessment.validate();
    assert(violations.isEmpty, 'assessment invariants violated: $violations');

    final product = ctx.product;
    final observedText = {for (final p in working) ...p.observedText}.toList();
    final fingerprint = ScanConsistencyService.fingerprint(
      product,
      analysedModel: [ctx.identity.modelFamily.value, ctx.identity.generation.value].whereType<String>().join(' '),
      observedText: observedText,
    );

    final evidenceItems = [for (var i = 0; i < working.length; i++) _evidenceItemFor(working[i], i + 1, result, ctx.profile)];
    final unclearText = result.unclear
        .where((r) => r.direction == EvidenceDirection.unclear)
        .map((r) => r.displayText)
        .toSet()
        .toList();

    final analysisLog = <String, dynamic>{
      'engine_version': AuthenticityEngineConfig.engineVersion,
      'prompt_version': AuthenticityEngineConfig.promptVersion,
      'timestamp': startedAt.toIso8601String(),
      'duration_ms': DateTime.now().difference(startedAt).inMilliseconds,
      'scan_id': ?scanId,
      'profile': ctx.profile.id,
      'generation_spec': ctx.profile.generation?.id,
      'identity': ctx.identity.toJson(),
      'classification': result.verdict.code,
      'evidence_strength': result.strength.name,
      'sufficient': result.sufficient,
      'decision_trace': result.trace,
      'gaps': result.gaps.map((g) => g.toJson()).toList(),
      'authentic_groups': result.authenticGroups.toList(),
      'hard_to_copy_groups': result.hardToCopyGroups.toList(),
      'counterfeit_groups': result.counterfeitGroups.toList(),
      if (result.diagnostics.isNotEmpty) 'diagnostics': result.diagnostics,
      // Read by ScanConsistencyService.
      'strongCounterfeitCount': result.decisiveCount + (result.counterfeitGroups.length >= 2 ? 1 : 0),
      'flaggedEvidenceIds': {for (final r in result.contradicting) ...r.photoId.split('+')}.toList(),
      'authenticEvidenceIds': {for (final r in result.supporting) r.photoId}.toList(),
      'photos': working.map((p) => p.toJson()).toList(),
      'records': result.records.map((r) => r.toJson()).toList(),
      'final_stage': finalStageMode.name,
      'final_evaluation': finalLog,
      if (checklist != null) 'checklist': checklist.toJson(),
      'correlation_id': _scanId,
      'plan': plan.toJson(),
      if (ctx.ranking != null) 'ai_ranking': ctx.ranking!.toJson(),
      'api_usage': usage.toJson(),
      'assessment_violations': violations,
      'fingerprint': fingerprint,
      'image_count': working.length,
    };
    if (kDebugMode) {
      debugPrint('[AuthEngine] ${jsonEncode({
        'verdict': result.verdict.code,
        'strength': result.strength.name,
        'trace': result.trace,
        'gaps': result.gaps.map((g) => g.type.name).toList(),
        'usage': usage.toJson()..remove('calls'),
      })}');
    }

    // Photo quality from the on-device measurements (focus, exposure, glare,
    // resolution), not from the model.
    final qualityScores = [
      for (final p in working)
        if (p.quality.measuredScore > 0) p.quality.measuredScore else if (p.quality.score > 0) p.quality.score,
    ];
    return AuthenticationReport(
      id: 'rep_${DateTime.now().millisecondsSinceEpoch}',
      product: product,
      verdict: result.verdict,
      // Engine v3 produces no numeric confidence (never calibrated).
      overallScore: 0,
      // How completely the item was identified (brand, model, generation
      // and their certainty), not the model's self-reported confidence.
      identificationConfidence: identificationCompleteness(ctx.identity, hasGenerations: ctx.profile.profile.hasGenerations),
      authenticationConfidence: 0,
      evidenceCoverageText: '${working.length} photo${working.length == 1 ? '' : 's'} used',
      coveredEvidenceCount: working.length,
      totalEvidenceCount: working.length,
      quickSummaryPoints: () {
        if (geminiSummaryPoints.isNotEmpty) {
          return geminiSummaryPoints.take(3).toList();
        }
        if (geminiReasoning != null && geminiReasoning.trim().isNotEmpty) {
          final sentences = geminiReasoning
              .split(RegExp(r'(?<=[.!?])\s+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty && s.length > 5)
              .take(3)
              .toList();
          if (sentences.isNotEmpty) return sentences;
        }
        return [
          ...switch (result.verdict) {
            Verdict.likelyReplica => result.contradicting.take(3).map((r) => r.displayText),
            Verdict.likelyAuthentic => result.supporting.take(3).map((r) => r.displayText),
            Verdict.inconclusive => [
                if (result.gaps.isNotEmpty) result.gaps.first.description,
                if (plan.recommended != null) 'Next photo: ${plan.recommended!.template.title}',
              ],
          },
        ];
      }(),
      positiveFindings: result.supporting.map((r) => r.displayText).toList(),
      suspiciousFindings: result.contradicting.map((r) => r.displayText).toList(),
      unclearFindings: unclearText,
      missingEvidence: [
        for (final id in skipped)
          if (ctx.profile.request(id) != null) "${ctx.profile.request(id)!.title} — you skipped this",
      ],
      contradictions: contradictions,
      nextChecks: [...assessment.recommendedNextSteps, ...extraChecks],
      physicalChecks: [
        for (final c in ctx.profile.profile.checkpoints.where((c) => c.hardToCopy).take(4))
          PhysicalCheck(title: c.name, description: c.check, whatToLookFor: c.genuine ?? c.check),
      ],
      evidenceItems: evidenceItems,
      // What the result was checked against, in the existing text field.
      rationale: checklist == null ? assessment.explanation : '${assessment.explanation} ${ProductReference.basisSentence}'.trim(),
      timestamp: DateTime.now(),
      isFavorite: false,
      imageQualityScore: qualityScores.isEmpty ? 0 : (qualityScores.reduce((a, b) => a + b) / qualityScores.length).round(),
      // Share of the checked details the analysis could judge clearly. Not
      // a probability that the verdict is right.
      analysisConfidence: judgedShare(result.records),
      needsMoreImages: !result.sufficient,
      recommendedViews: [
        if (assessment.recommendedNextPhoto != null)
          '${assessment.recommendedNextPhoto!.title}: ${assessment.recommendedNextPhoto!.instruction}'
        else if (plan.recommended != null)
          '${plan.recommended!.template.title}: ${plan.recommended!.reason}',
      ],
      limitations: assessment.remainingUncertainty,
      observedText: observedText,
      fingerprint: fingerprint,
      engineVersion: AuthenticityEngineConfig.engineVersion,
      promptVersion: AuthenticityEngineConfig.promptVersion,
      analysisLog: analysisLog,
      assessment: assessment,
      evidenceStrength: result.strength.name,
    );
  }

  /// 0-100: how completely the item is identified. Brand, model and (for
  /// products with generations) generation, each full when CONFIRMED and
  /// part when PROBABLE.
  static int identificationCompleteness(ProductIdentity id, {required bool hasGenerations}) {
    int part(IdentityAttribute a, int full) => switch (a.status) {
          AttributeStatus.confirmed => full,
          AttributeStatus.probable => full ~/ 2,
          _ => 0,
        };
    final got = part(id.brand, 40) + part(id.modelFamily, 35) + (hasGenerations ? part(id.generation, 25) : 0);
    final max = 75 + (hasGenerations ? 25 : 0);
    return (got * 100 / max).round();
  }

  /// 0-100: share of the checked details (one per feature and part) that
  /// were judged clearly, i.e. matched or differed with at least medium
  /// reliability. 0 when nothing was checked.
  static int judgedShare(Iterable<EvidenceRecord> records) {
    final byFeature = <String, EvidenceRecord>{};
    for (final r in records) {
      if (r.direction == EvidenceDirection.neutral) continue;
      byFeature.putIfAbsent('${r.featureId}|${r.group}', () => r);
    }
    if (byFeature.isEmpty) return 0;
    final judged = byFeature.values
        .where((r) =>
            (r.direction == EvidenceDirection.supportsAuthentic || r.direction == EvidenceDirection.supportsCounterfeit) &&
            r.reliability.atLeast(Reliability.medium))
        .length;
    return (judged * 100 / byFeature.length).round();
  }

  static EvidenceItem _evidenceItemFor(PhotoEvidence p, int index, EngineResult result, ResolvedProfile profile) {
    final records = result.records.where((r) => r.photoId == p.photoId).toList();
    final consistent = records.where((r) => r.direction == EvidenceDirection.supportsAuthentic).map((r) => r.displayText).toList();
    final inconsistent = records.where((r) => r.direction == EvidenceDirection.supportsCounterfeit).map((r) => r.displayText).toList();
    final uncertain = records
        .where((r) => r.direction == EvidenceDirection.unclear || r.direction == EvidenceDirection.neutral)
        .map((r) => r.direction == EvidenceDirection.neutral ? '${r.displayText} (design match only)' : r.displayText)
        .toList();
    final status = inconsistent.isNotEmpty
        ? EvidenceStatus.suspicious
        : consistent.isNotEmpty
            ? EvidenceStatus.consistent
            : EvidenceStatus.inconclusive;
    final template = profile.request(p.requestId);
    return EvidenceItem(
      id: p.photoId,
      index: index,
      title: p.requestTitle,
      guide: template?.instruction ?? '',
      reason: template?.why ?? '',
      weight: EvidenceWeight.high,
      capturedImagePath: p.imagePath,
      status: status,
      keptDespiteLowQuality: p.keptDespiteLowQuality,
      observations: [if (p.summary.isNotEmpty) p.summary],
      consistentSignals: consistent,
      inconsistentSignals: inconsistent,
      uncertainSignals: uncertain,
      guideType: template?.guide ?? CaptureGuideType.generic,
      checkpointIds: template?.checkpointIds ?? const [],
      clarity: judgedShare(records),
    );
  }

  /// Builds the list of photo requests shown to the user, in plan order.
  static List<EvidenceItem> requestItems(ScanContext ctx, EvidencePlan plan, List<PhotoEvidence> photos, Set<String> skipped) {
    // The first (identification) photo still counts as evidence, but it
    // never fills a checklist item: every item starts empty.
    final byRequest = {for (final p in photos) if (!p.isInitialPhoto) p.requestId: p};
    final ordered = <PhotoRequestTemplate>[
      ...plan.ranked.where((r) => !r.isRetake).map((r) => r.template),
      ...ctx.profile.profile.requests.where((t) => !plan.ranked.any((r) => r.id == t.id && !r.isRetake)),
    ];
    final items = <EvidenceItem>[];
    for (final t in ordered) {
      final planned = plan.ranked.where((r) => r.id == t.id && !r.isRetake).firstOrNull;
      final photo = byRequest[t.id];
      final value = planned?.discriminativeValue ?? EvidencePlanner.derivedValue(ctx.profile, t);
      items.add(EvidenceItem(
        id: t.id,
        index: items.length + 1,
        title: t.title,
        guide: t.instruction,
        reason: t.why,
        isRequired: false,
        weight: switch (value) {
          'HIGH' => EvidenceWeight.critical,
          'LOW' => EvidenceWeight.low,
          _ => EvidenceWeight.medium,
        },
        capturedImagePath: photo?.imagePath ?? '',
        status: photo != null
            ? EvidenceStatus.captured
            : skipped.contains(t.id)
                ? EvidenceStatus.unavailable
                : EvidenceStatus.pending,
        guideType: t.guide,
        tips: t.tips,
        checkpointIds: t.checkpointIds,
        discriminativeValue: value,
        recommendationReason: planned?.reason ?? t.why,
        aiChecks: planned?.aiChecks ?? const [],
        screenshotOk: t.screenshotOk,
        observations: [if (photo != null && photo.summary.isNotEmpty) photo.summary],
      ));
    }
    return items;
  }
}
