import 'package:flutter/foundation.dart';
import '../core/errors/app_error.dart';
import '../data/authentication_rules.dart';
import '../data/reference_library.dart';
import '../models/authentication_result.dart';
import '../models/evidence.dart';
import '../models/evidence_observation.dart';
import '../models/evidence_plan.dart';
import '../models/evidence_validation.dart';
import '../models/product.dart';
import '../models/product_identification.dart';
import '../services/authentication_scoring_engine.dart';
import '../services/gemini_service.dart';
import '../services/image_preparation_service.dart';

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

    const prompt = '''You are a strict luxury product presence validator and identifier for an authentication system.
Before attempting to identify any brand or product, perform an IMAGE VALIDATION & PRODUCT PRESENCE evaluation.

IMAGE VALIDATION RULES:
1. USABILITY & BRIGHTNESS:
   - If the photo is pitch black, extremely dark, or has insufficient lighting:
     status="unusable_image", reason="image_too_dark", product_detected=false.
     message="Image is too dark to analyze. Please move to a brighter area and scan the item again."
   - If the photo is completely blank, solid color, empty wall, or has no visible object:
     status="unusable_image", reason="no_visible_content", product_detected=false.
     message="No visible item detected. Please point the camera at a product and try again."
   - If the photo is heavily blurred, out of focus, or obstructed:
     status="unusable_image", reason="insufficient_visual_quality", product_detected=false.
     message="The image isn't clear enough to analyze. Please capture a sharper photo with the item fully visible."

2. HUMAN DETECTION:
   - If the photo primarily contains a person, human face, selfie, body, hands, or outfit without an obvious luxury product being inspected:
     status="not_product", reason="human_detected", product_detected=false.
     message="Please scan a luxury item such as a handbag, watch, shoe, wallet, jewelry, or other supported product."
     DO NOT guess or invent a product or brand for a human.

3. IRRELEVANT OBJECTS:
   - If the photo depicts food, drinks, furniture, wall, floor, animal, pet, vehicle, landscape, scenery, random electronics (computer monitor, keyboard, cable), or general household clutter:
     status="not_product", reason="unsupported_object", product_detected=false.
     message="No supported luxury item detected. Please scan a supported product."
     DO NOT invent a luxury brand or classify random objects as luxury goods.

4. PARTIAL / INSUFFICIENT EVIDENCE:
   - If a product appears to be present but is heavily cropped, mostly hidden, or too distant to identify:
     status="insufficient_evidence", reason="partial_product_insufficient_evidence", product_detected=false.
     message="There isn't enough visible detail to reliably determine the item. Please capture a clearer full-view photo."

5. VALID SUPPORTED LUXURY PRODUCT:
   - ONLY when an actual physical luxury product (e.g. Handbag, Watch, Sneakers/Shoes, Clothing, Wallet, Belt, Jewelry, Sunglasses/Eyewear, Perfume) is clearly visible and centered:
     status="product_detected", reason="valid_luxury_product", product_detected=true.
     Identify product_category (e.g. "Bags", "Watches", "Sneakers", "Clothing", "Accessories", "Jewelry").
     Identify brand ONLY if visible or distinctive (e.g. "Louis Vuitton", "Rolex", "Nike", "Gucci", "Hermes"). If not identifiable, set brand="not_identifiable".
     Identify product_name and model ONLY if clearly recognizable. NEVER hallucinate details.
     confidence: realistic 0.0 to 0.99.
     IMPORTANT: this app's entire purpose is checking whether an item is a genuine luxury product or a replica/fake - so many scanned items will legitimately look plain, unbranded, low-quality, or otherwise NOT obviously "luxury" at a glance (that uncertainty is exactly what the user is trying to resolve). Classify by OBJECT TYPE, not by how expensive or authentic it looks: if the object is clearly a watch (any analog/digital watch with a case, dial and strap/band - branded or not, plain or ornate, blurry logo or no logo, glare on the dial, worn on a wrist or on a surface), that is a valid product_category="Watches" with product_detected=true, even if you cannot tell the brand, cannot tell if it's genuine, or it doesn't look expensive. The same applies to bags, sneakers, wallets, belts, jewelry, eyewear, and perfume - do not reject an item just because it looks like it could be fake, generic, or low-value. Only use "not_product"/"unsupported_object" for things that are not one of these product types at all (e.g. furniture, food, a wall).

CRITICAL INVARIANTS:
- If product_detected is false:
  brand MUST be null
  model MUST be null
  product_name MUST be null
  product_category MUST be null
- NEVER output "Unknown Luxury Item". Output status "not_product" or "unusable_image" instead.

OUTPUT RFC-8259 JSON ONLY:
{
  "status": "product_detected | not_product | unusable_image | insufficient_evidence",
  "reason": "human_detected | unsupported_object | image_too_dark | no_visible_content | insufficient_visual_quality | partial_product_insufficient_evidence | valid_luxury_product",
  "product_detected": true,
  "product_category": "Category Name or null",
  "brand": "Brand Name or null",
  "product_name": "Product Name or null",
  "model": "Model or null",
  "confidence": 0.92,
  "visible_details": ["feature 1", "feature 2"],
  "missing_evidence": ["missing angle"],
  "message": "User-facing summary"
}''';

    final response = await _geminiService.generateStructuredContent(
      prompt: prompt,
      inlineImages: [prepared.toInlineData()],
      requestTypeLabel: 'product_identification_and_validation',
      maxOutputTokens: 600,
      timeout: const Duration(seconds: 30),
    );

    final identification = ProductIdentification.fromJson(response);
    _identificationCache[imagePathOrAsset] = identification;
    return identification;
  }

  // ---------------------------------------------------------------------------
  // Step 2 — Evidence plan: 5-6 product-specific angles with weights
  // ---------------------------------------------------------------------------

  Future<List<EvidenceItem>> getRequiredEvidence(Product product) async {
    final cacheKey = '${product.id}|${product.brand}|${product.name}';
    final cached = _evidencePlanCache[cacheKey];
    if (cached != null) {
      if (kDebugMode) debugPrint('[Auth] evidence plan served from scan cache');
      return cached;
    }

    final rules = AuthenticationRules.resolve(
      category: product.category,
      brand: product.brand,
      model: product.model,
    );
    final ref = ReferenceLibrary.findReference(product.brand, product.name);

    final referenceHint = ref != null
        ? '\nKnown checkpoints for this model:\n${ref.features.map((f) => '- ${f.title}: ${f.expectedDetail}').join('\n')}'
        : '';

    final prompt = '''Item: ${product.brand} ${product.name}${product.model.isNotEmpty ? ' (${product.model})' : ''} - ${product.category.label}.

Choose the smallest practical set of clear, easy-to-understand photo requests that give strong evidence for THIS specific product. Return 5 or 6.
$referenceHint

WRITE FOR A NORMAL PERSON, NOT AN AUTHENTICATOR:
- "title": 1-3 everyday words naming a physical part. The user must understand it without reading anything else.
  Good: Full Item, Logo, Tag, Inside, Back, Bottom, Front, Side, Sole, Stitching, Clasp, Zipper, Dial, Crown, Engraving, Number, Box Label.
  Never: reference area, production identifier, construction detail, hardware geometry, typography, manufacturing marker, authentication evidence.
- "guide": ONE short sentence telling them what to do, e.g. "Take a close-up of the small knob on the side."
- "why": ONE short sentence, e.g. "We'll check its shape and details." No authentication theory.

Ask for one photo per physical area, not one per detail: request "Logo" once rather than logo spacing, logo font and logo placement separately.

Assign a weight (this is internal, the user never sees it):
- "critical": identity evidence (serial or model number, main logo, dial, size or neck tag)
- "high": strong build or shape evidence
- "medium": supporting detail
- "low": box, papers or packaging (never decisive)

Include 2-3 critical items. At most one "low".

JSON only:
{"requiredEvidence":[{"id":"snake_case_internal_id","title":"Short Title","guide":"One short sentence.","reason":"One short sentence.","weight":"critical|high|medium|low"}]}''';

    List<EvidenceItem> items;
    try {
      final response = await _geminiService.generateStructuredContent(
        prompt: prompt,
        requestTypeLabel: 'evidence_plan',
        maxOutputTokens: 1400,
        timeout: const Duration(seconds: 35),
      );

      final plan = EvidencePlan.fromJson(response);
      items = <EvidenceItem>[];
      for (int i = 0; i < plan.requiredEvidence.length; i++) {
        items.add(plan.requiredEvidence[i].toEvidenceItem(index: i + 1));
      }
    } catch (e) {
      // The plan is a capture checklist, not a result. Falling back to the local
      // category blueprint keeps the user moving without inventing findings.
      if (kDebugMode) {
        debugPrint('[Auth] evidence plan request failed ($e) - using local category blueprint');
      }
      items = const [];
    }

    if (items.length < 4) {
      items = rules.evidenceBlueprint
          .asMap()
          .entries
          .map((e) => e.value.toEvidenceItem(e.key + 1))
          .toList();
    }

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
  }) async {
    final rules = AuthenticationRules.resolve(
      category: product.category,
      brand: product.brand,
      model: product.model,
    );
    final ref = ReferenceLibrary.findReference(product.brand, product.name);

    final imageParts = <Map<String, dynamic>>[];
    final imageManifest = StringBuffer();
    final missingList = <EvidenceItem>[];

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
      imageIndex++;
    }

    // The user supplied none of the requested angles. Rather than blocking
    // them, analyse the original identification photo on its own. It is not
    // credited to any requested angle, so evidence coverage stays at zero and
    // the result is bounded to inconclusive (§4, §26).
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
      overviewOnly = true;
    }

    final missingNote = missingList.isEmpty
        ? 'None - all requested angles were supplied.'
        : missingList
            .map((m) => '- ${m.title} (${m.weight.label}${m.isUnavailable ? ', user does not have it' : ', not supplied'})')
            .join('\n');

    final referenceNotes = StringBuffer();
    if (ref != null) {
      referenceNotes.writeln('Documented checkpoints for ${ref.brand} ${ref.model}:');
      for (final f in ref.features) {
        referenceNotes.writeln('- ${f.title}: ${f.expectedDetail}');
      }
      referenceNotes.writeln('Documented replica tells:');
      for (final flaw in ref.commonReplicaFlaws) {
        referenceNotes.writeln('- $flaw');
      }
    }

    final prompt = '''All attached images show ONE physical item: ${product.brand} ${product.name}${product.model.isNotEmpty ? ' (${product.model})' : ''}, category ${product.category.label}.

$imageManifest
Requested angles NOT supplied:
$missingNote
${overviewOnly ? '\nNOTE: none of the requested angles were supplied. Report only what the single overview photo shows, and list every requested angle under missing_critical_checks.' : ''}

INSPECTION FRAMEWORK for this category:
${rules.inspectionBriefing}

${referenceNotes.isEmpty ? '' : referenceNotes.toString()}
RULES:
1. Report OBSERVATIONS, not a verdict. Do NOT output an authenticity score or conclusion - the application computes that.
2. Treat all images as the same item. Actively compare them against each other and report any conflict (a reference on one image disagreeing with another, mismatched finish, different variant).
3. Category knowledge tells you what to inspect. It is NEVER proof by itself. Anchor each finding in what is visible in these photos.
4. If a detail is too small, blurred or obscured to judge, put it in uncertain_signals - do not guess.
5. Reference every observation to the evidence_id of the image it came from.

JSON only:
{"evidence_observations":[{"evidence_id":"","title":"","observations":[""],"consistent_signals":[""],"inconsistent_signals":[""],"uncertain_signals":[""],"visible_quality":0}],"contradictions":[{"description":"","involved_parts":[""],"severity":"minor|moderate|critical"}],"missing_critical_checks":[""],"physical_checks":[{"title":"","description":"","what_to_look_for":""}]}''';

    // A failure here is surfaced, never replaced with invented observations.
    final response = await _geminiService.generateStructuredContent(
      prompt: prompt,
      inlineImages: imageParts,
      requestTypeLabel: 'multi_image_forensic_observations',
      maxOutputTokens: 4096,
      timeout: const Duration(seconds: 90),
    );

    final geminiResponse = GeminiEvidenceResponse.fromJson(response);

    if (geminiResponse.partObservations.isEmpty) {
      throw AppError.invalidResponse();
    }

    final scoringResult = AuthenticationScoringEngine.evaluate(
      product: product,
      rawIdentificationConfidence: identificationConfidence,
      requiredEvidence: evidenceItems,
      capturedImages: capturedImages,
      observations: geminiResponse.partObservations,
      contradictions: geminiResponse.contradictions,
      rules: rules,
      reference: ref,
      hasModelReference: ref != null,
    );

    return AuthenticationReport(
      id: 'rep_${DateTime.now().millisecondsSinceEpoch}',
      product: product,
      verdict: scoringResult.verdict,
      overallScore: scoringResult.authenticationConfidence,
      identificationConfidence: scoringResult.identificationConfidence,
      authenticationConfidence: scoringResult.authenticationConfidence,
      evidenceCoverageText: scoringResult.evidenceCoverageText,
      coveredEvidenceCount: scoringResult.coveredCount,
      totalEvidenceCount: scoringResult.totalCount,
      quickSummaryPoints: scoringResult.quickSummaryPoints,
      positiveFindings: scoringResult.positiveFindings,
      suspiciousFindings: scoringResult.suspiciousFindings,
      unclearFindings: scoringResult.unclearFindings,
      missingEvidence: scoringResult.missingEvidenceDescriptions,
      contradictions: scoringResult.contradictionDescriptions,
      nextChecks: scoringResult.nextChecks,
      physicalChecks: geminiResponse.physicalChecks
          .map((c) => PhysicalCheck(
                title: c['title'] ?? '',
                description: c['description'] ?? '',
                whatToLookFor: c['what_to_look_for'] ?? '',
              ))
          .toList(),
      evidenceItems: scoringResult.scoredEvidenceItems,
      rationale: scoringResult.rationale,
      timestamp: DateTime.now(),
      isFavorite: false,
    );
  }
}
