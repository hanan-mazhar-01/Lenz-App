import 'evidence_record.dart';

/// Final verdict codes of the structured assessment.
abstract final class AssessmentVerdict {
  /// Visually consistent with an authentic item. Never manufacturer-verified.
  static const authenticVisual = 'AUTHENTIC_VISUAL';
  static const replica = 'REPLICA';
  static const unableToVerify = 'UNABLE_TO_VERIFY';
  static const all = [authenticVisual, replica, unableToVerify];
}

class ModelIdentificationStatus {
  /// The model the evidence was compared against, with its certainty.
  final String evaluatedModel;
  final String brandStatus;
  final String modelStatus;
  final String generationStatus;
  final String? generation;

  /// What established the model (visible feature, device screen...).
  final String basis;
  final List<String> uncertainAttributes;

  const ModelIdentificationStatus({
    required this.evaluatedModel,
    required this.brandStatus,
    required this.modelStatus,
    required this.generationStatus,
    this.generation,
    this.basis = '',
    this.uncertainAttributes = const [],
  });

  Map<String, dynamic> toJson() => {
        'evaluated_model': evaluatedModel,
        'brand_status': brandStatus,
        'model_status': modelStatus,
        'generation_status': generationStatus,
        'generation': generation,
        'basis': basis,
        'uncertain_attributes': uncertainAttributes,
      };

  factory ModelIdentificationStatus.fromJson(Map<String, dynamic> j) => ModelIdentificationStatus(
        evaluatedModel: j['evaluated_model'] as String? ?? '',
        brandStatus: j['brand_status'] as String? ?? 'UNKNOWN',
        modelStatus: j['model_status'] as String? ?? 'UNKNOWN',
        generationStatus: j['generation_status'] as String? ?? 'UNKNOWN',
        generation: j['generation'] as String?,
        basis: j['basis'] as String? ?? '',
        uncertainAttributes: (j['uncertain_attributes'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

class EvidencePhotoSummary {
  final String photoId;
  final String title;
  final String summary;
  final bool usedAsEvidence;
  final String qualityNote;

  const EvidencePhotoSummary({
    required this.photoId,
    required this.title,
    required this.summary,
    this.usedAsEvidence = true,
    this.qualityNote = '',
  });

  Map<String, dynamic> toJson() => {
        'photo_id': photoId,
        'title': title,
        'summary': summary,
        'used_as_evidence': usedAsEvidence,
        'quality_note': qualityNote,
      };

  factory EvidencePhotoSummary.fromJson(Map<String, dynamic> j) => EvidencePhotoSummary(
        photoId: j['photo_id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        usedAsEvidence: j['used_as_evidence'] as bool? ?? true,
        qualityNote: j['quality_note'] as String? ?? '',
      );
}

class NextPhotoRecommendation {
  final String requestId;
  final String title;
  final String instruction;

  /// Why this photo is the most informative next step.
  final String reason;

  /// True when the evidence already supports a verdict.
  final bool optional;

  const NextPhotoRecommendation({
    required this.requestId,
    required this.title,
    required this.instruction,
    required this.reason,
    required this.optional,
  });

  Map<String, dynamic> toJson() => {
        'request_id': requestId,
        'title': title,
        'instruction': instruction,
        'reason': reason,
        'optional': optional,
      };

  factory NextPhotoRecommendation.fromJson(Map<String, dynamic> j) => NextPhotoRecommendation(
        requestId: j['request_id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        instruction: j['instruction'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        optional: j['optional'] as bool? ?? true,
      );
}

/// The structured result of one scan (§8). Built by the app from the
/// evidence engine, never taken verbatim from a model response, and checked
/// by [validate] before it is stored.
class AuthenticationAssessment {
  final String productCategory;
  final String brand;
  final String model;
  final ModelIdentificationStatus modelIdentification;
  final List<EvidencePhotoSummary> availableEvidence;
  final List<EvidenceRecord> supportingObservations;
  final List<EvidenceRecord> contradictoryObservations;

  /// Overall evidence reliability: "Strong", "Moderate" or "Limited".
  final String evidenceReliability;
  final String evidenceReliabilityNote;
  final NextPhotoRecommendation? recommendedNextPhoto;
  final bool sufficientEvidence;

  /// One of [AssessmentVerdict.all].
  final String verdict;
  final String explanation;
  final List<String> remainingUncertainty;

  /// Always "NOT_VERIFIED": photographs cannot be verified with a manufacturer.
  final String manufacturerVerificationStatus;
  final String manufacturerVerificationNote;
  final List<String> recommendedNextSteps;

  const AuthenticationAssessment({
    required this.productCategory,
    required this.brand,
    required this.model,
    required this.modelIdentification,
    required this.availableEvidence,
    required this.supportingObservations,
    required this.contradictoryObservations,
    required this.evidenceReliability,
    this.evidenceReliabilityNote = '',
    this.recommendedNextPhoto,
    required this.sufficientEvidence,
    required this.verdict,
    required this.explanation,
    required this.remainingUncertainty,
    this.manufacturerVerificationStatus = 'NOT_VERIFIED',
    this.manufacturerVerificationNote =
        'Visual analysis only. Nothing was checked with the manufacturer, and serial numbers were read from photos, not validated.',
    required this.recommendedNextSteps,
  });

  /// Invariants a well-formed assessment must satisfy. Empty when valid.
  List<String> validate() {
    final v = <String>[];
    if (!AssessmentVerdict.all.contains(verdict)) v.add('unknown verdict "$verdict"');
    final material = contradictoryObservations
        .where((r) => r.reliability.atLeast(Reliability.medium) && r.weight.atLeast(Weight.medium))
        .toList();
    if (verdict == AssessmentVerdict.authenticVisual) {
      if (material.isNotEmpty) v.add('authentic verdict with unresolved material contradictions');
      if (supportingObservations.isEmpty) v.add('authentic verdict without supporting observations');
    }
    if (verdict == AssessmentVerdict.replica && contradictoryObservations.isEmpty) {
      v.add('replica verdict without contradictory observations');
    }
    if (sufficientEvidence != (verdict != AssessmentVerdict.unableToVerify)) {
      v.add('sufficientEvidence disagrees with the verdict');
    }
    if (sufficientEvidence && recommendedNextPhoto != null && !recommendedNextPhoto!.optional) {
      v.add('next photo must be optional when evidence is sufficient');
    }
    if (manufacturerVerificationStatus != 'NOT_VERIFIED' &&
        !supportingObservations.any((r) => r.kind == EvidenceKind.manufacturerVerified)) {
      v.add('manufacturer verification claimed without a verified source');
    }
    if (explanation.trim().isEmpty) v.add('empty explanation');
    if (verdict == AssessmentVerdict.unableToVerify && remainingUncertainty.isEmpty) {
      v.add('unable to verify without stating what remains unresolved');
    }
    return v;
  }

  Map<String, dynamic> toJson() => {
        'product_category': productCategory,
        'brand': brand,
        'model': model,
        'model_identification': modelIdentification.toJson(),
        'available_evidence': availableEvidence.map((e) => e.toJson()).toList(),
        'supporting_observations': supportingObservations.map((e) => e.toJson()).toList(),
        'contradictory_observations': contradictoryObservations.map((e) => e.toJson()).toList(),
        'evidence_reliability': evidenceReliability,
        'evidence_reliability_note': evidenceReliabilityNote,
        'recommended_next_photo': recommendedNextPhoto?.toJson(),
        'sufficient_evidence': sufficientEvidence,
        'verdict': verdict,
        'explanation': explanation,
        'remaining_uncertainty': remainingUncertainty,
        'manufacturer_verification_status': manufacturerVerificationStatus,
        'manufacturer_verification_note': manufacturerVerificationNote,
        'recommended_next_steps': recommendedNextSteps,
      };

  factory AuthenticationAssessment.fromJson(Map<String, dynamic> j) {
    List<EvidenceRecord> records(String k) => (j[k] as List? ?? const [])
        .whereType<Map>()
        .map((e) => EvidenceRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    List<String> strings(String k) => (j[k] as List?)?.map((e) => e.toString()).toList() ?? const [];
    return AuthenticationAssessment(
      productCategory: j['product_category'] as String? ?? '',
      brand: j['brand'] as String? ?? '',
      model: j['model'] as String? ?? '',
      modelIdentification: ModelIdentificationStatus.fromJson(
          Map<String, dynamic>.from(j['model_identification'] as Map? ?? const {})),
      availableEvidence: (j['available_evidence'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => EvidencePhotoSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      supportingObservations: records('supporting_observations'),
      contradictoryObservations: records('contradictory_observations'),
      evidenceReliability: j['evidence_reliability'] as String? ?? 'Limited',
      evidenceReliabilityNote: j['evidence_reliability_note'] as String? ?? '',
      recommendedNextPhoto: j['recommended_next_photo'] is Map
          ? NextPhotoRecommendation.fromJson(Map<String, dynamic>.from(j['recommended_next_photo'] as Map))
          : null,
      sufficientEvidence: j['sufficient_evidence'] as bool? ?? false,
      verdict: j['verdict'] as String? ?? AssessmentVerdict.unableToVerify,
      explanation: j['explanation'] as String? ?? '',
      remainingUncertainty: strings('remaining_uncertainty'),
      manufacturerVerificationStatus: j['manufacturer_verification_status'] as String? ?? 'NOT_VERIFIED',
      manufacturerVerificationNote: j['manufacturer_verification_note'] as String? ?? '',
      recommendedNextSteps: strings('recommended_next_steps'),
    );
  }
}
