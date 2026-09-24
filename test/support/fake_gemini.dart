import 'package:replica_detector/core/errors/app_error.dart';
import 'package:replica_detector/services/gemini_service.dart';
import 'package:replica_detector/services/image_preparation_service.dart';

/// Stands in for the network. Records every call so tests can assert how many
/// requests a flow actually makes.
class FakeGeminiService implements GeminiService {
  final List<String> calls = [];
  final List<int> imageCounts = [];
  final Map<String, Map<String, dynamic>> responses;
  final Map<String, Object> errors;

  FakeGeminiService({this.responses = const {}, this.errors = const {}});

  int callsMatching(String prefix) => calls.where((c) => c.startsWith(prefix)).length;

  @override
  Future<Map<String, dynamic>> generateStructuredContent({
    required String prompt,
    List<Map<String, dynamic>>? inlineImages,
    String? requestTypeLabel,
    int? maxOutputTokens,
    Duration? timeout,
  }) async {
    final label = requestTypeLabel ?? 'unknown';
    calls.add(label);
    imageCounts.add(inlineImages?.length ?? 0);

    for (final entry in errors.entries) {
      if (label.startsWith(entry.key)) throw entry.value;
    }
    for (final entry in responses.entries) {
      if (label.startsWith(entry.key)) return entry.value;
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
    return const PreparedImage(
      base64Data: 'ZmFrZQ==',
      mimeType: 'image/jpeg',
      byteSize: 4,
      width: 1024,
      height: 768,
    );
  }

  @override
  Future<String> persistCapturedImage(String tempPath, {String prefix = 'scan', bool stripExif = false}) async {
    persisted.add(tempPath);
    return '/documents/vericheck_evidence/${prefix}_stored.jpg';
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
  String category = 'Watches',
  String brand = 'Rolex',
  String product = 'Submariner Date',
  String model = '126610LN',
  double confidence = 0.91,
}) =>
    {
      'status': status,
      'reason': reason,
      'product_detected': productDetected,
      'product_category': category,
      'category': category,
      'brand': brand,
      'product': product,
      'model': model,
      'identification_confidence': confidence,
      'visible_details': ['black dial', 'steel bracelet'],
      'message': 'Item identified successfully.',
    };

Map<String, dynamic> evidencePlanJson() => {
      'requiredEvidence': [
        {'id': 'full_watch', 'title': 'Full Watch', 'guide': 'Whole watch straight on', 'reason': 'proportions', 'weight': 'high'},
        {'id': 'dial', 'title': 'Dial', 'guide': 'Flat, glare free', 'reason': 'printing', 'weight': 'critical'},
        {'id': 'crown', 'title': 'Crown', 'guide': 'Side close-up', 'reason': 'machining', 'weight': 'high'},
        {'id': 'caseback', 'title': 'Caseback', 'guide': 'Whole back', 'reason': 'finishing', 'weight': 'high'},
        {'id': 'bracelet_clasp', 'title': 'Bracelet & Clasp', 'guide': 'Clasp engraving', 'reason': 'stamping', 'weight': 'medium'},
        {'id': 'reference_serial', 'title': 'Reference / Serial', 'guide': 'Macro of serial', 'reason': 'format', 'weight': 'critical'},
      ],
    };

Map<String, dynamic> validationJson({
  String detected = 'dial',
  bool matches = true,
  int matchConfidence = 96,
  int quality = 91,
  int usefulness = 89,
}) =>
    {
      'evidence_type_detected': detected,
      'match_to_requested_evidence': matches,
      'match_confidence': matchConfidence,
      'photo_quality_score': quality,
      'quality_status': 'EXCELLENT',
      'sharpness': quality,
      'lighting': quality,
      'framing': quality,
      'detail': quality,
      'usability_score': quality,
      'authentication_usefulness': usefulness,
      'reason': 'Clear and well framed.',
    };

Map<String, dynamic> observationsJson({bool suspicious = false}) => {
      'evidence_observations': [
        {
          'evidence_id': 'full_watch',
          'title': 'Full Watch',
          'observations': ['Case and bracelet visible'],
          'consistent_signals': ['Proportions match the reference', 'End links sit flush'],
          'inconsistent_signals': <String>[],
          'uncertain_signals': <String>[],
          'visible_quality': 90,
        },
        {
          'evidence_id': 'dial',
          'title': 'Dial',
          'observations': ['Dial printing visible'],
          'consistent_signals': suspicious ? <String>[] : ['Kerning is even', 'Lume fills the markers'],
          'inconsistent_signals': suspicious ? ['Coronet is malformed', 'Text bleeds at the edges'] : <String>[],
          'uncertain_signals': <String>[],
          'visible_quality': 92,
        },
        {
          'evidence_id': 'crown',
          'title': 'Crown',
          'observations': ['Crown profile visible'],
          'consistent_signals': ['Knurling is cleanly machined'],
          'inconsistent_signals': <String>[],
          'uncertain_signals': <String>[],
          'visible_quality': 88,
        },
        {
          'evidence_id': 'caseback',
          'title': 'Caseback',
          'observations': ['Caseback visible'],
          'consistent_signals': ['Uniform brushing, no engraving'],
          'inconsistent_signals': <String>[],
          'uncertain_signals': <String>[],
          'visible_quality': 89,
        },
        {
          'evidence_id': 'bracelet_clasp',
          'title': 'Bracelet & Clasp',
          'observations': ['Clasp visible'],
          'consistent_signals': ['Stamping is crisp'],
          'inconsistent_signals': <String>[],
          'uncertain_signals': <String>[],
          'visible_quality': 87,
        },
        {
          'evidence_id': 'reference_serial',
          'title': 'Reference / Serial',
          'observations': ['Serial visible'],
          'consistent_signals': ['Serial format matches the model', 'Etch depth consistent'],
          'inconsistent_signals': suspicious ? ['Serial is shallow and the wrong length'] : <String>[],
          'uncertain_signals': <String>[],
          'visible_quality': 90,
        },
      ],
      'contradictions': <Map<String, dynamic>>[],
      'missing_critical_checks': <String>[],
      'physical_checks': [
        {
          'title': 'Crown tactile check',
          'description': 'Unscrew and feel the crown action.',
          'what_to_look_for': 'Smooth threading without grit',
        },
      ],
    };
