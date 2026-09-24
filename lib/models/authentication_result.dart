import 'evidence.dart';
import 'product.dart';

enum Verdict {
  likelyAuthentic('Likely Authentic'),
  likelyReplica('Likely Replica'),
  inconclusive('Inconclusive');

  final String label;
  const Verdict(this.label);
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
    };
  }

  factory AuthenticationReport.fromJson(Map<String, dynamic> json) {
    Verdict v;
    final vStr = (json['verdict'] as String?)?.toLowerCase() ?? '';
    if (vStr.contains('authentic')) {
      v = Verdict.likelyAuthentic;
    } else if (vStr.contains('replica') || vStr.contains('fake')) {
      v = Verdict.likelyReplica;
    } else {
      v = Verdict.inconclusive;
    }

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
    );
  }
}
