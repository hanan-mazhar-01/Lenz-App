import 'package:replica_detector/models/evidence.dart';
import 'package:replica_detector/models/evidence_observation.dart';
import 'package:replica_detector/models/evidence_validation.dart';
import 'package:replica_detector/models/photo_quality.dart';
import 'package:replica_detector/models/product.dart';

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

/// One requested angle, optionally already supplied.
EvidenceItem item({
  required String id,
  required String title,
  required EvidenceWeight weight,
  int index = 1,
  bool captured = true,
  int quality = 90,
  bool keptLowQuality = false,
  bool unavailable = false,
}) {
  return EvidenceItem(
    id: id,
    index: index,
    title: title,
    guide: 'Capture the $title.',
    reason: 'Needed to verify the $title.',
    isRequired: weight == EvidenceWeight.critical || weight == EvidenceWeight.high,
    weight: weight,
    capturedImagePath: captured ? '/tmp/$id.jpg' : '',
    status: unavailable
        ? EvidenceStatus.unavailable
        : captured
            ? EvidenceStatus.captured
            : EvidenceStatus.pending,
    keptDespiteLowQuality: keptLowQuality,
    validation: captured ? validation(id: id, title: title, quality: quality) : null,
  );
}

PartObservation observation({
  required String id,
  required String title,
  List<String> consistent = const [],
  List<String> inconsistent = const [],
  List<String> uncertain = const [],
  int quality = 90,
}) {
  return PartObservation(
    evidenceId: id,
    title: title,
    observations: ['observed $title'],
    consistentSignals: consistent,
    inconsistentSignals: inconsistent,
    uncertainSignals: uncertain,
    visibleQuality: quality,
  );
}

Map<String, String> imagesFor(List<EvidenceItem> items) => {
      for (final i in items)
        if (i.capturedImagePath.isNotEmpty) i.id: i.capturedImagePath,
    };

/// A full, clean six-angle watch submission.
List<EvidenceItem> fullWatchEvidence({int quality = 90}) => [
      item(id: 'full_watch', title: 'Full Watch', weight: EvidenceWeight.high, index: 1, quality: quality),
      item(id: 'dial', title: 'Dial', weight: EvidenceWeight.critical, index: 2, quality: quality),
      item(id: 'crown', title: 'Crown', weight: EvidenceWeight.high, index: 3, quality: quality),
      item(id: 'caseback', title: 'Caseback', weight: EvidenceWeight.high, index: 4, quality: quality),
      item(id: 'bracelet_clasp', title: 'Bracelet & Clasp', weight: EvidenceWeight.medium, index: 5, quality: quality),
      item(id: 'reference_serial', title: 'Reference / Serial', weight: EvidenceWeight.critical, index: 6, quality: quality),
    ];

List<PartObservation> cleanWatchObservations() => [
      observation(id: 'full_watch', title: 'Full Watch', consistent: ['Case proportions match the reference', 'Bracelet sits flush to the lugs']),
      observation(id: 'dial', title: 'Dial', consistent: ['Dial printing is sharp with even kerning', 'Lume fills the markers evenly']),
      observation(id: 'crown', title: 'Crown', consistent: ['Crown knurling is cleanly machined']),
      observation(id: 'caseback', title: 'Caseback', consistent: ['Caseback is unengraved with uniform brushing']),
      observation(id: 'bracelet_clasp', title: 'Bracelet & Clasp', consistent: ['Clasp stamping is crisp']),
      observation(id: 'reference_serial', title: 'Reference / Serial', consistent: ['Serial format matches the model', 'Etch depth is consistent']),
    ];
