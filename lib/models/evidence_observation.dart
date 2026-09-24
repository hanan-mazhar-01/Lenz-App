/// Structured raw observations returned by Gemini during the forensic inspection phase.
/// Gemini is tasked with reporting observations ONLY, not premature verdicts or raw overall scores.
class PartObservation {
  final String evidenceId;
  final String title;
  final List<String> observations;
  final List<String> consistentSignals;
  final List<String> inconsistentSignals;
  final List<String> uncertainSignals;
  final int visibleQuality; // 0-100

  const PartObservation({
    required this.evidenceId,
    required this.title,
    this.observations = const [],
    this.consistentSignals = const [],
    this.inconsistentSignals = const [],
    this.uncertainSignals = const [],
    this.visibleQuality = 80,
  });

  bool get hasInconsistencies => inconsistentSignals.isNotEmpty;
  bool get hasConsistentSignals => consistentSignals.isNotEmpty;
  bool get isUnclear => uncertainSignals.isNotEmpty && consistentSignals.isEmpty;

  factory PartObservation.fromJson(Map<String, dynamic> json) {
    return PartObservation(
      evidenceId: json['evidence_id'] as String? ?? json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      observations: (json['observations'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      consistentSignals: (json['consistent_signals'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      inconsistentSignals: (json['inconsistent_signals'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      uncertainSignals: (json['uncertain_signals'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      visibleQuality: (json['visible_quality'] as num?)?.toInt() ?? 80,
    );
  }

  Map<String, dynamic> toJson() => {
        'evidence_id': evidenceId,
        'title': title,
        'observations': observations,
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

class GeminiEvidenceResponse {
  final List<PartObservation> partObservations;
  final List<CrossImageContradiction> contradictions;
  final List<String> missingCriticalChecks;
  final List<Map<String, String>> physicalChecks;

  const GeminiEvidenceResponse({
    required this.partObservations,
    required this.contradictions,
    required this.missingCriticalChecks,
    required this.physicalChecks,
  });

  factory GeminiEvidenceResponse.fromJson(Map<String, dynamic> json) {
    final partsList = (json['evidence_observations'] as List? ?? json['evidence'] as List? ?? [])
        .map((e) => PartObservation.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final contraList = (json['contradictions'] as List? ?? [])
        .map((e) => CrossImageContradiction.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final missing = (json['missing_evidence'] as List? ?? json['missing_critical_checks'] as List? ?? [])
        .map((e) => e.toString())
        .toList();

    final physChecks = (json['physical_checks'] as List? ?? [])
        .map((e) => {
              'title': (e['title'] ?? '').toString(),
              'description': (e['description'] ?? '').toString(),
              'what_to_look_for': (e['what_to_look_for'] ?? '').toString(),
            })
        .toList();

    return GeminiEvidenceResponse(
      partObservations: partsList,
      contradictions: contraList,
      missingCriticalChecks: missing,
      physicalChecks: physChecks,
    );
  }
}
