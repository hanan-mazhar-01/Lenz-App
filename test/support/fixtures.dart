import 'package:replica_detector/data/evidence_profiles.dart';
import 'package:replica_detector/models/evidence.dart';
import 'package:replica_detector/models/evidence_record.dart';
import 'package:replica_detector/models/evidence_validation.dart';
import 'package:replica_detector/models/photo_quality.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/models/product_identity.dart';

// These are unit-test fixtures: hand-written inputs that exercise specific
// decision rules. They are NOT a dataset and say nothing about accuracy on
// real products.

const testWatch = Product(
  id: 'p_test_watch',
  name: 'Submariner Date',
  brand: 'Rolex',
  model: '126610LN',
  category: ProductCategory.watches,
  imageAsset: '/tmp/primary.jpg',
  identificationConfidence: 0.91,
);

const testBag = Product(
  id: 'p_test_bag',
  name: 'Neverfull MM',
  brand: 'Louis Vuitton',
  model: 'Monogram',
  category: ProductCategory.bags,
  imageAsset: '/tmp/primary.jpg',
  identificationConfidence: 0.87,
);

EvidenceValidationResult validation({
  required String id,
  required String title,
  int quality = 90,
  int match = 95,
  int? usefulness,
  bool matches = true,
  String? detected,
}) {
  return EvidenceValidationResult(
    requestedEvidenceId: id,
    requestedEvidenceTitle: title,
    evidenceTypeDetected: detected ?? title,
    matchToRequestedEvidence: matches,
    matchConfidence: matches ? match : 0,
    quality: PhotoQualityResult(
      qualityScore: quality,
      qualityStatus: PhotoQualityStatus.fromScore(quality),
      explanation: 'fixture',
      sharpness: quality,
      lighting: quality,
      framing: quality,
      detail: quality,
    ),
    usabilityScore: quality,
    authenticationUsefulness: matches ? (usefulness ?? quality) : 0,
    reason: 'fixture',
  );
}

/// One requested angle, optionally already supplied (legacy report shape).
EvidenceItem item({
  required String id,
  required String title,
  EvidenceWeight weight = EvidenceWeight.medium,
  int index = 1,
  bool captured = true,
  int quality = 90,
  bool keptLowQuality = false,
  EvidenceStatus? status,
}) {
  return EvidenceItem(
    id: id,
    index: index,
    title: title,
    guide: 'fixture guide',
    weight: weight,
    isRequired: weight == EvidenceWeight.critical || weight == EvidenceWeight.high,
    capturedImagePath: captured ? '/tmp/$id.jpg' : '',
    status: status ?? (captured ? EvidenceStatus.captured : EvidenceStatus.pending),
    validation: captured ? validation(id: id, title: title, quality: quality) : null,
    keptDespiteLowQuality: keptLowQuality,
  );
}

/// A complete legacy (engine v2) watch checklist, for persistence tests of
/// reports saved before engine v3.
List<EvidenceItem> fullWatchEvidence({int quality = 90}) => [
      item(id: 'full_watch', title: 'Full Watch', weight: EvidenceWeight.high, index: 1, quality: quality),
      item(id: 'dial', title: 'Dial', weight: EvidenceWeight.critical, index: 2, quality: quality),
      item(id: 'crown', title: 'Crown', weight: EvidenceWeight.high, index: 3, quality: quality),
      item(id: 'caseback', title: 'Caseback', weight: EvidenceWeight.high, index: 4, quality: quality),
      item(id: 'bracelet_clasp', title: 'Bracelet & Clasp', weight: EvidenceWeight.medium, index: 5, quality: quality),
      item(id: 'reference_serial', title: 'Reference / Serial', weight: EvidenceWeight.critical, index: 6, quality: quality),
    ];

// ------------------------------------------------------------ engine v3

IdentityAttribute attr(String? value, [AttributeStatus status = AttributeStatus.confirmed, IdentitySource source = IdentitySource.design]) =>
    value == null ? IdentityAttribute.unknown : IdentityAttribute(value: value, status: status, source: source, basis: 'fixture');

ProductIdentity identity({
  String category = 'WATCH',
  String type = '',
  String? brand,
  String? family,
  String? generation,
  AttributeStatus brandStatus = AttributeStatus.confirmed,
  AttributeStatus familyStatus = AttributeStatus.confirmed,
  AttributeStatus generationStatus = AttributeStatus.confirmed,
}) =>
    ProductIdentity(
      categoryCode: category,
      productType: type,
      brand: attr(brand, brandStatus),
      modelFamily: attr(family, familyStatus),
      generation: attr(generation, generationStatus),
    );

ResolvedProfile appleWatch({String? generation = 'Ultra 2', AttributeStatus genStatus = AttributeStatus.confirmed}) =>
    EvidenceProfileRegistry.resolve(identity(
      type: 'smartwatch',
      brand: 'Apple',
      family: 'Apple Watch Ultra',
      generation: generation,
      generationStatus: genStatus,
    ));

ResolvedProfile appleWatchSeries({String? generation = 'Series 9', AttributeStatus genStatus = AttributeStatus.confirmed}) =>
    EvidenceProfileRegistry.resolve(identity(
      type: 'smartwatch',
      brand: 'Apple',
      family: 'Apple Watch Series',
      generation: generation,
      generationStatus: genStatus,
    ));

CheckpointAssessment assess(
  String checkpointId,
  CheckpointOutcome outcome, {
  Reliability reliability = Reliability.high,
  String observation = 'fixture observation',
  String interpretation = 'fixture interpretation',
  String feature = '',
  String? alternative,
  ReferenceBasis basis = ReferenceBasis.modelKnowledge,
  EvidenceKind kind = EvidenceKind.aiInterpretation,
}) =>
    CheckpointAssessment(
      checkpointId: checkpointId,
      feature: feature,
      observation: observation,
      interpretation: interpretation,
      outcome: outcome,
      reliability: reliability,
      basis: basis,
      kind: kind,
      alternativeExplanation: alternative,
    );

PhotoEvidence photo(
  String requestId,
  List<CheckpointAssessment> assessments, {
  String? photoId,
  PhotoQualitySummary quality = const PhotoQualitySummary(detailReadability: 'READABLE'),
  bool kept = false,
  String hash = '',
  bool initial = false,
  IdentityAttribute generation = IdentityAttribute.unknown,
  IdentityAttribute family = IdentityAttribute.unknown,
}) =>
    PhotoEvidence(
      photoId: photoId ?? requestId,
      requestId: requestId,
      requestTitle: requestId.replaceAll('_', ' '),
      imagePath: '/tmp/$requestId.jpg',
      isInitialPhoto: initial,
      keptDespiteLowQuality: kept,
      quality: quality,
      assessments: assessments,
      summary: 'fixture $requestId',
      imageHash: hash,
      generation: generation,
      modelFamily: family,
    );
