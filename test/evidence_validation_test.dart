import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/models/evidence_validation.dart';
import 'package:replica_detector/models/photo_quality.dart';
import 'package:replica_detector/models/product_identification.dart';

void main() {
  EvidenceValidationResult parse(Map<String, dynamic> json) =>
      EvidenceValidationResult.fromJson(json, requestedEvidenceId: 'dial', requestedEvidenceTitle: 'Dial');

  group('Wrong evidence is rejected (§6, §8, §14, §49)', () {
    test('a crown photo submitted for the dial is refused', () {
      final r = parse({
        'evidence_type_detected': 'crown',
        'match_to_requested_evidence': false,
        'match_confidence': 4,
        'photo_quality_score': 94,
        'quality_status': 'EXCELLENT',
        'sharpness': 95,
        'lighting': 93,
        'framing': 92,
        'detail': 94,
        'usability_score': 94,
        'authentication_usefulness': 71,
        'reason': 'The image shows the winding crown.',
      });

      expect(r.verdict, EvidenceVerdict.rejectedWrongEvidence);
      expect(r.isAccepted, isFalse);
      expect(r.quality.qualityScore, 94, reason: 'Photo quality is judged independently');
      expect(r.quality.qualityStatus, PhotoQualityStatus.excellent);
      expect(r.authenticationUsefulness, 0,
          reason: 'Usefulness must be zeroed for the requested check (§14)');
      expect(r.headline, "That's a different part");
      expect(r.guidance, 'This photo shows the crown, but we need the dial.');
      expect(r.callToAction, 'We need a clear photo of the dial.');
      expect(r.usefulnessLabel, 'Not useful here');
    });

    test('a wrong-subject photo can never be forced in (§28)', () {
      final r = parse({
        'evidence_type_detected': 'box label',
        'match_to_requested_evidence': false,
        'photo_quality_score': 99,
      });
      expect(r.isOverridable, isFalse);
    });

    test('a low match confidence is treated as a mismatch even if the flag says true', () {
      final r = parse({
        'evidence_type_detected': 'dial, partially obscured',
        'match_to_requested_evidence': true,
        'match_confidence': 22,
        'photo_quality_score': 80,
      });
      expect(r.verdict, EvidenceVerdict.rejectedWrongEvidence);
    });
  });

  group('Poor quality is rejected but overridable (§50)', () {
    test('a blurry photo of the right area asks for a retake', () {
      final r = parse({
        'evidence_type_detected': 'dial',
        'match_to_requested_evidence': true,
        'match_confidence': 88,
        'photo_quality_score': 24,
        'quality_status': 'POOR',
        'sharpness': 15,
        'lighting': 40,
        'framing': 60,
        'detail': 20,
        'usability_score': 25,
        'authentication_usefulness': 18,
      });

      expect(r.verdict, EvidenceVerdict.rejectedQuality);
      expect(r.isOverridable, isTrue, reason: 'The user may keep it, flagged low quality');
      expect(r.quality.isBlurry, isTrue);
      expect(r.headline, 'Too blurry');
      expect(r.guidance, "It's too blurry to check properly.");
      expect(r.callToAction, 'Hold steady and try again.');
    });

    test('a dark photo is identified as such', () {
      final r = parse({
        'evidence_type_detected': 'dial',
        'match_to_requested_evidence': true,
        'match_confidence': 80,
        'photo_quality_score': 30,
        'sharpness': 70,
        'lighting': 12,
        'framing': 65,
        'detail': 30,
        'usability_score': 30,
      });
      expect(r.quality.isTooDark, isTrue);
      expect(r.headline, 'Too dark');
      expect(r.quality.firstFix, 'Too dark');
    });
  });

  group('Accepted photos (§13)', () {
    test('a good dial photo passes with all three metrics reported', () {
      final r = parse({
        'evidence_type_detected': 'dial',
        'match_to_requested_evidence': true,
        'match_confidence': 98,
        'photo_quality_score': 92,
        'quality_status': 'EXCELLENT',
        'sharpness': 94,
        'lighting': 88,
        'framing': 93,
        'detail': 90,
        'usability_score': 93,
        'authentication_usefulness': 91,
        'reason': 'Clear and well-framed.',
      });

      expect(r.verdict, EvidenceVerdict.accepted);
      expect(r.quality.qualityScore, 92);
      expect(r.matchConfidence, 98);
      expect(r.authenticationUsefulness, 91);
      expect(r.headline, 'Great photo');
      expect(r.usefulnessLabel, 'Very useful');
      expect(r.usefulnessExplanation, 'Clear photo with useful detail.');
    });
  });

  group('Quality parsing never invents numbers (§11)', () {
    test('missing roll-up is derived from sub-scores, not guessed', () {
      final q = PhotoQualityResult.fromJson({
        'sharpness': 80,
        'lighting': 60,
        'framing': 70,
        'detail': 50,
      });
      expect(q.qualityScore, 65);
      expect(q.qualityStatus, PhotoQualityStatus.needsImprovement);
    });

    test('an empty response yields zero, not a flattering default', () {
      final q = PhotoQualityResult.fromJson({});
      expect(q.qualityScore, 0);
      expect(q.qualityStatus, PhotoQualityStatus.poor);
    });

    test('status thresholds map to the four published tiers', () {
      expect(PhotoQualityStatus.fromScore(91), PhotoQualityStatus.excellent);
      expect(PhotoQualityStatus.fromScore(78), PhotoQualityStatus.good);
      expect(PhotoQualityStatus.fromScore(51), PhotoQualityStatus.needsImprovement);
      expect(PhotoQualityStatus.fromScore(28), PhotoQualityStatus.poor);
    });

    test('0-1 scaled scores are normalised', () {
      final q = PhotoQualityResult.fromJson({'photo_quality_score': 0.86, 'sharpness': 0.9});
      expect(q.qualityScore, 86);
      expect(q.sharpness, 90);
    });
  });

  group('Round-trips survive persistence', () {
    test('validation survives a JSON round trip', () {
      final original = parse({
        'evidence_type_detected': 'dial',
        'match_to_requested_evidence': true,
        'match_confidence': 93,
        'photo_quality_score': 88,
        'sharpness': 90,
        'lighting': 85,
        'framing': 88,
        'detail': 89,
        'usability_score': 90,
        'authentication_usefulness': 87,
        'reason': 'Sharp and centred.',
        'issues': ['slight glare at 3 oclock'],
      });

      final restored = EvidenceValidationResult.fromStoredJson(original.toJson());

      expect(restored.matchConfidence, 93);
      expect(restored.authenticationUsefulness, 87);
      expect(restored.quality.qualityScore, 88);
      expect(restored.quality.sharpness, 90);
      expect(restored.issues, ['slight glare at 3 oclock']);
      expect(restored.verdict, EvidenceVerdict.accepted);
    });
  });

  group('Identification never claims certainty (§24)', () {
    test('a 1.0 confidence is capped below absolute', () {
      final id = ProductIdentification.fromJson({
        'category': 'Watches',
        'brand': 'Apple',
        'product': 'Apple Watch Ultra',
        'identification_confidence': 1.0,
      });
      expect(id.identificationConfidence, lessThan(1.0));
      expect((id.identificationConfidence * 100).round(), 99);
    });

    test('a 100 (percent-scaled) confidence is normalised and capped', () {
      final id = ProductIdentification.fromJson({
        'category': 'Bags',
        'brand': 'Louis Vuitton',
        'product': 'Neverfull',
        'identification_confidence': 100,
      });
      expect((id.identificationConfidence * 100).round(), 99);
    });

    test('an unidentifiable item is not upgraded into a guess', () {
      final id = ProductIdentification.fromJson({
        'category': 'Unknown',
        'brand': 'Unknown',
        'product': 'Unknown',
        'identification_confidence': 0.1,
      });
      expect(id.isIdentified, isFalse);
    });
  });
}
