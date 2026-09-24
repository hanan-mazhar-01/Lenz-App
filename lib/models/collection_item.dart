import 'authentication_result.dart';
import 'product.dart';

/// An item the user saved from a real report. Every field traces back to that
/// scan — nothing here is estimated or invented (§30, §42).
class CollectionItem {
  final String id;
  final String name;
  final String brand;
  final String model;
  final ProductCategory category;

  /// The user's own photo from the scan.
  final String imageAsset;

  final Verdict verdict;
  final int authenticationConfidence;
  final String evidenceCoverageText;
  final DateTime savedDate;
  final DateTime scannedDate;

  /// The report this was saved from, so the collection can link back to it.
  final String? sourceReportId;

  final String? notes;

  const CollectionItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.category,
    required this.imageAsset,
    required this.verdict,
    required this.authenticationConfidence,
    required this.savedDate,
    required this.scannedDate,
    this.evidenceCoverageText = '',
    this.sourceReportId,
    this.notes,
  });

  factory CollectionItem.fromReport(AuthenticationReport report) {
    return CollectionItem(
      id: 'col_${report.id}',
      name: report.product.name,
      brand: report.product.brand,
      model: report.product.model,
      category: report.product.category,
      imageAsset: report.product.imageAsset,
      verdict: report.verdict,
      authenticationConfidence: report.authenticationConfidence,
      evidenceCoverageText: report.evidenceCoverageText,
      savedDate: DateTime.now(),
      scannedDate: report.timestamp,
      sourceReportId: report.id,
      notes: report.rationale,
    );
  }

  CollectionItem copyWith({
    String? id,
    String? name,
    String? brand,
    String? model,
    ProductCategory? category,
    String? imageAsset,
    Verdict? verdict,
    int? authenticationConfidence,
    String? evidenceCoverageText,
    DateTime? savedDate,
    DateTime? scannedDate,
    String? sourceReportId,
    String? notes,
  }) {
    return CollectionItem(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      category: category ?? this.category,
      imageAsset: imageAsset ?? this.imageAsset,
      verdict: verdict ?? this.verdict,
      authenticationConfidence: authenticationConfidence ?? this.authenticationConfidence,
      evidenceCoverageText: evidenceCoverageText ?? this.evidenceCoverageText,
      savedDate: savedDate ?? this.savedDate,
      scannedDate: scannedDate ?? this.scannedDate,
      sourceReportId: sourceReportId ?? this.sourceReportId,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'model': model,
        'category': category.name,
        'imageAsset': imageAsset,
        'verdict': verdict.name,
        'authenticationConfidence': authenticationConfidence,
        'evidenceCoverageText': evidenceCoverageText,
        'savedDate': savedDate.toIso8601String(),
        'scannedDate': scannedDate.toIso8601String(),
        'sourceReportId': sourceReportId,
        'notes': notes,
      };

  factory CollectionItem.fromJson(Map<String, dynamic> json) {
    ProductCategory cat = ProductCategory.accessories;
    final catStr = (json['category'] as String?)?.toLowerCase() ?? '';
    for (final c in ProductCategory.values) {
      if (c.name.toLowerCase() == catStr || c.label.toLowerCase() == catStr) {
        cat = c;
        break;
      }
    }

    Verdict v = Verdict.inconclusive;
    final vStr = (json['verdict'] as String?)?.toLowerCase() ?? '';
    if (vStr.contains('authentic')) {
      v = Verdict.likelyAuthentic;
    } else if (vStr.contains('replica')) {
      v = Verdict.likelyReplica;
    }

    return CollectionItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      model: json['model'] as String? ?? '',
      category: cat,
      imageAsset: json['imageAsset'] as String? ?? '',
      verdict: v,
      authenticationConfidence: (json['authenticationConfidence'] as num?)?.toInt() ?? 0,
      evidenceCoverageText: json['evidenceCoverageText'] as String? ?? '',
      savedDate: DateTime.tryParse(json['savedDate'] as String? ?? '') ?? DateTime.now(),
      scannedDate: DateTime.tryParse(json['scannedDate'] as String? ?? '') ?? DateTime.now(),
      sourceReportId: json['sourceReportId'] as String?,
      notes: json['notes'] as String?,
    );
  }
}
