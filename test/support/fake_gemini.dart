import 'package:replica_detector/core/errors/app_error.dart';
import 'package:replica_detector/services/gemini_service.dart';
import 'package:replica_detector/services/image_preparation_service.dart';
import 'package:replica_detector/services/native_image_decoder.dart';

/// Stands in for the network. Records every call so tests can assert how many
/// requests a flow makes, with how many images, and against which schema.
class FakeGeminiService implements GeminiService {
  final List<String> calls = [];
  final List<int> imageCounts = [];
  final List<String> prompts = [];
  final List<Map<String, dynamic>?> schemas = [];
  final List<String?> scanIds = [];
  final List<String?> thinkingLevels = [];

  /// Responses by label prefix. A list value is consumed in order (last one
  /// repeats), which lets a test return a malformed answer first.
  final Map<String, Object> responses;
  final Map<String, Object> errors;

  FakeGeminiService({this.responses = const {}, this.errors = const {}});

  final Map<String, int> _served = {};

  int callsMatching(String prefix) => calls.where((c) => c.startsWith(prefix)).length;

  int imagesFor(String prefix) {
    var n = 0;
    for (var i = 0; i < calls.length; i++) {
      if (calls[i].startsWith(prefix)) n += imageCounts[i];
    }
    return n;
  }

  @override
  Future<Map<String, dynamic>> generateStructuredContent({
    required String prompt,
    List<Map<String, dynamic>>? inlineImages,
    String? requestTypeLabel,
    int? maxOutputTokens,
    Duration? timeout,
    Map<String, dynamic>? responseSchema,
    String? scanId,
    String? thinkingLevel,
  }) async {
    final label = requestTypeLabel ?? 'unknown';
    calls.add(label);
    prompts.add(prompt);
    schemas.add(responseSchema);
    imageCounts.add(inlineImages?.length ?? 0);
    scanIds.add(scanId);
    thinkingLevels.add(thinkingLevel);

    for (final entry in errors.entries) {
      if (label.startsWith(entry.key)) throw entry.value;
    }
    // Longest matching prefix wins, so 'photo_analysis:back' can override
    // a generic 'photo_analysis'.
    final keys = responses.keys.where(label.startsWith).toList()..sort((a, b) => b.length.compareTo(a.length));
    if (keys.isNotEmpty) {
      final v = responses[keys.first]!;
      if (v is List) {
        final i = _served[keys.first] ?? 0;
        _served[keys.first] = i + 1;
        return Map<String, dynamic>.from(v[i.clamp(0, v.length - 1)] as Map);
      }
      return Map<String, dynamic>.from(v as Map);
    }
    throw AppError.invalidResponse();
  }

  @override
  void close() {}
}

/// Skips real file and image decoding so pipeline tests stay hermetic.
class FakeImagePreparationService implements ImagePreparationService {
  final List<String> prepared = [];
  final List<String> persisted = [];
  final List<String> deleted = [];

  @override
  Future<PreparedImage> prepareImage(String pathOrAsset, {ImagePreset preset = ImagePreset.evidence}) async {
    prepared.add('$pathOrAsset|${preset.name}');
    return const PreparedImage(base64Data: 'ZmFrZQ==', mimeType: 'image/jpeg', byteSize: 4, width: 1024, height: 768);
  }

  @override
  void warm(String pathOrAsset, ImagePreset preset) {}

  /// Origin hints the tests set per path (none by default).
  final Map<String, String> originHints = {};

  @override
  String? originHint(String storedPath) => originHints[storedPath];

  @override
  Future<PreparedImage> encodePixels(PixelBuffer pixels, {int maxDimension = 1024, int jpegQuality = 90}) async =>
      const PreparedImage(base64Data: 'Y3JvcA==', mimeType: 'image/jpeg', byteSize: 4, width: 512, height: 512);

  @override
  Future<String> persistCapturedImage(String tempPath, {String prefix = 'scan', bool stripExif = false}) async {
    persisted.add(tempPath);
    return '/documents/vericheck_evidence/${prefix}_${persisted.length}.jpg';
  }

  @override
  Future<void> deleteStoredImages(Iterable<String> paths) async => deleted.addAll(paths);

  @override
  void clearCache() {}

  @override
  int get cacheSizeBytes => 0;
}

// ---------------------------------------------------------------- canned JSON

Map<String, dynamic> identificationJson({
  String status = 'product_detected',
  String reason = 'valid_luxury_product',
  bool productDetected = true,
  String categoryCode = 'WATCH',
  String category = 'Watches',
  String type = 'smartwatch',
  String? brand = 'Apple',
  String brandStatus = 'CONFIRMED',
  String? model = 'Apple Watch Ultra',
  String modelStatus = 'PROBABLE',
  String? generation,
  String generationStatus = 'UNKNOWN',
  double confidence = 0.93,
  List<num>? box = const [200, 250, 800, 750],
  String source = 'PHYSICAL_ITEM',
}) =>
    {
      'image_source': source,
      'status': status,
      'reason': reason,
      'product_detected': productDetected,
      'category_code': categoryCode,
      'product_category': category,
      'product_type': type,
      'confidence': confidence,
      'brand': brand,
      'brand_status': brandStatus,
      'brand_basis': 'logo',
      'product_name': model,
      'model': model,
      'model_status': modelStatus,
      'model_basis': 'case design',
      'generation': generation,
      'generation_status': generationStatus,
      'exact_model': null,
      'exact_model_status': 'UNKNOWN',
      'visible_part': 'front display',
      'item_box_2d': box,
      'visible_characteristics': ['titanium case'],
      'distinguishing_features': ['raised case edge'],
      'uncertain_attributes': ['generation'],
      'message': 'Item identified successfully.',
    };

Map<String, dynamic> recommendationJson(List<String> order, {String value = 'HIGH'}) => {
      'ranked': [
        for (final (i, id) in order.indexed)
          {
            'request_id': id,
            'discriminative_value': i == 0 ? value : 'MEDIUM',
            'photo_assessable': true,
            'model_specific_checks': ['fixture check'],
            'reason': 'fixture',
          },
      ],
      'model_notes': ['Bands are interchangeable.'],
    };

Map<String, dynamic> photoCheckJson({
  String matched = 'back_sensor',
  bool usable = true,
  bool showsProduct = true,
  bool showsRequested = true,
  int requestedConfidence = 90,
  String? partShown,
  String readability = 'READABLE',
  List<String> issues = const ['NONE'],
  String fix = '',
  List<num>? box = const [250, 250, 750, 750],
  int quality = 85,
  String source = 'PHYSICAL_ITEM',
}) =>
    {
      'image_source': source,
      'part_shown': partShown ?? matched.replaceAll('_', ' '),
      'shows_product': showsProduct,
      'shows_requested_part': showsRequested,
      'requested_part_confidence': requestedConfidence,
      'matched_request_id': matched,
      'detail_box_2d': box,
      'detail_readability': readability,
      'issues': issues,
      'usable': usable,
      'fix': fix,
      'quality_score': quality,
      'reason': 'Clear photo.',
    };

Map<String, dynamic> assessmentJson(
  String id,
  String outcome, {
  String reliability = 'HIGH',
  String observation = 'fixture observation',
  String interpretation = 'fixture interpretation',
  String? alternative,
  String basis = 'MODEL_KNOWLEDGE',
  String kind = 'AI_INTERPRETATION',
  String feature = '',
}) =>
    {
      'checkpoint_id': id,
      'feature': feature,
      'observation': observation,
      'interpretation': interpretation,
      'outcome': outcome,
      'reliability': reliability,
      'limitation': '',
      'basis': basis,
      'evidence_kind': kind,
      'alternative_explanation': alternative,
    };

Map<String, dynamic> photoAnalysisJson(
  List<Map<String, dynamic>> assessments, {
  String matched = 'front_display',
  List<String> observedText = const [],
  Map<String, dynamic>? identity,
}) =>
    {
      'photo_summary': 'fixture summary',
      'matched_request_id': matched,
      'observed_text': observedText,
      'identity_evidence': identity ?? {'status': 'UNKNOWN', 'source': 'NONE'},
      'assessments': assessments,
    };

Map<String, dynamic> finalEvaluationJson({
  List<Map<String, dynamic>> variations = const [],
  List<Map<String, dynamic>> contradictions = const [],
  bool identityConsistent = true,
}) =>
    {
      'cross_photo_contradictions': contradictions,
      'variation_checks': variations,
      'identity_consistent': identityConsistent,
      'remaining_uncertainty': <String>[],
      'notes': 'fixture',
    };

// ------------------------------------------------ engine v4 (combined stage)

/// One finding of the combined analysis. Fixture data, not model output.
/// [claimId] is a checklist id (b#) or "none" for Gemini's own knowledge.
Map<String, dynamic> findingJson(
  String claimId,
  String comparison, {
  List<String> images = const ['P1'],
  String? area,
  String visibility = 'CLEAR',
  String reliability = 'HIGH',
  String? basis,
  String variation = 'NOT_APPLICABLE',
  String? alternative,
  String observed = 'fixture observation',
  String part = 'other',
  String? differenceKind,
  String detailKind = 'CONSTRUCTION',
  bool hard = false,
  bool tell = false,
  String scope = 'MODEL_FAMILY',
}) =>
    {
      'claim_id': claimId,
      'feature': area ?? claimId,
      'area': area ?? claimId,
      'part_request_id': part,
      'image_ids': images,
      'observed': observed,
      'comparison': comparison,
      'difference_kind': differenceKind ?? (comparison == 'CONFLICTS' ? 'DIFFERENT' : 'NOT_APPLICABLE'),
      'visibility': visibility,
      'reliability': reliability,
      'basis': basis ?? (claimId == 'none' ? 'MODEL_KNOWLEDGE' : 'CHECKLIST_ITEM'),
      'knowledge_scope': scope,
      'detail_kind': detailKind,
      'hard_to_copy': hard,
      'counterfeit_tell': tell,
      'alternative_explanation': alternative,
      'legitimate_variation': variation,
    };

Map<String, dynamic> combinedJson({
  List<Map<String, dynamic>> findings = const [],
  List<Map<String, dynamic>> contradictions = const [],
  String verdict = 'NOT_SURE',
  bool consistent = true,
  List<Map<String, dynamic>> unresolved = const [],
  List<String> verification = const [],
  String? brand = 'Apple',
  List<String> summaryPoints = const ['Fixture summary point 1', 'Fixture summary point 2'],
}) =>
    {
      'identity_established': {
        'brand': brand,
        'model': 'Apple Watch Ultra',
        'generation': null,
        'variant': null,
        'basis': 'fixture',
        'consistent_with_identification': consistent,
      },
      'findings': findings,
      'cross_image_contradictions': contradictions,
      'proposed_verdict': verdict,
      'verdict_reasoning': 'fixture reasoning',
      'summary_points': summaryPoints,
      'unresolved': unresolved,
      'independent_verification': verification,
    };

/// Findings that satisfy the Authentic rules: three different parts, one
/// hard-to-copy physical detail, seen in two photos (Gemini's knowledge).
List<Map<String, dynamic>> authenticFindings() => [
      findingJson('none', 'MATCHES', images: ['P2'], area: 'back', part: 'back_sensor', detailKind: 'MATERIAL', hard: true),
      findingJson('none', 'MATCHES', images: ['P1'], area: 'crown', part: 'crown_side'),
      findingJson('none', 'MATCHES', images: ['P1'], area: 'display', part: 'front_display'),
    ];
