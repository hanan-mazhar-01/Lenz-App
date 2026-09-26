import 'evidence.dart';
import 'product.dart';

/// Internal classification. [code] is the engine's enum value; [label] is
/// the user-facing wording.
enum Verdict {
  likelyAuthentic('Appears Authentic', 'LIKELY_AUTHENTIC'),
  likelyReplica('Likely Replica', 'LIKELY_REPLICA'),
  inconclusive('Unable to Verify', 'INCONCLUSIVE');

  final String label;
  final String code;
  const Verdict(this.label, this.code);

  static Verdict parse(String? raw) {
    final s = (raw ?? '').toLowerCase();
    if (s.contains('authentic')) return Verdict.likelyAuthentic;
    if (s.contains('replica') || s.contains('fake')) return Verdict.likelyReplica;
    return Verdict.inconclusive;
  }
}

/// How this scan relates to earlier scans of the same product (§17-19).
class ConsistencyInfo {
  /// The verdict the engine produced from this scan's evidence alone.
  final Verdict rawVerdict;
  final int rawConfidence;

  final String? previousReportId;
  final Verdict? previousVerdict;
  final int? previousConfidence;

  /// True when this scan's raw verdict was held back because it contradicted
  /// a stable earlier result without new strong evidence.
  final bool flipPrevented;

  /// Aggregate across every matched scan, including this one.
  final Verdict? sessionVerdict;
  final int sessionScanCount;
  final String note;

  const ConsistencyInfo({
    required this.rawVerdict,
    required this.rawConfidence,
    this.previousReportId,
    this.previousVerdict,
    this.previousConfidence,
    this.flipPrevented = false,
    this.sessionVerdict,
    this.sessionScanCount = 1,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'rawVerdict': rawVerdict.name,
        'rawConfidence': rawConfidence,
        if (previousReportId != null) 'previousReportId': previousReportId,
        if (previousVerdict != null) 'previousVerdict': previousVerdict!.name,
        if (previousConfidence != null) 'previousConfidence': previousConfidence,
        'flipPrevented': flipPrevented,
        if (sessionVerdict != null) 'sessionVerdict': sessionVerdict!.name,
        'sessionScanCount': sessionScanCount,
        'note': note,
      };

  factory ConsistencyInfo.fromJson(Map<String, dynamic> json) => ConsistencyInfo(
        rawVerdict: Verdict.parse(json['rawVerdict'] as String?),
        rawConfidence: (json['rawConfidence'] as num?)?.toInt() ?? 0,
        previousReportId: json['previousReportId'] as String?,
        previousVerdict: json['previousVerdict'] == null ? null : Verdict.parse(json['previousVerdict'] as String?),
        previousConfidence: (json['previousConfidence'] as num?)?.toInt(),
        flipPrevented: json['flipPrevented'] as bool? ?? false,
        sessionVerdict: json['sessionVerdict'] == null ? null : Verdict.parse(json['sessionVerdict'] as String?),
        sessionScanCount: (json['sessionScanCount'] as num?)?.toInt() ?? 1,
        note: json['note'] as String? ?? '',
      );
}

/// A product-specific physical check the user can perform in person (§36).
class PhysicalCheck {
  final String title;
  final String description;
  final String whatToLookFor;

  const PhysicalCheck({
    required this.title,
    required this.description,
    required this.whatToLookFor,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'what_to_look_for': whatToLookFor,
      };

  factory PhysicalCheck.fromJson(Map<String, dynamic> json) => PhysicalCheck(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        whatToLookFor: json['what_to_look_for'] as String? ?? '',
      );
}

class AuthenticationReport {
  final String id;
  final Product product;
  final Verdict verdict;

  /// Alias retained for existing call sites; equals [authenticationConfidence].
  final int overallScore;

  /// "What product does this look like?" — independent of authenticity.
  final int identificationConfidence;

  /// "How strongly does the available evidence support this assessment?" (§25)
  final int authenticationConfidence;

  final String evidenceCoverageText;
  final int coveredEvidenceCount;
  final int totalEvidenceCount;

  final List<String> quickSummaryPoints;

  /// §37 — the four evidence buckets plus the follow-up.
  final List<String> positiveFindings;
  final List<String> suspiciousFindings;
  final List<String> unclearFindings;
  final List<String> missingEvidence;
  final List<String> contradictions;
  final List<String> nextChecks;

  final List<PhysicalCheck> physicalChecks;
  final List<EvidenceItem> evidenceItems;
  final String rationale;
  final DateTime timestamp;
  final bool isFavorite;

  // ------------------------------------------------------------ engine v2
  /// 0-100: how well the photos let anyone inspect the item.
  final int imageQualityScore;

  /// 0-100: confidence in the analysis itself. Separate from
  /// [authenticationConfidence], which is how strongly the evidence
  /// supports the verdict.
  final int analysisConfidence;

  final bool needsMoreImages;
  final List<String> recommendedViews;
  final List<String> limitations;

  /// Serial/model text read off the item. Observed text only, never
  /// validated against a brand database.
  final List<String> observedText;

  /// Semantic product fingerprint used to recognise repeat scans.
  final String? fingerprint;
  final ConsistencyInfo? consistency;

  final String engineVersion;
  final String promptVersion;

  /// Debug record of the analysis (§34). No personal data.
  final Map<String, dynamic> analysisLog;

  const AuthenticationReport({
    required this.id,
    required this.product,
    required this.verdict,
    required this.overallScore,
    this.identificationConfidence = 0,
    int? authenticationConfidence,
    this.evidenceCoverageText = '',
    this.coveredEvidenceCount = 0,
    this.totalEvidenceCount = 0,
    required this.quickSummaryPoints,
    this.positiveFindings = const [],
    this.suspiciousFindings = const [],
    this.unclearFindings = const [],
    this.missingEvidence = const [],
    this.contradictions = const [],
    this.nextChecks = const [],
    this.physicalChecks = const [],
    required this.evidenceItems,
    required this.rationale,
    required this.timestamp,
    this.isFavorite = false,
    this.imageQualityScore = 0,
    this.analysisConfidence = 0,
    this.needsMoreImages = false,
    this.recommendedViews = const [],
    this.limitations = const [],
    this.observedText = const [],
    this.fingerprint,
    this.consistency,
    this.engineVersion = '1.0',
    this.promptVersion = '1.0',
    this.analysisLog = const {},
  }) : authenticationConfidence = authenticationConfidence ?? overallScore;

  /// Evidence items the user actually supplied and the app accepted.
  List<EvidenceItem> get acceptedEvidence => evidenceItems.where((e) => e.hasPhoto).toList();

  AuthenticationReport copyWith({
    String? id,
    Product? product,
    Verdict? verdict,
    int? overallScore,
    int? identificationConfidence,
    int? authenticationConfidence,
    String? evidenceCoverageText,
    int? coveredEvidenceCount,
    int? totalEvidenceCount,
    List<String>? quickSummaryPoints,
    List<String>? positiveFindings,
    List<String>? suspiciousFindings,
    List<String>? unclearFindings,
    List<String>? missingEvidence,
    List<String>? contradictions,
    List<String>? nextChecks,
    List<PhysicalCheck>? physicalChecks,
    List<EvidenceItem>? evidenceItems,
    String? rationale,
    DateTime? timestamp,
    bool? isFavorite,
    int? imageQualityScore,
    int? analysisConfidence,
    bool? needsMoreImages,
    List<String>? recommendedViews,
    List<String>? limitations,
    List<String>? observedText,
    String? fingerprint,
    ConsistencyInfo? consistency,
    String? engineVersion,
    String? promptVersion,
    Map<String, dynamic>? analysisLog,
  }) {
    return AuthenticationReport(
      id: id ?? this.id,
      product: product ?? this.product,
      verdict: verdict ?? this.verdict,
      overallScore: overallScore ?? this.overallScore,
      identificationConfidence: identificationConfidence ?? this.identificationConfidence,
      authenticationConfidence: authenticationConfidence ?? this.authenticationConfidence,
      evidenceCoverageText: evidenceCoverageText ?? this.evidenceCoverageText,
      coveredEvidenceCount: coveredEvidenceCount ?? this.coveredEvidenceCount,
      totalEvidenceCount: totalEvidenceCount ?? this.totalEvidenceCount,
      quickSummaryPoints: quickSummaryPoints ?? this.quickSummaryPoints,
      positiveFindings: positiveFindings ?? this.positiveFindings,
      suspiciousFindings: suspiciousFindings ?? this.suspiciousFindings,
      unclearFindings: unclearFindings ?? this.unclearFindings,
      missingEvidence: missingEvidence ?? this.missingEvidence,
      contradictions: contradictions ?? this.contradictions,
      nextChecks: nextChecks ?? this.nextChecks,
      physicalChecks: physicalChecks ?? this.physicalChecks,
      evidenceItems: evidenceItems ?? this.evidenceItems,
      rationale: rationale ?? this.rationale,
      timestamp: timestamp ?? this.timestamp,
      isFavorite: isFavorite ?? this.isFavorite,
      imageQualityScore: imageQualityScore ?? this.imageQualityScore,
      analysisConfidence: analysisConfidence ?? this.analysisConfidence,
      needsMoreImages: needsMoreImages ?? this.needsMoreImages,
      recommendedViews: recommendedViews ?? this.recommendedViews,
      limitations: limitations ?? this.limitations,
      observedText: observedText ?? this.observedText,
      fingerprint: fingerprint ?? this.fingerprint,
      consistency: consistency ?? this.consistency,
      engineVersion: engineVersion ?? this.engineVersion,
      promptVersion: promptVersion ?? this.promptVersion,
      analysisLog: analysisLog ?? this.analysisLog,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product': product.toJson(),
      'verdict': verdict.name,
      'overallScore': overallScore,
      'identificationConfidence': identificationConfidence,
      'authenticationConfidence': authenticationConfidence,
      'evidenceCoverageText': evidenceCoverageText,
      'coveredEvidenceCount': coveredEvidenceCount,
      'totalEvidenceCount': totalEvidenceCount,
      'quickSummaryPoints': quickSummaryPoints,
      'positiveFindings': positiveFindings,
      'suspiciousFindings': suspiciousFindings,
      'unclearFindings': unclearFindings,
      'missingEvidence': missingEvidence,
      'contradictions': contradictions,
      'nextChecks': nextChecks,
      'physicalChecks': physicalChecks.map((c) => c.toJson()).toList(),
      'evidenceItems': evidenceItems.map((e) => e.toJson()).toList(),
      'rationale': rationale,
      'timestamp': timestamp.toIso8601String(),
      'isFavorite': isFavorite,
      'imageQualityScore': imageQualityScore,
      'analysisConfidence': analysisConfidence,
      'needsMoreImages': needsMoreImages,
      'recommendedViews': recommendedViews,
      'limitations': limitations,
      'observedText': observedText,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (consistency != null) 'consistency': consistency!.toJson(),
      'engineVersion': engineVersion,
      'promptVersion': promptVersion,
      'analysisLog': analysisLog,
    };
  }

  factory AuthenticationReport.fromJson(Map<String, dynamic> json) {
    final v = Verdict.parse(json['verdict'] as String?);

    List<String> strings(String key) =>
        (json[key] as List?)?.map((e) => e.toString()).toList() ?? const [];

    final authConf = (json['authenticationConfidence'] as num?)?.toInt() ??
        (json['overallScore'] as num?)?.toInt() ??
        0;

    return AuthenticationReport(
      id: json['id'] as String? ?? 'rep_${DateTime.now().millisecondsSinceEpoch}',
      product: Product.fromJson(Map<String, dynamic>.from(json['product'] as Map? ?? {})),
      verdict: v,
      overallScore: authConf,
      identificationConfidence: (json['identificationConfidence'] as num?)?.toInt() ?? 0,
      authenticationConfidence: authConf,
      evidenceCoverageText: json['evidenceCoverageText'] as String? ?? '',
      coveredEvidenceCount: (json['coveredEvidenceCount'] as num?)?.toInt() ?? 0,
      totalEvidenceCount: (json['totalEvidenceCount'] as num?)?.toInt() ?? 0,
      quickSummaryPoints: strings('quickSummaryPoints'),
      positiveFindings: strings('positiveFindings'),
      suspiciousFindings: strings('suspiciousFindings'),
      unclearFindings: strings('unclearFindings'),
      missingEvidence: strings('missingEvidence'),
      contradictions: strings('contradictions'),
      nextChecks: strings('nextChecks'),
      physicalChecks: (json['physicalChecks'] as List?)
              ?.map((c) => PhysicalCheck.fromJson(Map<String, dynamic>.from(c as Map)))
              .toList() ??
          const [],
      evidenceItems: (json['evidenceItems'] as List?)
              ?.map((e) => EvidenceItem.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      rationale: json['rationale'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      isFavorite: json['isFavorite'] as bool? ?? false,
      imageQualityScore: (json['imageQualityScore'] as num?)?.toInt() ?? 0,
      analysisConfidence: (json['analysisConfidence'] as num?)?.toInt() ?? 0,
      needsMoreImages: json['needsMoreImages'] as bool? ?? false,
      recommendedViews: strings('recommendedViews'),
      limitations: strings('limitations'),
      observedText: strings('observedText'),
      fingerprint: json['fingerprint'] as String?,
      consistency: json['consistency'] is Map
          ? ConsistencyInfo.fromJson(Map<String, dynamic>.from(json['consistency'] as Map))
          : null,
      engineVersion: json['engineVersion'] as String? ?? '1.0',
      promptVersion: json['promptVersion'] as String? ?? '1.0',
      analysisLog: json['analysisLog'] is Map ? Map<String, dynamic>.from(json['analysisLog'] as Map) : const {},
    );
  }
}
