import 'evidence_finding.dart';

/// Structured observations returned by Gemini for one photo during the
/// forensic inspection phase. Gemini reports evidence; the app decides.
class PartObservation {
  final String evidenceId;
  final String title;
  final List<String> observations;

  /// Typed, strength-rated findings (engine v2). Legacy responses without
  /// them are converted from the three signal lists below.
  final List<EvidenceFinding> findings;

  final List<String> consistentSignals;
  final List<String> inconsistentSignals;
  final List<String> uncertainSignals;
  final int visibleQuality; // 0-100

  const PartObservation({
    required this.evidenceId,
    required this.title,
    this.observations = const [],
    this.findings = const [],
    this.consistentSignals = const [],
    this.inconsistentSignals = const [],
    this.uncertainSignals = const [],
    this.visibleQuality = 80,
  });

  bool get hasInconsistencies => inconsistentSignals.isNotEmpty;
  bool get hasConsistentSignals => consistentSignals.isNotEmpty;
  bool get isUnclear => uncertainSignals.isNotEmpty && consistentSignals.isEmpty;

  /// Findings for the engine. Legacy signal lists map to MODERATE findings;
  /// the engine then applies the absence and photo-condition rules to them
  /// exactly as it does to typed findings.
  List<EvidenceFinding> get effectiveFindings {
    if (findings.isNotEmpty) return findings;
    return [
      for (final s in consistentSignals)
        EvidenceFinding(
          evidenceId: evidenceId,
          feature: title,
          type: FindingType.authenticIndicator,
          strength: FindingStrength.moderate,
          observation: s,
        ),
      for (final s in inconsistentSignals)
        EvidenceFinding(
          evidenceId: evidenceId,
          feature: title,
          type: FindingType.counterfeitIndicator,
          strength: FindingStrength.moderate,
          observation: s,
        ),
      for (final s in uncertainSignals)
        EvidenceFinding(
          evidenceId: evidenceId,
          feature: title,
          type: FindingType.ambiguous,
          strength: FindingStrength.weak,
          observation: s,
        ),
    ];
  }

  factory PartObservation.fromJson(Map<String, dynamic> json) {
    final id = json['evidence_id'] as String? ?? json['id'] as String? ?? '';
    List<String> strings(String key) =>
        (json[key] as List?)?.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList() ??
        const [];

    final findings = (json['findings'] as List? ?? const [])
        .whereType<Map>()
        .map((f) => EvidenceFinding.fromJson(Map<String, dynamic>.from(f), fallbackEvidenceId: id))
        .toList();

    // When typed findings exist, derive the display lists from them so the
    // report UI keeps working unchanged.
    final consistent = findings.isEmpty
        ? strings('consistent_signals')
        : findings.where((f) => f.isAuthentic).map((f) => f.displayText).toList();
    final inconsistent = findings.isEmpty
        ? strings('inconsistent_signals')
        : findings.where((f) => f.isCounterfeit).map((f) => f.displayText).toList();
    final uncertain = findings.isEmpty
        ? strings('uncertain_signals')
        : findings.where((f) => f.isUncertain).map((f) => f.displayText).toList();

    return PartObservation(
      evidenceId: id,
      title: json['title'] as String? ?? '',
      observations: strings('observations'),
      findings: findings,
      consistentSignals: consistent,
      inconsistentSignals: inconsistent,
      uncertainSignals: uncertain,
      visibleQuality: (json['visible_quality'] as num?)?.toInt() ?? 80,
    );
  }

  Map<String, dynamic> toJson() => {
        'evidence_id': evidenceId,
        'title': title,
        'observations': observations,
        'findings': findings.map((f) => f.toJson()).toList(),
        'consistent_signals': consistentSignals,
        'inconsistent_signals': inconsistentSignals,
        'uncertain_signals': uncertainSignals,
        'visible_quality': visibleQuality,
      };
}

enum ContradictionSeverity {
  minor,
  moderate,
  critical,
}

class CrossImageContradiction {
  final String description;
  final List<String> involvedPartIds;
  final ContradictionSeverity severity;

  const CrossImageContradiction({
    required this.description,
    required this.involvedPartIds,
    this.severity = ContradictionSeverity.moderate,
  });

  factory CrossImageContradiction.fromJson(Map<String, dynamic> json) {
    final sevStr = (json['severity'] as String? ?? 'moderate').toLowerCase();
    ContradictionSeverity sev = ContradictionSeverity.moderate;
    if (sevStr.contains('critical') || sevStr.contains('major') || sevStr.contains('high')) {
      sev = ContradictionSeverity.critical;
    } else if (sevStr.contains('minor') || sevStr.contains('low')) {
      sev = ContradictionSeverity.minor;
    }

    return CrossImageContradiction(
      description: json['description'] as String? ?? '',
      involvedPartIds: (json['involved_parts'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      severity: sev,
    );
  }

  Map<String, dynamic> toJson() => {
        'description': description,
        'involved_parts': involvedPartIds,
        'severity': severity.name,
      };
}

/// The model's answers to the pre-verdict self-check (prompt step 9).
class ContradictionCheck {
  final bool counterfeitEvidenceIsVisible;
  final bool counterfeitEvidenceIsModelSpecific;
  final bool couldBeExplainedByConditions;
  final bool modelIdentificationReliable;
  final bool morePhotosRequired;

  const ContradictionCheck({
    this.counterfeitEvidenceIsVisible = false,
    this.counterfeitEvidenceIsModelSpecific = false,
    this.couldBeExplainedByConditions = false,
    this.modelIdentificationReliable = true,
    this.morePhotosRequired = false,
  });

  factory ContradictionCheck.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ContradictionCheck();
    return ContradictionCheck(
      counterfeitEvidenceIsVisible: json['counterfeit_evidence_is_visible'] == true,
      counterfeitEvidenceIsModelSpecific: json['counterfeit_evidence_is_model_specific'] == true,
      couldBeExplainedByConditions: json['could_be_explained_by_lighting_angle_wear_or_compression'] == true,
      modelIdentificationReliable: json['model_identification_reliable'] != false,
      morePhotosRequired: json['more_photos_required'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'counterfeit_evidence_is_visible': counterfeitEvidenceIsVisible,
        'counterfeit_evidence_is_model_specific': counterfeitEvidenceIsModelSpecific,
        'could_be_explained_by_lighting_angle_wear_or_compression': couldBeExplainedByConditions,
        'model_identification_reliable': modelIdentificationReliable,
        'more_photos_required': morePhotosRequired,
      };
}

class GeminiEvidenceResponse {
  final List<PartObservation> partObservations;
  final List<CrossImageContradiction> contradictions;
  final List<String> missingCriticalChecks;
  final List<Map<String, String>> physicalChecks;

  // ------------------------------------------------------- engine v2
  final String? categoryCode;
  final String? brand;
  final String? model;
  final int modelConfidence;
  final bool modelConfirmed;
  final int imageQualityScore;
  final List<String> imageQualityIssues;
  final List<EvidenceFinding> missingEvidence;
  final ContradictionCheck contradictionCheck;
  final List<String> recommendedViews;

  /// Text the model read off the item (serials, model codes). Reported as
  /// observed text only - never as validated against any database.
  final List<String> observedText;

  /// The model's own classification. Advisory only: the engine decides, and
  /// uses this solely to downgrade a replica call the model itself doesn't
  /// support.
  final String? modelClassification;

  const GeminiEvidenceResponse({
    required this.partObservations,
    required this.contradictions,
    required this.missingCriticalChecks,
    required this.physicalChecks,
    this.categoryCode,
    this.brand,
    this.model,
    this.modelConfidence = 0,
    this.modelConfirmed = false,
    this.imageQualityScore = 0,
    this.imageQualityIssues = const [],
    this.missingEvidence = const [],
    this.contradictionCheck = const ContradictionCheck(),
    this.recommendedViews = const [],
    this.observedText = const [],
    this.modelClassification,
  });

  factory GeminiEvidenceResponse.fromJson(Map<String, dynamic> json) {
    final partsList = (json['evidence_observations'] as List? ?? json['evidence'] as List? ?? [])
        .whereType<Map>()
        .map((e) => PartObservation.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final contraList = (json['contradictions'] as List? ?? [])
        .whereType<Map>()
        .map((e) => CrossImageContradiction.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    // v2 sends structured missing evidence; v1 sent plain strings.
    final rawMissing = json['missing_evidence'] as List? ?? json['missing_critical_checks'] as List? ?? [];
    final missingStrings = <String>[];
    final missingFindings = <EvidenceFinding>[];
    for (final m in rawMissing) {
      if (m is Map) {
        final f = EvidenceFinding.fromJson({
          ...Map<String, dynamic>.from(m),
          'type': 'MISSING',
          'strength': 'WEAK',
          'observation': m['reason'] ?? m['observation'] ?? '',
        });
        missingFindings.add(f);
        missingStrings.add(f.feature.isNotEmpty ? f.feature : f.observation);
      } else {
        missingStrings.add(m.toString());
      }
    }

    final physChecks = (json['physical_checks'] as List? ?? [])
        .whereType<Map>()
        .map((e) => {
              'title': (e['title'] ?? '').toString(),
              'description': (e['description'] ?? '').toString(),
              'what_to_look_for': (e['what_to_look_for'] ?? '').toString(),
            })
        .toList();

    final ident = json['identification'] is Map ? Map<String, dynamic>.from(json['identification'] as Map) : null;
    final quality = json['image_quality'] is Map ? Map<String, dynamic>.from(json['image_quality'] as Map) : null;
    List<String> strings(dynamic v) =>
        (v as List?)?.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList() ?? const [];

    String? cleanText(dynamic v) {
      final s = v?.toString().trim();
      if (s == null || s.isEmpty || s.toLowerCase() == 'null' || s.toLowerCase() == 'unknown') return null;
      return s;
    }

    return GeminiEvidenceResponse(
      partObservations: partsList,
      contradictions: contraList,
      missingCriticalChecks: missingStrings,
      physicalChecks: physChecks,
      categoryCode: cleanText(ident?['category']),
      brand: cleanText(ident?['brand']),
      model: cleanText(ident?['model']),
      modelConfidence: (ident?['model_confidence'] as num?)?.toInt() ?? 0,
      modelConfirmed: ident?['model_confirmed'] == true,
      imageQualityScore: (quality?['score'] as num?)?.toInt() ?? 0,
      imageQualityIssues: strings(quality?['issues']),
      missingEvidence: missingFindings,
      contradictionCheck: ContradictionCheck.fromJson(
        json['contradiction_check'] is Map ? Map<String, dynamic>.from(json['contradiction_check'] as Map) : null,
      ),
      recommendedViews: strings(json['recommended_views']),
      observedText: strings(json['observed_text']),
      modelClassification: cleanText(json['model_classification']),
    );
  }
}

/// Result of the second-pass counterfeit verification for one finding.
enum VerificationOutcome {
  confirmed('CONFIRMED'),
  notVisible('NOT_VISIBLE'),
  explainedByConditions('EXPLAINED_BY_CONDITIONS'),
  notModelSpecific('NOT_MODEL_SPECIFIC');

  final String code;
  const VerificationOutcome(this.code);

  static VerificationOutcome parse(String? raw) {
    final s = (raw ?? '').toUpperCase();
    for (final v in values) {
      if (v.code == s) return v;
    }
    if (s.contains('CONFIRM')) return VerificationOutcome.confirmed;
    if (s.contains('VISIBLE')) return VerificationOutcome.notVisible;
    if (s.contains('SPECIFIC')) return VerificationOutcome.notModelSpecific;
    return VerificationOutcome.explainedByConditions;
  }
}
