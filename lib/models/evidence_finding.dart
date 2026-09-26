import '../core/config/authenticity_engine_config.dart';

/// What a single finding says about the item.
enum FindingType {
  /// A visible detail that matches the identified product.
  authenticIndicator('AUTHENTIC_INDICATOR'),

  /// A visible detail that conflicts with the identified product.
  counterfeitIndicator('COUNTERFEIT_INDICATOR'),

  /// Something that should be checked but isn't in any photo.
  missing('MISSING'),

  /// Visible, but it could reasonably be read either way.
  ambiguous('AMBIGUOUS'),

  /// Cannot be verified from a photo at all (weight, internal parts,
  /// database validity of a serial).
  unverifiable('UNVERIFIABLE');

  final String code;
  const FindingType(this.code);

  static FindingType parse(String? raw) {
    final s = (raw ?? '').toUpperCase();
    for (final t in values) {
      if (t.code == s) return t;
    }
    if (s.contains('COUNTERFEIT') || s.contains('REPLICA') || s.contains('FAKE')) {
      return FindingType.counterfeitIndicator;
    }
    if (s.contains('AUTHENTIC') || s.contains('GENUINE') || s.contains('CONSISTENT')) {
      return FindingType.authenticIndicator;
    }
    if (s.contains('MISSING') || s.contains('NOT_VISIBLE')) return FindingType.missing;
    if (s.contains('UNVERIF')) return FindingType.unverifiable;
    return FindingType.ambiguous;
  }
}

enum FindingStrength {
  weak('WEAK', AuthenticityEngineConfig.weakPoints),
  moderate('MODERATE', AuthenticityEngineConfig.moderatePoints),
  strong('STRONG', AuthenticityEngineConfig.strongPoints);

  final String code;
  final double points;
  const FindingStrength(this.code, this.points);

  static FindingStrength parse(String? raw) {
    final s = (raw ?? '').toUpperCase();
    if (s.contains('STRONG') || s.contains('HIGH')) return FindingStrength.strong;
    if (s.contains('WEAK') || s.contains('LOW')) return FindingStrength.weak;
    return FindingStrength.moderate;
  }

  FindingStrength get downgraded => switch (this) {
        FindingStrength.strong => FindingStrength.moderate,
        _ => FindingStrength.weak,
      };
}

/// One piece of evidence, tied to the photo it came from.
class EvidenceFinding {
  final String evidenceId;
  final String feature;

  /// Inspection dimension, e.g. LOGO, TYPOGRAPHY, HARDWARE, SERIAL.
  final String dimension;
  final FindingType type;
  final FindingStrength strength;
  final String observation;

  /// True when the comparison relies on known facts about this specific
  /// model, rather than generic "luxury goods should look like X" rules.
  final bool modelSpecific;

  /// A benign explanation the model offered (lighting, angle, wear...).
  final String? alternativeExplanation;

  /// Set by the engine when it changed the finding, e.g. "downgraded: photo
  /// quality 48". Kept for the debug log.
  final String? engineNote;

  const EvidenceFinding({
    required this.evidenceId,
    required this.feature,
    this.dimension = 'OTHER',
    required this.type,
    required this.strength,
    required this.observation,
    this.modelSpecific = false,
    this.alternativeExplanation,
    this.engineNote,
  });

  bool get isCounterfeit => type == FindingType.counterfeitIndicator;
  bool get isAuthentic => type == FindingType.authenticIndicator;
  bool get isUncertain => !isCounterfeit && !isAuthentic;

  String get displayText {
    final f = feature.trim();
    final o = observation.trim();
    if (f.isEmpty) return o;
    if (o.isEmpty) return f;
    return '$f: $o';
  }

  EvidenceFinding copyWith({
    FindingType? type,
    FindingStrength? strength,
    String? engineNote,
  }) =>
      EvidenceFinding(
        evidenceId: evidenceId,
        feature: feature,
        dimension: dimension,
        type: type ?? this.type,
        strength: strength ?? this.strength,
        observation: observation,
        modelSpecific: modelSpecific,
        alternativeExplanation: alternativeExplanation,
        engineNote: engineNote ?? this.engineNote,
      );

  factory EvidenceFinding.fromJson(Map<String, dynamic> json, {String fallbackEvidenceId = ''}) {
    final alt = (json['alternative_explanation'] as String?)?.trim();
    return EvidenceFinding(
      evidenceId: (json['evidence_id'] as String?)?.trim().isNotEmpty == true
          ? (json['evidence_id'] as String).trim()
          : fallbackEvidenceId,
      feature: (json['feature'] as String? ?? '').trim(),
      dimension: (json['dimension'] as String? ?? 'OTHER').trim().toUpperCase(),
      type: FindingType.parse(json['type'] as String?),
      strength: FindingStrength.parse(json['strength'] as String?),
      observation: (json['observation'] as String? ?? '').trim(),
      modelSpecific: json['model_specific'] == true,
      alternativeExplanation: (alt == null || alt.isEmpty || alt.toLowerCase() == 'null') ? null : alt,
      engineNote: json['engine_note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'evidence_id': evidenceId,
        'feature': feature,
        'dimension': dimension,
        'type': type.code,
        'strength': strength.code,
        'observation': observation,
        'model_specific': modelSpecific,
        if (alternativeExplanation != null) 'alternative_explanation': alternativeExplanation,
        if (engineNote != null) 'engine_note': engineNote,
      };

  // ------------------------------------------------ absence / conditions
  static final RegExp _absencePattern = RegExp(
    r"\b(not (clearly )?(visible|shown|pictured|captured|legible|readable|in (the )?(frame|photo|image))|"
    r"(can(no|')t|could ?n[o']t|unable to|impossible to) (be )?(see|seen|read|verify|verified|confirm|confirmed|inspect|inspected|assess|assessed|determine|determined|make out)|"
    r"no (visible|clear|legible|readable) |"
    r"out of frame|obscured|hidden by|covered by|"
    r"missing from (the )?(photo|image|picture)s?|not photographed|not provided|not supplied|not included)",
    caseSensitive: false,
  );

  static final RegExp _conditionsPattern = RegExp(
    r"\b(glare|reflections?|lighting|shadows?|out of focus|blurr?(y|ed)?|motion blur|"
    r"too (dark|bright|far|small)|over-?exposed|under-?exposed|compression|artifacts?|pixelat|"
    r"low resolution|camera angle|viewing angle|due to (the )?angle|perspective|may be (due|caused)|"
    r"possibly (due|caused)|could be (due|caused))",
    caseSensitive: false,
  );

  /// True when a finding describes something that simply isn't visible,
  /// rather than something visibly wrong. Absence is never counterfeit
  /// evidence: "serial not visible" means unverified, not fake.
  static bool describesAbsence(String text) => _absencePattern.hasMatch(text);

  /// True when a finding attributes what it saw to photo conditions, which
  /// makes it ambiguous rather than evidence either way.
  static bool attributesToConditions(String text) => _conditionsPattern.hasMatch(text);
}
