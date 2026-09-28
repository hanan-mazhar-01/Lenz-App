import 'capture_guide.dart';
import 'evidence_validation.dart';

enum EvidenceStatus {
  /// Requested but not yet supplied.
  pending('Pending'),
  analyzing('Analyzing...'),

  /// Supplied, validated, awaiting analysis.
  captured('Captured'),
  completed('Completed'),

  /// Post-analysis outcomes.
  consistent('Consistent'),
  suspicious('Suspicious'),
  inconclusive('Inconclusive'),

  /// The user declared they do not have this evidence (§27).
  unavailable("Don't have it"),

  /// The submitted photo showed something else and was refused (§6).
  rejected('Rejected'),

  notProvided('Not Provided');

  final String label;
  const EvidenceStatus(this.label);
}

/// How much a given evidence item matters to the final assessment (§21).
/// Packaging must never weigh as much as a model-specific reference detail.
///
/// [label] is internal. The UI shows [userLabel] / [userHint] instead, because
/// nothing here is mandatory and "Critical" reads like a demand (§18).
enum EvidenceWeight {
  critical('Critical', 1.0, 'Needed', 'Needed for a strong check'),
  high('High', 0.7, 'Needed', 'Needed for a strong check'),
  medium('Medium', 0.45, 'Helpful', 'Helpful if you can'),
  low('Low', 0.2, 'Optional', 'Optional extra');

  final String label;
  final double factor;

  /// Short chip text, e.g. "Needed" / "Helpful".
  final String userLabel;

  /// One-line explanation shown under the title.
  final String userHint;

  const EvidenceWeight(this.label, this.factor, this.userLabel, this.userHint);

  static EvidenceWeight parse(String? raw) {
    final s = (raw ?? '').toLowerCase();
    if (s.contains('critical')) return EvidenceWeight.critical;
    if (s.contains('high')) return EvidenceWeight.high;
    if (s.contains('low')) return EvidenceWeight.low;
    if (s.contains('medium') || s.contains('med')) return EvidenceWeight.medium;
    return EvidenceWeight.medium;
  }
}

class EvidenceItem {
  final String id;
  final int index;
  final String title;
  final String guide;

  /// Why this angle matters for this specific product.
  final String reason;

  /// Requested items are strongly recommended but never mandatory (§4).
  final bool isRequired;
  final EvidenceWeight weight;

  /// Path to the user's own photo. Empty until they supply one.
  final String capturedImagePath;

  /// Illustrative/thumbnail asset. Never stands in for user evidence.
  final String imageAsset;

  final int score;
  final EvidenceStatus status;

  /// Validation record for the accepted photo, if any.
  final EvidenceValidationResult? validation;

  /// Set when the user kept a photo the app flagged as low quality (§50).
  final bool keptDespiteLowQuality;

  final String? whyCorrect;
  final List<String> whatToLookFor;
  final List<String> observations;
  final List<String> consistentSignals;
  final List<String> inconsistentSignals;
  final List<String> uncertainSignals;

  // ------------------------------------------------------------ engine v3
  /// Framing overlay for this photo.
  final CaptureGuideType guideType;

  /// Distance, focus and lighting advice.
  final CaptureTips tips;

  /// Checkpoints this photo can show.
  final List<String> checkpointIds;

  /// HIGH / MEDIUM / LOW: how well this photo separates genuine from
  /// counterfeit for the identified model.
  final String discriminativeValue;

  /// Why the planner recommends this photo now.
  final String recommendationReason;

  /// Model-specific things to look for (AI knowledge, unverified).
  final List<String> aiChecks;

  /// A screenshot is acceptable (device information screens).
  final bool screenshotOk;

  /// 0-100: share of the details checked on this photo that the final
  /// analysis could judge clearly (0 = not measured). Shown as the report's
  /// evidence line; it is not an authenticity score.
  final int clarity;

  const EvidenceItem({
    required this.id,
    required this.index,
    required this.title,
    required this.guide,
    this.reason = '',
    this.isRequired = true,
    this.weight = EvidenceWeight.medium,
    this.capturedImagePath = '',
    this.imageAsset = '',
    this.score = 0,
    this.status = EvidenceStatus.pending,
    this.validation,
    this.keptDespiteLowQuality = false,
    this.whyCorrect,
    this.whatToLookFor = const [],
    this.observations = const [],
    this.consistentSignals = const [],
    this.inconsistentSignals = const [],
    this.uncertainSignals = const [],
    this.guideType = CaptureGuideType.generic,
    this.tips = CaptureTips.standard,
    this.checkpointIds = const [],
    this.discriminativeValue = '',
    this.recommendationReason = '',
    this.aiChecks = const [],
    this.screenshotOk = false,
    this.clarity = 0,
  });

  bool get hasPhoto => capturedImagePath.isNotEmpty;
  bool get isUnavailable => status == EvidenceStatus.unavailable;
  bool get isCritical => weight == EvidenceWeight.critical;

  int get photoQualityScore => validation?.quality.qualityScore ?? 0;
  int get evidenceMatchScore => validation?.matchConfidence ?? 0;
  int get usefulnessScore => validation?.authenticationUsefulness ?? 0;

  /// Display image: the user's own photo wins; the template asset is only a
  /// placeholder for items that were never captured.
  String get displayImage => capturedImagePath.isNotEmpty ? capturedImagePath : imageAsset;

  EvidenceItem copyWith({
    String? id,
    int? index,
    String? title,
    String? guide,
    String? reason,
    bool? isRequired,
    EvidenceWeight? weight,
    String? capturedImagePath,
    String? imageAsset,
    int? score,
    EvidenceStatus? status,
    EvidenceValidationResult? validation,
    bool? keptDespiteLowQuality,
    String? whyCorrect,
    List<String>? whatToLookFor,
    List<String>? observations,
    List<String>? consistentSignals,
    List<String>? inconsistentSignals,
    List<String>? uncertainSignals,
    CaptureGuideType? guideType,
    CaptureTips? tips,
    List<String>? checkpointIds,
    String? discriminativeValue,
    String? recommendationReason,
    List<String>? aiChecks,
    bool? screenshotOk,
    int? clarity,
  }) {
    return EvidenceItem(
      id: id ?? this.id,
      index: index ?? this.index,
      title: title ?? this.title,
      guide: guide ?? this.guide,
      reason: reason ?? this.reason,
      isRequired: isRequired ?? this.isRequired,
      weight: weight ?? this.weight,
      capturedImagePath: capturedImagePath ?? this.capturedImagePath,
      imageAsset: imageAsset ?? this.imageAsset,
      score: score ?? this.score,
      status: status ?? this.status,
      validation: validation ?? this.validation,
      keptDespiteLowQuality: keptDespiteLowQuality ?? this.keptDespiteLowQuality,
      whyCorrect: whyCorrect ?? this.whyCorrect,
      whatToLookFor: whatToLookFor ?? this.whatToLookFor,
      observations: observations ?? this.observations,
      consistentSignals: consistentSignals ?? this.consistentSignals,
      inconsistentSignals: inconsistentSignals ?? this.inconsistentSignals,
      uncertainSignals: uncertainSignals ?? this.uncertainSignals,
      guideType: guideType ?? this.guideType,
      tips: tips ?? this.tips,
      checkpointIds: checkpointIds ?? this.checkpointIds,
      discriminativeValue: discriminativeValue ?? this.discriminativeValue,
      recommendationReason: recommendationReason ?? this.recommendationReason,
      aiChecks: aiChecks ?? this.aiChecks,
      screenshotOk: screenshotOk ?? this.screenshotOk,
      clarity: clarity ?? this.clarity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'index': index,
      'title': title,
      'guide': guide,
      'reason': reason,
      'isRequired': isRequired,
      'weight': weight.name,
      'capturedImagePath': capturedImagePath,
      'imageAsset': imageAsset,
      'score': score,
      'status': status.name,
      'validation': validation?.toJson(),
      'keptDespiteLowQuality': keptDespiteLowQuality,
      'whyCorrect': whyCorrect,
      'whatToLookFor': whatToLookFor,
      'observations': observations,
      'consistentSignals': consistentSignals,
      'inconsistentSignals': inconsistentSignals,
      'uncertainSignals': uncertainSignals,
      'guideType': guideType.name,
      'tips': tips.toJson(),
      'checkpointIds': checkpointIds,
      'discriminativeValue': discriminativeValue,
      'recommendationReason': recommendationReason,
      'aiChecks': aiChecks,
      'screenshotOk': screenshotOk,
      if (clarity > 0) 'clarity': clarity,
    };
  }

  factory EvidenceItem.fromJson(Map<String, dynamic> json) {
    EvidenceStatus stat = EvidenceStatus.pending;
    final statStr = (json['status'] as String?)?.toLowerCase() ?? '';
    for (final s in EvidenceStatus.values) {
      if (s.name.toLowerCase() == statStr || s.label.toLowerCase() == statStr) {
        stat = s;
        break;
      }
    }

    return EvidenceItem(
      id: json['id'] as String? ?? '',
      index: (json['index'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      guide: json['guide'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      isRequired: json['isRequired'] as bool? ?? true,
      weight: EvidenceWeight.parse(json['weight'] as String?),
      capturedImagePath: json['capturedImagePath'] as String? ?? '',
      imageAsset: json['imageAsset'] as String? ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      status: stat,
      validation: json['validation'] is Map
          ? EvidenceValidationResult.fromStoredJson(
              Map<String, dynamic>.from(json['validation'] as Map))
          : null,
      keptDespiteLowQuality: json['keptDespiteLowQuality'] as bool? ?? false,
      whyCorrect: json['whyCorrect'] as String?,
      whatToLookFor: (json['whatToLookFor'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      observations: (json['observations'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      consistentSignals:
          (json['consistentSignals'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      inconsistentSignals:
          (json['inconsistentSignals'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      uncertainSignals:
          (json['uncertainSignals'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      guideType: CaptureGuideType.parse(json['guideType'] as String?),
      tips: CaptureTips.fromJson(json['tips'] is Map ? Map<String, dynamic>.from(json['tips'] as Map) : null),
      checkpointIds: (json['checkpointIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      discriminativeValue: json['discriminativeValue'] as String? ?? '',
      recommendationReason: json['recommendationReason'] as String? ?? '',
      aiChecks: (json['aiChecks'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      screenshotOk: json['screenshotOk'] as bool? ?? false,
      clarity: (json['clarity'] as num?)?.toInt() ?? 0,
    );
  }
}
