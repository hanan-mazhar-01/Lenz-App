import 'product_identity.dart';

/// How far one observation can be trusted.
enum Reliability {
  high('HIGH', 'High'),
  medium('MEDIUM', 'Medium'),
  low('LOW', 'Low');

  final String code;
  final String label;
  const Reliability(this.code, this.label);

  static Reliability parse(String? raw) {
    final s = (raw ?? '').toUpperCase();
    if (s.startsWith('HIGH') || s.startsWith('STRONG')) return Reliability.high;
    if (s.startsWith('MED') || s.startsWith('MODERATE')) return Reliability.medium;
    return Reliability.low;
  }

  Reliability get downgraded => switch (this) {
        Reliability.high => Reliability.medium,
        _ => Reliability.low,
      };

  Reliability cappedAt(Reliability cap) => index < cap.index ? cap : this;

  bool atLeast(Reliability other) => index <= other.index;
}

/// How much a checkpoint can contribute in one direction.
enum Weight {
  none,
  low,
  medium,
  high,

  /// On its own enough to show an item is not the genuine model, once the
  /// observation is reliable and legitimate variations are ruled out.
  decisive;

  bool atLeast(Weight other) => index >= other.index;

  Weight capped(Weight cap) => index > cap.index ? cap : this;
}

/// What one photo showed about one checkpoint.
enum CheckpointOutcome {
  consistent('CONSISTENT'),
  inconsistent('INCONSISTENT'),
  notVisible('NOT_VISIBLE'),
  unclear('UNCLEAR');

  final String code;
  const CheckpointOutcome(this.code);

  static CheckpointOutcome? tryParse(String? raw) {
    final s = (raw ?? '').toUpperCase().trim();
    for (final v in values) {
      if (v.code == s) return v;
    }
    if (s.startsWith('MATCH') || s.startsWith('AUTHENTIC')) return CheckpointOutcome.consistent;
    if (s.startsWith('CONFLICT') || s.startsWith('COUNTERFEIT') || s.startsWith('MISMATCH')) {
      return CheckpointOutcome.inconsistent;
    }
    if (s.contains('VISIBLE') || s == 'MISSING') return CheckpointOutcome.notVisible;
    if (s.startsWith('AMBIG') || s.startsWith('UNCLEAR') || s.startsWith('CANNOT')) return CheckpointOutcome.unclear;
    return null;
  }
}

enum EvidenceDirection {
  supportsAuthentic('Supports authenticity'),
  supportsCounterfeit('Points to a replica'),

  /// Matches the design, which replicas copy too: identifies, doesn't authenticate.
  neutral('Matches the design only'),
  unclear('Unclear'),
  missing('Not visible');

  final String label;
  const EvidenceDirection(this.label);
}

/// What an observation rests on (§6: facts vs interpretations vs
/// manufacturer information vs assumptions).
enum EvidenceKind {
  /// What is literally visible, e.g. "four round marks at the corners".
  observedFact('OBSERVED_FACT', 'Directly observed'),

  /// The model's reading of what it saw, e.g. "printed, not real screws".
  aiInterpretation('AI_INTERPRETATION', 'AI interpretation'),

  /// Values the device shows about itself. A clone can display false values.
  deviceReported('DEVICE_REPORTED', 'Device-reported, not verified'),

  /// Confirmed by the manufacturer. Nothing in the app currently produces
  /// this: photographs cannot be verified with a manufacturer.
  manufacturerVerified('MANUFACTURER_VERIFIED', 'Verified with manufacturer'),

  /// A comparison that depends on something not established (e.g. an
  /// unconfirmed generation).
  unverifiedAssumption('UNVERIFIED_ASSUMPTION', 'Unverified assumption');

  final String code;
  final String label;
  const EvidenceKind(this.code, this.label);

  static EvidenceKind parse(String? raw) {
    final s = (raw ?? '').toUpperCase();
    for (final v in values) {
      // Manufacturer verification is never accepted from model output.
      if (v.code == s && v != EvidenceKind.manufacturerVerified) return v;
    }
    if (s.contains('DEVICE')) return EvidenceKind.deviceReported;
    if (s.contains('OBSERV') || s.contains('FACT')) return EvidenceKind.observedFact;
    if (s.contains('ASSUM')) return EvidenceKind.unverifiedAssumption;
    return EvidenceKind.aiInterpretation;
  }
}

/// What the comparison was made against.
enum ReferenceBasis {
  curatedReference('REFERENCE_PROVIDED'),
  modelKnowledge('MODEL_KNOWLEDGE'),
  generalPrinciple('GENERAL_PRINCIPLE'),
  deviceReported('DEVICE_REPORTED');

  final String code;
  const ReferenceBasis(this.code);

  static ReferenceBasis parse(String? raw) {
    final s = (raw ?? '').toUpperCase();
    for (final v in values) {
      if (v.code == s) return v;
    }
    if (s.contains('REFERENCE')) return ReferenceBasis.curatedReference;
    if (s.contains('DEVICE')) return ReferenceBasis.deviceReported;
    if (s.contains('GENERAL')) return ReferenceBasis.generalPrinciple;
    return ReferenceBasis.modelKnowledge;
  }
}

/// Result of checking an unusual feature against legitimate model,
/// regional and manufacturing variations (final evaluation step).
enum VariationCheck {
  notChecked('NOT_CHECKED'),

  /// No legitimate variation explains it.
  ruledOut('RULED_OUT'),

  /// A legitimate variation might explain it.
  possible('POSSIBLE'),

  /// A legitimate variation most likely explains it.
  likely('LIKELY');

  final String code;
  const VariationCheck(this.code);

  static VariationCheck parse(String? raw) {
    final s = (raw ?? '').toUpperCase();
    for (final v in values) {
      if (v.code == s) return v;
    }
    if (s.contains('RULED') || s == 'NONE') return VariationCheck.ruledOut;
    if (s.contains('LIKELY')) return VariationCheck.likely;
    if (s.contains('POSSIBLE')) return VariationCheck.possible;
    return VariationCheck.notChecked;
  }
}

/// One checkpoint as reported by the photo analysis for one photo.
class CheckpointAssessment {
  /// Profile checkpoint id, or "other" for a finding outside the list.
  final String checkpointId;

  /// Short feature name (required for "other").
  final String feature;

  /// What is literally visible.
  final String observation;

  /// What it means compared with the genuine model.
  final String interpretation;

  final CheckpointOutcome outcome;
  final Reliability reliability;
  final String limitation;
  final ReferenceBasis basis;
  final EvidenceKind kind;
  final String? alternativeExplanation;

  const CheckpointAssessment({
    required this.checkpointId,
    required this.feature,
    required this.observation,
    required this.interpretation,
    required this.outcome,
    required this.reliability,
    this.limitation = '',
    this.basis = ReferenceBasis.modelKnowledge,
    this.kind = EvidenceKind.aiInterpretation,
    this.alternativeExplanation,
  });

  /// Throws [FormatException] when the entry is structurally invalid, so a
  /// malformed model response surfaces as an error instead of silently
  /// becoming "no evidence".
  factory CheckpointAssessment.fromJson(Map<String, dynamic> json) {
    final outcome = CheckpointOutcome.tryParse(json['outcome'] as String?);
    if (outcome == null) {
      throw FormatException('assessment without a valid outcome: ${json['outcome']}');
    }
    final id = (json['checkpoint_id'] as String? ?? '').trim();
    if (id.isEmpty) throw const FormatException('assessment without checkpoint_id');
    String clean(dynamic v) {
      final s = v?.toString().trim() ?? '';
      return s.toLowerCase() == 'null' ? '' : s;
    }

    final alt = clean(json['alternative_explanation']);
    return CheckpointAssessment(
      checkpointId: id,
      feature: clean(json['feature']),
      observation: clean(json['observation']),
      interpretation: clean(json['interpretation']),
      outcome: outcome,
      reliability: Reliability.parse(json['reliability'] as String?),
      limitation: clean(json['limitation']),
      basis: ReferenceBasis.parse(json['basis'] as String?),
      kind: EvidenceKind.parse(json['evidence_kind'] as String?),
      alternativeExplanation: alt.isEmpty ? null : alt,
    );
  }

  Map<String, dynamic> toJson() => {
        'checkpoint_id': checkpointId,
        'feature': feature,
        'observation': observation,
        'interpretation': interpretation,
        'outcome': outcome.code,
        'reliability': reliability.code,
        'limitation': limitation,
        'basis': basis.code,
        'evidence_kind': kind.code,
        if (alternativeExplanation != null) 'alternative_explanation': alternativeExplanation,
      };
}

/// Measurable image problems, from the on-device check and the AI check.
class PhotoQualitySummary {
  /// Plain issue codes: BLUR, MOTION_BLUR, GLARE, TOO_DARK, OVEREXPOSED,
  /// LOW_RESOLUTION, TOO_FAR, OUT_OF_FOCUS, OCCLUSION, TEXT_UNREADABLE.
  final List<String> issues;

  /// Whether the requested detail itself (text, engraving, stitching) could
  /// be read. "NA" when the part has no fine detail.
  final String detailReadability;

  /// One sentence telling the user exactly what to change, or empty.
  final String fix;

  /// 0-100, informational only.
  final int score;

  /// 0-100 from the on-device measurements only (focus, exposure, glare,
  /// resolution); 0 = not measured. Used for the report's photo quality.
  final int measuredScore;

  const PhotoQualitySummary({
    this.issues = const [],
    this.detailReadability = 'NA',
    this.fix = '',
    this.score = 0,
    this.measuredScore = 0,
  });

  /// Severe problems measured on the device (see ImageQualityChecker).
  static const severeIssues = {'SEVERE_BLUR', 'MOTION_BLUR', 'SEVERE_GLARE'};

  /// 2 = fine detail unreadable, 1 = partly readable, 0 = fine.
  int get fineDetailPenalty {
    if (detailReadability == 'NOT_READABLE' || issues.any(severeIssues.contains)) return 2;
    if (detailReadability == 'PARTLY_READABLE') return 1;
    return 0;
  }

  bool get hasFineDetailProblem => fineDetailPenalty > 0;

  Map<String, dynamic> toJson() => {
        'issues': issues,
        'detail_readability': detailReadability,
        'fix': fix,
        'score': score,
        if (measuredScore > 0) 'measured_score': measuredScore,
      };

  factory PhotoQualitySummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PhotoQualitySummary();
    return PhotoQualitySummary(
      issues: (json['issues'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      detailReadability: json['detail_readability'] as String? ?? 'NA',
      fix: json['fix'] as String? ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      measuredScore: (json['measured_score'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Everything learned from one accepted photo. Built once per photo and
/// reused for every later evaluation: photos are never re-analysed just
/// because another photo was added.
class PhotoEvidence {
  final String photoId;

  /// The evidence request this photo satisfies (may differ from the one the
  /// user was asked for, when the photo clearly shows another listed part).
  final String requestId;
  final String requestTitle;
  final String imagePath;
  final bool isInitialPhoto;
  final bool keptDespiteLowQuality;
  final PhotoQualitySummary quality;
  final List<CheckpointAssessment> assessments;
  final List<String> observedText;
  final String summary;

  /// Identity information this photo revealed (e.g. an About screen).
  final IdentityAttribute brand;
  final IdentityAttribute modelFamily;
  final IdentityAttribute generation;
  final IdentityAttribute exactModel;

  /// 64-bit difference hash, hex. Used to spot the same picture submitted twice.
  final String imageHash;

  /// Which model produced [assessments], as reported by the backend.
  final String analysisModel;

  /// Normalised [ymin, xmin, ymax, xmax] of the detail the photo check
  /// located (or the item box of the first photo). Used for the in-memory
  /// close-up sent with the final combined analysis.
  final List<double>? detailBox;

  const PhotoEvidence({
    required this.photoId,
    required this.requestId,
    required this.requestTitle,
    required this.imagePath,
    this.isInitialPhoto = false,
    this.keptDespiteLowQuality = false,
    this.quality = const PhotoQualitySummary(),
    this.assessments = const [],
    this.observedText = const [],
    this.summary = '',
    this.brand = IdentityAttribute.unknown,
    this.modelFamily = IdentityAttribute.unknown,
    this.generation = IdentityAttribute.unknown,
    this.exactModel = IdentityAttribute.unknown,
    this.imageHash = '',
    this.analysisModel = '',
    this.detailBox,
  });

  PhotoEvidence copyWith({
    String? requestId,
    String? requestTitle,
    bool? keptDespiteLowQuality,
    List<CheckpointAssessment>? assessments,
    List<String>? observedText,
    String? summary,
    String? analysisModel,
  }) =>
      PhotoEvidence(
        photoId: photoId,
        requestId: requestId ?? this.requestId,
        requestTitle: requestTitle ?? this.requestTitle,
        imagePath: imagePath,
        isInitialPhoto: isInitialPhoto,
        keptDespiteLowQuality: keptDespiteLowQuality ?? this.keptDespiteLowQuality,
        quality: quality,
        assessments: assessments ?? this.assessments,
        observedText: observedText ?? this.observedText,
        summary: summary ?? this.summary,
        brand: brand,
        modelFamily: modelFamily,
        generation: generation,
        exactModel: exactModel,
        imageHash: imageHash,
        analysisModel: analysisModel ?? this.analysisModel,
        detailBox: detailBox,
      );

  Map<String, dynamic> toJson() => {
        'photo_id': photoId,
        'request_id': requestId,
        'request_title': requestTitle,
        'is_initial_photo': isInitialPhoto,
        'kept_despite_low_quality': keptDespiteLowQuality,
        'quality': quality.toJson(),
        'assessments': assessments.map((a) => a.toJson()).toList(),
        'observed_text': observedText,
        'summary': summary,
        'identity': {
          'brand': brand.toJson(),
          'model_family': modelFamily.toJson(),
          'generation': generation.toJson(),
          'exact_model': exactModel.toJson(),
        },
        'image_hash': imageHash,
        'analysis_model': analysisModel,
        if (detailBox != null) 'detail_box': detailBox,
      };
}

/// One observation after the engine applied its rules: the unit reported
/// back to the user (§6).
class EvidenceRecord {
  final String featureId;
  final String featureName;

  /// Independence group. Records in the same group describe the same
  /// underlying feature and never count as corroborating each other.
  final String group;
  final String photoId;
  final String photoTitle;
  final String observation;
  final String interpretation;

  /// The exact product model the observation was compared against.
  final String evaluatedModel;

  /// Human description of the reference used.
  final String referenceSource;
  final EvidenceDirection direction;
  final Reliability reliability;
  final Weight weight;
  final List<String> limitations;
  final EvidenceKind kind;
  final bool corroborated;
  final VariationCheck variation;
  final String? variationNote;
  final String? alternativeExplanation;

  /// Why the engine changed the raw assessment, for the debug log.
  final List<String> engineNotes;

  const EvidenceRecord({
    required this.featureId,
    required this.featureName,
    required this.group,
    required this.photoId,
    required this.photoTitle,
    required this.observation,
    required this.interpretation,
    required this.evaluatedModel,
    required this.referenceSource,
    required this.direction,
    required this.reliability,
    required this.weight,
    this.limitations = const [],
    required this.kind,
    this.corroborated = false,
    this.variation = VariationCheck.notChecked,
    this.variationNote,
    this.alternativeExplanation,
    this.engineNotes = const [],
  });

  EvidenceRecord copyWith({
    EvidenceDirection? direction,
    Reliability? reliability,
    Weight? weight,
    bool? corroborated,
    VariationCheck? variation,
    String? variationNote,
    List<String>? limitations,
    List<String>? engineNotes,
    EvidenceKind? kind,
  }) =>
      EvidenceRecord(
        featureId: featureId,
        featureName: featureName,
        group: group,
        photoId: photoId,
        photoTitle: photoTitle,
        observation: observation,
        interpretation: interpretation,
        evaluatedModel: evaluatedModel,
        referenceSource: referenceSource,
        direction: direction ?? this.direction,
        reliability: reliability ?? this.reliability,
        weight: weight ?? this.weight,
        limitations: limitations ?? this.limitations,
        kind: kind ?? this.kind,
        corroborated: corroborated ?? this.corroborated,
        variation: variation ?? this.variation,
        variationNote: variationNote ?? this.variationNote,
        alternativeExplanation: alternativeExplanation,
        engineNotes: engineNotes ?? this.engineNotes,
      );

  /// One line for lists in the report: what was seen, and what it means.
  String get displayText {
    final obs = observation.trim().replaceAll(RegExp(r'[.\s]+$'), '');
    final meaning = interpretation.trim();
    if (obs.isEmpty) return '$featureName: $meaning';
    if (meaning.isEmpty || meaning.toLowerCase() == obs.toLowerCase()) return '$featureName: $obs.';
    return '$featureName: $obs. $meaning';
  }

  Map<String, dynamic> toJson() => {
        'feature_id': featureId,
        'feature': featureName,
        'group': group,
        'photo_id': photoId,
        'photo': photoTitle,
        'observation': observation,
        'interpretation': interpretation,
        'evaluated_model': evaluatedModel,
        'reference_source': referenceSource,
        'direction': direction.name,
        'reliability': reliability.code,
        'weight': weight.name,
        'limitations': limitations,
        'kind': kind.code,
        'corroborated': corroborated,
        'variation': variation.code,
        if (variationNote != null) 'variation_note': variationNote,
        if (alternativeExplanation != null) 'alternative_explanation': alternativeExplanation,
        if (engineNotes.isNotEmpty) 'engine_notes': engineNotes,
      };

  factory EvidenceRecord.fromJson(Map<String, dynamic> json) {
    EvidenceDirection dir = EvidenceDirection.unclear;
    for (final d in EvidenceDirection.values) {
      if (d.name == json['direction']) dir = d;
    }
    Weight w = Weight.none;
    for (final v in Weight.values) {
      if (v.name == json['weight']) w = v;
    }
    return EvidenceRecord(
      featureId: json['feature_id'] as String? ?? '',
      featureName: json['feature'] as String? ?? '',
      group: json['group'] as String? ?? '',
      photoId: json['photo_id'] as String? ?? '',
      photoTitle: json['photo'] as String? ?? '',
      observation: json['observation'] as String? ?? '',
      interpretation: json['interpretation'] as String? ?? '',
      evaluatedModel: json['evaluated_model'] as String? ?? '',
      referenceSource: json['reference_source'] as String? ?? '',
      direction: dir,
      reliability: Reliability.parse(json['reliability'] as String?),
      weight: w,
      limitations: (json['limitations'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      kind: EvidenceKind.parse(json['kind'] as String?),
      corroborated: json['corroborated'] as bool? ?? false,
      variation: VariationCheck.parse(json['variation'] as String?),
      variationNote: json['variation_note'] as String?,
      alternativeExplanation: json['alternative_explanation'] as String?,
      engineNotes: (json['engine_notes'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}
