import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/config/authenticity_engine_config.dart';
import '../core/errors/app_error.dart';
import '../data/authentication_rules.dart';
import '../data/reference_library.dart';
import '../models/authentication_result.dart';
import '../models/evidence.dart';
import '../models/evidence_observation.dart';
import '../models/evidence_validation.dart';
import '../models/product.dart';
import '../models/product_identification.dart';
import '../models/evidence_finding.dart';
import '../services/authentication_scoring_engine.dart';
import '../services/authenticity_prompts.dart';
import '../services/gemini_service.dart';
import '../services/image_preparation_service.dart';
import '../services/image_quality_checker.dart';
import '../services/scan_consistency_service.dart';

/// Real inference pipeline. Every value it returns originates in a model
/// response or the local scoring engine — there is no synthetic fallback, so a
/// failed call surfaces as an error rather than a fabricated result (§46).
class GeminiAuthenticationRepository {
  final GeminiService _geminiService;
  final ImagePreparationService _imagePrep;

  /// Per-scan caches so returning to a screen never re-bills a request (§3, §45).
  final Map<String, ProductIdentification> _identificationCache = {};
  final Map<String, List<EvidenceItem>> _evidencePlanCache = {};

  GeminiAuthenticationRepository({
    GeminiService? geminiService,
    ImagePreparationService? imagePrep,
  })  : _geminiService = geminiService ?? GeminiService(),
        _imagePrep = imagePrep ?? ImagePreparationService();

  ImagePreparationService get imagePrep => _imagePrep;

  void clearScanCaches() {
    _identificationCache.clear();
    _evidencePlanCache.clear();
  }

  // ---------------------------------------------------------------------------
  // Step 1 — Identification & Visual Validation Stage
  // ---------------------------------------------------------------------------

  Future<ProductIdentification> identifyProduct(String imagePathOrAsset) async {
    final cached = _identificationCache[imagePathOrAsset];
    if (cached != null) {
      if (kDebugMode) debugPrint('[Auth] identification served from scan cache');
      return cached;
    }

    final prepared = await _imagePrep.prepareImage(
      imagePathOrAsset,
      preset: ImagePreset.identification,
    );

    final response = await _geminiService.generateStructuredContent(
      prompt: AuthenticityPrompts.identificationPrompt,
      inlineImages: [prepared.toInlineData()],
      requestTypeLabel: 'product_identification_and_validation',
      maxOutputTokens: 700,
      timeout: const Duration(seconds: 30),
      responseSchema: AuthenticityPrompts.identificationSchema,
    );

    final identification = ProductIdentification.fromJson(response);
    _identificationCache[imagePathOrAsset] = identification;
    return identification;
  }

  // ---------------------------------------------------------------------------
  // Step 2 — Evidence plan: 5-6 product-specific angles with weights
  // ---------------------------------------------------------------------------

  /// The capture checklist for this product.
  ///
  /// Deterministic on purpose: it comes from the category/model rule set,
  /// not from a fresh Gemini call. Engine v1 asked Gemini for a new plan on
  /// every scan, so two scans of the same item were judged against
  /// different "critical" angles, which is one of the reasons results
  /// flipped between scans.
  Future<List<EvidenceItem>> getRequiredEvidence(Product product) async {
    final cacheKey = '${product.id}|${product.brand}|${product.name}';
    final cached = _evidencePlanCache[cacheKey];
    if (cached != null) return cached;

    final rules = AuthenticationRules.resolve(
      category: product.category,
      brand: product.brand,
      model: product.model,
      name: product.name,
    );
    final items = rules.evidenceBlueprint
        .asMap()
        .entries
        .map((e) => e.value.toEvidenceItem(e.key + 1))
        .toList();

    final normalized = _normalizePlan(items, rules);
    _evidencePlanCache[cacheKey] = normalized;
    return normalized;
  }

  /// Words that mean nothing to a normal user. A title containing one of these
  /// is replaced with the plain-English blueprint wording (§1).
  static const _jargon = [
    'reference area', 'production identifier', 'construction', 'geometry',
    'typography', 'manufacturing marker', 'authentication', 'evidence',
    'component relationship', 'characteristic', 'identifier', 'analysis',
    'consistency', 'verification',
  ];

  static bool _isPlainTitle(String title) {
    final t = title.toLowerCase();
    if (t.split(RegExp(r'\s+')).length > 4) return false;
    return !_jargon.any(t.contains);
  }

  /// Caps the plan at 4-6 entries, guarantees at least two critical angles and
  /// stops packaging from ever outranking identity evidence.
  static List<EvidenceItem> _normalizePlan(
    List<EvidenceItem> items,
    AuthenticationRuleSet rules,
  ) {
    if (items.isEmpty) return items;

    var working = items.map((item) {
      // Trust the blueprint's weight over an AI-assigned one where the id is known.
      final blueprintWeight = rules.weightFor(item.id);
      final weight = item.weight == EvidenceWeight.medium ? blueprintWeight : item.weight;
      return item.copyWith(
        weight: weight,
        isRequired: weight == EvidenceWeight.critical || weight == EvidenceWeight.high,
      );
    }).toList();

    if (working.length > 6) working = working.sublist(0, 6);

    // Last line of defence: if the model still returns jargon, fall back to
    // the plain-English blueprint title for that id (§1, §11).
    working = working.map((item) {
      if (!_isPlainTitle(item.title)) {
        final match = rules.evidenceBlueprint
            .where((b) => b.id.toLowerCase() == item.id.toLowerCase())
            .toList();
        if (match.isNotEmpty) {
          return item.copyWith(title: match.first.title, guide: match.first.guide, reason: match.first.why);
        }
      }
      return item;
    }).toList();

    // Ensure at least two critical angles exist, promoting the strongest first.
    var criticalCount = working.where((e) => e.isCritical).length;
    if (criticalCount < 2) {
      for (int i = 0; i < working.length && criticalCount < 2; i++) {
        if (working[i].weight == EvidenceWeight.high) {
          working[i] = working[i].copyWith(weight: EvidenceWeight.critical, isRequired: true);
          criticalCount++;
        }
      }
    }

    // At most one low-weight (packaging-style) angle.
    var lowSeen = 0;
    for (int i = 0; i < working.length; i++) {
      if (working[i].weight == EvidenceWeight.low) {
        lowSeen++;
        if (lowSeen > 1) {
          working[i] = working[i].copyWith(weight: EvidenceWeight.medium);
        }
      }
    }

    return [
      for (int i = 0; i < working.length; i++) working[i].copyWith(index: i + 1),
    ];
  }

  // ---------------------------------------------------------------------------
  // Step 3 — Per-photo validation: is this the requested area, and is it usable?
  // ---------------------------------------------------------------------------

  /// One call per submitted photo. Returns evidence-type detection, technical
  /// quality and authentication usefulness together (§7, §8, §10, §12).
  ///
  /// The model is never told what the user claims the photo is beyond the
  /// requested angle, and the filename is never sent (§9).
  Future<EvidenceValidationResult> validateEvidencePhoto({
    required String imagePathOrAsset,
    required EvidenceItem requestedItem,
    required Product product,
  }) async {
    final prepared = await _imagePrep.prepareImage(
      imagePathOrAsset,
      preset: ImagePreset.validation,
    );

    final otherAngles = requestedItem.reason.isNotEmpty ? '\nWhy it is needed: ${requestedItem.reason}' : '';

    final prompt = '''You are checking whether a submitted photo shows the specific area that was requested.

Item: ${product.brand} ${product.name} (${product.category.label}).
REQUESTED AREA: "${requestedItem.title}"
Capture instruction given to the user: "${requestedItem.guide}"$otherAngles

Judge ONLY from the image. Ignore any assumption about what the user intended to photograph.

1. Name the part/area actually visible in "evidence_type_detected" (e.g. "crown", "caseback", "box label", "unrelated object").
2. Set "match_to_requested_evidence" true ONLY if the requested area is genuinely visible and large enough to inspect.
   Set "match_confidence" (0-100) to how strongly the photo shows the REQUESTED area specifically - this is NOT your confidence in identifying what the photo shows. If "match_to_requested_evidence" is false, "match_confidence" MUST be low (under 20), even if you are completely sure what the wrong part is.
3. Score the IMAGE quality independently of what it shows.
4. Score "authentication_usefulness": how much this image helps authenticate the REQUESTED area. If the requested area is not shown, this MUST be 0.

A technically perfect photo of the wrong part scores high quality and zero usefulness.

WORDING: "reason" must be ONE short everyday sentence a normal person understands, e.g. "Clear photo with good lighting." or "The logo is too far away to see."
"issues" must be short plain phrases such as "Too dark", "Too blurry", "Move a little closer", "Too much glare", "Keep the whole item in frame".
Never use words like entropy, segmentation, resolution, artefact, feature extraction or evidence type.

JSON only:
{"evidence_type_detected":"","match_to_requested_evidence":true,"match_confidence":0,"photo_quality_score":0,"quality_status":"EXCELLENT|GOOD|NEEDS_IMPROVEMENT|POOR","sharpness":0,"lighting":0,"framing":0,"detail":0,"usability_score":0,"authentication_usefulness":0,"reason":"one short sentence","issues":[""]}''';

    final response = await _geminiService.generateStructuredContent(
      prompt: prompt,
      inlineImages: [prepared.toInlineData()],
      requestTypeLabel: 'evidence_validation:${requestedItem.id}',
      maxOutputTokens: 600,
      timeout: const Duration(seconds: 30),
    );

    return EvidenceValidationResult.fromJson(
      response,
      requestedEvidenceId: requestedItem.id,
      requestedEvidenceTitle: requestedItem.title,
    );
  }

  // ---------------------------------------------------------------------------
  // Step 4 — Final analysis: every accepted image in ONE request
  // ---------------------------------------------------------------------------

  Future<AuthenticationReport> finalizeReport({
    required Product product,
    required List<EvidenceItem> evidenceItems,
    required Map<String, String> capturedImages,
    String? overviewImagePath,
    int identificationConfidence = 0,
    String? scanId,
  }) async {
    final startedAt = DateTime.now();
    final rules = AuthenticationRules.resolve(
      category: product.category,
      brand: product.brand,
      model: product.model,
      name: product.name,
    );
    final ref = ReferenceLibrary.findReference(product.brand, product.name);

    final imageParts = <Map<String, dynamic>>[];
    final imageManifest = StringBuffer();
    final missingList = <EvidenceItem>[];
    final localQuality = <int>[];
    final localQualityById = <String, int>{};

    int imageIndex = 1;
    for (final item in evidenceItems) {
      final path = capturedImages[item.id];
      if (path == null || path.isEmpty) {
        missingList.add(item);
        continue;
      }
      final prep = await _imagePrep.prepareImage(path, preset: ImagePreset.evidence);
      imageParts.add(prep.toInlineData());
      imageManifest.writeln(
        'IMAGE $imageIndex -> evidence_id "${item.id}" (${item.title}, importance: ${item.weight.label})',
      );
      final q = await ImageQualityChecker.evaluate(path);
      if (q.qualityScore > 0) {
        localQuality.add(q.qualityScore);
        localQualityById[item.id] = q.qualityScore;
      }
      imageIndex++;
    }

    // The user supplied none of the requested angles. Rather than blocking
    // them, analyse the original identification photo on its own. It is not
    // credited to any requested angle, so evidence coverage stays at zero.
    var overviewOnly = false;
    if (imageParts.isEmpty) {
      if (overviewImagePath == null || overviewImagePath.isEmpty) {
        throw AppError.unknown(
          detail: 'There is no photo to analyse. Capture the item first.',
        );
      }
      final prep = await _imagePrep.prepareImage(overviewImagePath, preset: ImagePreset.evidence);
      imageParts.add(prep.toInlineData());
      imageManifest.writeln(
        'IMAGE 1 -> evidence_id "overview" (the original identification photo; '
        'it was NOT captured against any requested angle)',
      );
      final q = await ImageQualityChecker.evaluate(overviewImagePath);
      if (q.qualityScore > 0) localQuality.add(q.qualityScore);
      overviewOnly = true;
    }

    final missingNote = missingList.isEmpty
        ? 'None - all requested photos were supplied.'
        : missingList
            .map((m) => '- ${m.title} (${m.weight.label}${m.isUnavailable ? ', user does not have it' : ', not supplied'})')
            .join('\n');

    final prompt = AuthenticityPrompts.forensicAnalysisPrompt(
      product: product,
      rules: rules,
      imageManifest: imageManifest.toString(),
      missingNote: missingNote,
      overviewOnly: overviewOnly,
      reference: ref,
    );

    // A failure here is surfaced, never replaced with invented observations.
    final response = await _geminiService.generateStructuredContent(
      prompt: prompt,
      inlineImages: imageParts,
      requestTypeLabel: 'multi_image_forensic_observations',
      maxOutputTokens: 8192,
      timeout: const Duration(seconds: 90),
      responseSchema: AuthenticityPrompts.forensicAnalysisSchema,
    );

    final analysis = GeminiEvidenceResponse.fromJson(response);
    if (analysis.partObservations.isEmpty) {
      throw AppError.invalidResponse();
    }

    ScoringEngineResult score({
      Map<String, VerificationResult> verifications = const {},
      bool? verificationSufficient,
    }) =>
        AuthenticationScoringEngine.evaluate(
          product: product,
          rawIdentificationConfidence: identificationConfidence,
          requiredEvidence: evidenceItems,
          capturedImages: capturedImages,
          observations: analysis.partObservations,
          contradictions: analysis.contradictions,
          rules: rules,
          reference: ref,
          hasModelReference: ref != null,
          analysis: analysis,
          localQualityScores: localQuality,
          verifications: verifications,
          verificationSufficient: verificationSufficient,
        );

    var result = score();

    // Contradiction check (§26-27): before "Likely Replica" is ever shown,
    // a second, independent pass challenges each counterfeit finding.
    Map<String, dynamic>? verificationLog;
    if (result.verdict == Verdict.likelyReplica && result.counterfeitFindingsToVerify.isNotEmpty) {
      final toVerify = result.counterfeitFindingsToVerify;
      try {
        final vResponse = await _geminiService.generateStructuredContent(
          prompt: AuthenticityPrompts.verificationPrompt(
            product: product,
            counterfeitFindings: toVerify,
            imageManifest: imageManifest.toString(),
            rules: rules,
          ),
          inlineImages: imageParts,
          requestTypeLabel: 'counterfeit_verification',
          maxOutputTokens: 2048,
          timeout: const Duration(seconds: 60),
          responseSchema: AuthenticityPrompts.verificationSchema,
        );
        final verifications = <String, VerificationResult>{};
        for (final v in (vResponse['verifications'] as List? ?? const []).whereType<Map>()) {
          final idx = (v['finding_index'] as num?)?.toInt();
          if (idx == null || idx < 0 || idx >= toVerify.length) continue;
          final f = toVerify[idx];
          verifications[AuthenticationScoringEngine.findingKey(f.evidenceId, f)] = VerificationResult(
            outcome: VerificationOutcome.parse(v['outcome'] as String?),
            strength: FindingStrength.parse(v['verified_strength'] as String?),
            reason: (v['reason'] as String? ?? '').trim(),
          );
        }
        final sufficient = vResponse['sufficient_evidence_for_counterfeit'] == true;
        result = score(verifications: verifications, verificationSufficient: sufficient);
        verificationLog = {
          'sufficient': sufficient,
          // A list, not a map: the keys contain free text, which is fragile
          // as Firestore map keys.
          'results': [for (final e in verifications.entries) {'finding': e.key, ...e.value.toJson()}],
          'verdictAfter': result.verdict.code,
          'model': (vResponse['_meta'] as Map?)?['model'],
        };
      } catch (e) {
        // No verification, no replica verdict: an unchallenged counterfeit
        // call is exactly the false positive this pass exists to prevent.
        result = score(verificationSufficient: false);
        verificationLog = {'error': e.toString(), 'verdictAfter': result.verdict.code};
      }
    }

    final fingerprint = ScanConsistencyService.fingerprint(
      product,
      analysedModel: analysis.model,
      observedText: analysis.observedText,
    );

    final analysisLog = _buildAnalysisLog(
      scanId: scanId,
      startedAt: startedAt,
      product: product,
      rules: rules,
      analysis: analysis,
      result: result,
      rawResponse: response,
      localQualityById: localQualityById,
      verificationLog: verificationLog,
      fingerprint: fingerprint,
      imageCount: imageParts.length,
    );
    if (kDebugMode) {
      debugPrint('[AuthEngine] ${jsonEncode({...analysisLog, 'raw_response': '<omitted>'})}');
    }

    return AuthenticationReport(
      id: 'rep_${DateTime.now().millisecondsSinceEpoch}',
      product: product,
      verdict: result.verdict,
      overallScore: result.authenticationConfidence,
      identificationConfidence: result.identificationConfidence,
      authenticationConfidence: result.authenticationConfidence,
      evidenceCoverageText: result.evidenceCoverageText,
      coveredEvidenceCount: result.coveredCount,
      totalEvidenceCount: result.totalCount,
      quickSummaryPoints: result.quickSummaryPoints,
      positiveFindings: result.positiveFindings,
      suspiciousFindings: result.suspiciousFindings,
      unclearFindings: result.unclearFindings,
      missingEvidence: result.missingEvidenceDescriptions,
      contradictions: result.contradictionDescriptions,
      nextChecks: result.nextChecks,
      physicalChecks: analysis.physicalChecks
          .map((c) => PhysicalCheck(
                title: c['title'] ?? '',
                description: c['description'] ?? '',
                whatToLookFor: c['what_to_look_for'] ?? '',
              ))
          .toList(),
      evidenceItems: result.scoredEvidenceItems,
      rationale: result.rationale,
      timestamp: DateTime.now(),
      isFavorite: false,
      imageQualityScore: result.imageQualityScore,
      analysisConfidence: result.analysisConfidence,
      needsMoreImages: result.needsMoreImages,
      recommendedViews: result.recommendedViews,
      limitations: result.limitations,
      observedText: analysis.observedText,
      fingerprint: fingerprint,
      engineVersion: AuthenticityEngineConfig.engineVersion,
      promptVersion: AuthenticityEngineConfig.promptVersion,
      analysisLog: analysisLog,
    );
  }

  /// Everything needed to explain a result later (§34), and nothing about
  /// the user: no name, email, uid, image data or file paths.
  static Map<String, dynamic> _buildAnalysisLog({
    required String? scanId,
    required DateTime startedAt,
    required Product product,
    required AuthenticationRuleSet rules,
    required GeminiEvidenceResponse analysis,
    required ScoringEngineResult result,
    required Map<String, dynamic> rawResponse,
    required Map<String, int> localQualityById,
    required Map<String, dynamic>? verificationLog,
    required String fingerprint,
    required int imageCount,
  }) {
    var raw = jsonEncode(rawResponse);
    if (raw.length > 20000) raw = '${raw.substring(0, 20000)}...<truncated>';
    final findings = result.normalizedFindings;
    return {
      'engine_version': AuthenticityEngineConfig.engineVersion,
      'prompt_version': AuthenticityEngineConfig.promptVersion,
      'timestamp': startedAt.toIso8601String(),
      'duration_ms': DateTime.now().difference(startedAt).inMilliseconds,
      'scan_id': ?scanId,
      'gemini_model': (rawResponse['_meta'] as Map?)?['model'],
      'schema_enforced': (rawResponse['_meta'] as Map?)?['schemaEnforced'] ?? false,
      'inspection_profile': rules.profileName,
      'category': product.categoryCode ?? product.category.name,
      'detected_category': analysis.categoryCode,
      'brand': product.brand,
      'detected_brand': analysis.brand,
      'model': product.model,
      'detected_model': analysis.model,
      'model_confidence': analysis.modelConfidence,
      'model_confirmed': analysis.modelConfirmed,
      'fingerprint': fingerprint,
      'image_count': imageCount,
      'image_quality': result.imageQualityScore,
      'gemini_image_quality': analysis.imageQualityScore,
      'image_quality_issues': analysis.imageQualityIssues,
      'local_image_quality': localQualityById,
      'classification': result.verdict.code,
      'model_classification': analysis.modelClassification,
      'authenticity_confidence': result.authenticationConfidence,
      'analysis_confidence': result.analysisConfidence,
      'identification_confidence': result.identificationConfidence,
      'authentic_points': result.authenticPoints,
      'counterfeit_points': result.counterfeitPoints,
      'strongCounterfeitCount': result.strongCounterfeitCount,
      'flaggedEvidenceIds': {
        for (final f in findings.where((f) => f.isCounterfeit && f.strength != FindingStrength.weak)) f.evidenceId,
      }.toList(),
      'authenticEvidenceIds': {
        for (final f in findings.where((f) => f.isAuthentic && f.strength != FindingStrength.weak)) f.evidenceId,
      }.toList(),
      'contradiction_check': analysis.contradictionCheck.toJson(),
      'decision_trace': result.decisionTrace,
      'evidence': findings.map((f) => f.toJson()).toList(),
      'missing_evidence': findings.where((f) => f.type == FindingType.missing).map((f) => f.toJson()).toList(),
      'verification': ?verificationLog,
      'raw_response': raw,
    };
  }
}
