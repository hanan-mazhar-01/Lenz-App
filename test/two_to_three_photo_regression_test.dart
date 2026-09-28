import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/data/evidence_profiles.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/evidence_record.dart';
import 'package:replica_detector/models/product_reference.dart';
import 'package:replica_detector/services/evidence_decision_engine.dart';
import 'package:replica_detector/services/final_verdict_validator.dart';

import 'support/fake_gemini.dart';
import 'support/fixtures.dart';

/// Comprehensive regression tests for 2-3 photo analysis and verdict restrictions
/// covering all requirements in Section 10 of the specification:
/// 1. Genuine products with 2–3 informative photographs.
/// 2. Replica products with 2–3 informative photographs.
/// 3. Genuine products with 5–6 photographs.
/// 4. High-quality counterfeits with convincing external appearance.
/// 5. Missing device-information photographs.
/// 6. Different generations of the same model.
/// 7. Blurry and partially obscured photographs.
/// 8. Contradictory findings.
/// 9. Incorrect evidence-ID mapping.
/// 10. Gemini and validation-engine disagreements.
/// 11. Privacy-safe diagnostics verification.
void main() {
  final profile = appleWatch();
  final checklist = ProductReference.checklist(profile);

  final threePhotos = [
    photo('overview', const [], initial: true),
    photo('back_sensor', const []),
    photo('side_crown', const []),
  ];

  const images3 = {
    'P1': 'overview',
    'P2': 'back_sensor',
    'P3': 'side_crown',
    'C1': 'back_sensor',
  };

  CombinedAnalysis parse(
    Map<String, dynamic> json, {
    Map<String, String> imageMap = images3,
    ProductReference? list,
    ResolvedProfile? prof,
  }) =>
      CombinedAnalysis.parse(
        json,
        imageToPhoto: imageMap,
        claimIds: {for (final c in (list ?? checklist).claims) ...[c.id, if (c.checkpointId != null) c.checkpointId!]},
        requestIds: {for (final r in (prof ?? profile).profile.requests) r.id},
      );

  EngineResult run(
    Map<String, dynamic> json, {
    List<PhotoEvidence>? ps,
    ResolvedProfile? prof,
    Map<String, String>? imageMap,
    EngineResult? preliminary,
  }) {
    final activeProf = prof ?? profile;
    final activeList = prof == null ? checklist : ProductReference.checklist(prof);
    final activePhotos = ps ?? threePhotos;
    final activeImages = imageMap ?? {for (var i = 0; i < activePhotos.length; i++) 'P${i + 1}': activePhotos[i].photoId};
    return FinalVerdictValidator.validate(
      profile: activeProf,
      photos: activePhotos,
      checklist: activeList,
      analysis: parse(json, imageMap: activeImages, list: activeList, prof: activeProf),
      preliminary: preliminary,
    );
  }

  group('1. Genuine products with 2-3 informative photographs', () {
    test('Apple Watch with 3 informative photos (overview, back sensor, crown) authenticates', () {
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'front display', part: 'front_display'),
        findingJson('none', 'MATCHES', images: ['P2'], area: 'back sensor', part: 'back_sensor', detailKind: 'MATERIAL', hard: true),
        findingJson('none', 'MATCHES', images: ['P3'], area: 'digital crown', part: 'crown_side'),
      ];

      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: findings));
      expect(r.verdict, Verdict.likelyAuthentic);
      expect(r.authenticGroups, containsAll(['front_display', 'back_sensor', 'crown_side']));
      expect(r.hardToCopyGroups, contains('back_sensor'));
      expect(r.diagnostics['validation_result'], 'agreed');
      expect(r.diagnostics['submitted_photos_count'], 3);
    });

    test('2 clear photos showing 3 independent features authenticates', () {
      final twoPhotos = [
        photo('overview', const [], initial: true),
        photo('back_sensor', const []),
      ];
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'front display', part: 'front_display'),
        findingJson('none', 'MATCHES', images: ['P1'], area: 'digital crown', part: 'crown_side'),
        findingJson('none', 'MATCHES', images: ['P2'], area: 'back sensor', part: 'back_sensor', detailKind: 'MATERIAL', hard: true),
      ];

      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: findings), ps: twoPhotos);
      expect(r.verdict, Verdict.likelyAuthentic);
      expect(r.authenticGroups.length, 3);
      expect(r.diagnostics['submitted_photos_count'], 2);
    });

    test('2 photos showing the same detail does NOT count as independent evidence', () {
      final twoPhotos = [
        photo('overview', const [], initial: true),
        photo('front_closeup', const []),
      ];
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'front display', part: 'front_display'),
        findingJson('none', 'MATCHES', images: ['P2'], area: 'display edge', part: 'front_display'),
      ];

      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: findings), ps: twoPhotos);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.authenticGroups, {'front_display'});
      expect(r.gaps.any((g) => g.description.contains('more independent detail')), isTrue);
    });
  });

  group('2. Replica products with 2-3 informative photographs', () {
    test('decisive material mismatch on back sensor gives Replica from 2 photos', () {
      final twoPhotos = [
        photo('overview', const [], initial: true),
        photo('back_sensor', const []),
      ];
      final backMaterial = checklist.claims.firstWhere((c) => c.checkpointId == 'aw_back_material');
      final findings = [
        findingJson(backMaterial.id, 'CONFLICTS', images: ['P2'], part: 'back_sensor', variation: 'RULED_OUT', observed: 'Light cream plastic back plate.'),
      ];

      final r = run(combinedJson(verdict: 'REPLICA', findings: findings), ps: twoPhotos);
      expect(r.verdict, Verdict.likelyReplica);
      expect(r.decisiveCount, 1);
      expect(r.strength, EvidenceStrength.strong);
      expect(r.diagnostics['final_verdict'], 'LIKELY_REPLICA');
    });

    test('two independent model-knowledge discrepancies give Replica from 3 photos', () {
      final findings = [
        findingJson('none', 'CONFLICTS', images: ['P1'], part: 'front_display', variation: 'RULED_OUT', observed: 'Oversized bezels.'),
        findingJson('none', 'CONFLICTS', images: ['P3'], part: 'crown_side', variation: 'RULED_OUT', observed: 'Coarse plastic crown ridges.'),
      ];

      final r = run(combinedJson(verdict: 'REPLICA', findings: findings));
      expect(r.verdict, Verdict.likelyReplica);
      expect(r.counterfeitGroups.length, 2);
    });
  });

  group('3. Genuine products with 5-6 photographs', () {
    test('full 6-photo scan with comprehensive matches gives strong Authentic', () {
      final sixPhotos = [
        photo('overview', const [], initial: true),
        photo('back_sensor', const []),
        photo('device_info', const []),
        photo('crown_side', const []),
        photo('front_display', const []),
        photo('band_slot', const []),
      ];
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'front display', part: 'front_display'),
        findingJson('none', 'MATCHES', images: ['P2'], area: 'back sensor', part: 'back_sensor', detailKind: 'MATERIAL', hard: true),
        findingJson('none', 'MATCHES', images: ['P3'], area: 'device info', part: 'device_info', detailKind: 'SOFTWARE'),
        findingJson('none', 'MATCHES', images: ['P4'], area: 'crown machining', part: 'crown_side', detailKind: 'CONSTRUCTION', hard: true),
        findingJson('none', 'MATCHES', images: ['P6'], area: 'band slot', part: 'band_slot'),
      ];

      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: findings), ps: sixPhotos);
      expect(r.verdict, Verdict.likelyAuthentic);
      expect(r.strength, EvidenceStrength.strong);
      expect(r.authenticGroups.length, greaterThanOrEqualTo(4));
    });
  });

  group('4. High-quality counterfeits with convincing external appearance', () {
    test('convincing logo and appearance without hard-to-copy feature remains Inconclusive when Gemini is not sure', () {
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'case finish', part: 'front_display', detailKind: 'CONSTRUCTION'),
        findingJson('none', 'MATCHES', images: ['P2'], area: 'back engraving', part: 'back_sensor', detailKind: 'MARKING', hard: false),
        findingJson('none', 'MATCHES', images: ['P3'], area: 'crown logo', part: 'crown_side', detailKind: 'MARKING', hard: false),
      ];

      final r = run(combinedJson(
        verdict: 'NOT_SURE',
        findings: findings,
        unresolved: [
          {'issue': 'Internal hardware and sensor lenses could not be verified.', 'resolving_photo': 'back_sensor', 'resolving_check': null},
        ],
      ));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.hardToCopyGroups, isEmpty);
      expect(r.remainingUncertainty.any((u) => u.contains('Internal hardware')), isTrue);
    });

    test('high quality counterfeit with subtle sensor discrepancy identified as replica', () {
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'case finish', part: 'front_display'),
        findingJson('none', 'MATCHES', images: ['P3'], area: 'crown machining', part: 'crown_side'),
        findingJson('none', 'CONFLICTS', images: ['P2'], part: 'back_sensor', variation: 'RULED_OUT', observed: 'Photodiode window layout inverted.'),
        findingJson('none', 'CONFLICTS', images: ['P1'], part: 'front_display', variation: 'RULED_OUT', observed: 'Display chin border 2mm wider than genuine.'),
      ];

      final r = run(combinedJson(verdict: 'REPLICA', findings: findings));
      expect(r.verdict, Verdict.likelyReplica);
    });
  });

  group('5. Missing device-information photographs', () {
    test('does NOT block Apple Watch from authenticating when hardware evidence is complete', () {
      final hardwareOnlyPhotos = [
        photo('overview', const [], initial: true),
        photo('back_sensor', const []),
        photo('side_crown', const []),
      ];
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'case and crystal', part: 'front_display'),
        findingJson('none', 'MATCHES', images: ['P2'], area: 'ceramic sensor cluster', part: 'back_sensor', detailKind: 'MATERIAL', hard: true),
        findingJson('none', 'MATCHES', images: ['P3'], area: 'digital crown knurling', part: 'crown_side'),
      ];

      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: findings), ps: hardwareOnlyPhotos);
      expect(r.verdict, Verdict.likelyAuthentic);
      expect(r.gaps.any((g) => g.description.contains('information screen')), isFalse);
    });
  });

  group('6. Different generations of the same model', () {
    test('generation-specific feature without confirmed generation is treated as unclear, not counterfeit', () {
      final noGenProfile = appleWatch(generation: null);
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'display', part: 'front_display'),
        findingJson('none', 'MATCHES', images: ['P2'], area: 'sensor', part: 'back_sensor', detailKind: 'MATERIAL', hard: true),
        findingJson('none', 'CONFLICTS', images: ['P3'], area: 'action button', part: 'crown_side', scope: 'THIS_GENERATION', observed: 'Has action button not on Series 8.'),
      ];

      final r = run(combinedJson(verdict: 'NOT_SURE', findings: findings), prof: noGenProfile);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.counterfeitGroups, isEmpty);
      expect(r.records.firstWhere((x) => x.featureName == 'action button').direction, EvidenceDirection.unclear);
    });
  });

  group('7. Blurry and partially obscured photographs', () {
    test('blurry photo downgrades fine detail reliability and prevents false authentic', () {
      final blurryPhotos = [
        photo('overview', const [], initial: true, quality: const PhotoQualitySummary(detailReadability: 'NOT_READABLE')),
        photo('back_sensor', const [], quality: const PhotoQualitySummary(detailReadability: 'NOT_READABLE')),
        photo('side_crown', const []),
      ];
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'front display', part: 'front_display'),
        findingJson('none', 'MATCHES', images: ['P2'], area: 'back sensor', part: 'back_sensor', detailKind: 'MATERIAL', hard: true),
        findingJson('none', 'MATCHES', images: ['P3'], area: 'digital crown', part: 'crown_side'),
      ];

      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: findings), ps: blurryPhotos);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.diagnostics['validation_result'], 'overridden_to_inconclusive');
    });

    test('obscured detail is never counted as counterfeit evidence', () {
      final findings = [
        findingJson('none', 'CONFLICTS', images: ['P2'], part: 'back_sensor', visibility: 'OBSCURED', observed: 'Cannot clearly see sensor.'),
        findingJson('none', 'NOT_VISIBLE', images: ['P3'], part: 'crown_side', observed: 'Crown obscured by protective case.'),
      ];

      final r = run(combinedJson(verdict: 'REPLICA', findings: findings));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.counterfeitGroups, isEmpty);
      expect(r.decisiveCount, 0);
    });
  });

  group('8. Contradictory findings and cross-photo discrepancies', () {
    test('cross-photo contradiction about model identity forces Inconclusive', () {
      final findings = authenticFindings();
      final contradictions = [
        {
          'description': 'Photo 1 shows a round case, while Photo 2 shows a rectangular Apple Watch case.',
          'photo_ids': ['P1', 'P2'],
          'severity': 'critical',
          'identity_related': true,
        },
      ];

      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: findings, contradictions: contradictions, consistent: false));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.identityMet, isFalse);
      expect(r.diagnostics['validation_result'], 'overridden_to_inconclusive');
      expect(r.diagnostics['disagreement_reason'], 'contradictory_model_identity');
    });

    test('contested evidence with both decisive difference and hard-to-copy matches gives Inconclusive', () {
      final backMaterial = checklist.claims.firstWhere((c) => c.checkpointId == 'aw_back_material');
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'case machining', part: 'band_slot', detailKind: 'CONSTRUCTION', hard: true),
        findingJson('none', 'MATCHES', images: ['P3'], area: 'crown knurling', part: 'crown_side', detailKind: 'CONSTRUCTION', hard: true),
        findingJson(backMaterial.id, 'CONFLICTS', images: ['P2'], part: 'back_sensor', variation: 'RULED_OUT', observed: 'White plastic back plate.'),
      ];

      final r = run(combinedJson(verdict: 'REPLICA', findings: findings));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.contested, isTrue);
      expect(r.diagnostics['disagreement_reason'], 'contested_evidence');
    });
  });

  group('9. Incorrect evidence-ID mapping', () {
    test('claim ID referencing checkpoint ID instead of claim UUID is reconciled via fallback', () {
      final findings = [
        findingJson('aw_display_border', 'MATCHES', images: ['P1'], area: 'front display', part: 'front_display'),
        findingJson('aw_sensor_construction', 'MATCHES', images: ['P2'], area: 'back sensor', part: 'back_sensor', detailKind: 'MATERIAL', hard: true),
        findingJson('aw_crown_construction', 'MATCHES', images: ['P3'], area: 'crown machining', part: 'crown_side'),
      ];

      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: findings));
      expect(r.verdict, Verdict.likelyAuthentic);
      expect(r.supporting.first.referenceSource, contains('App checklist'));
    });
  });

  group('10. Gemini and validation-engine technical validation', () {
    test('Gemini proposes AUTHENTIC while documenting counterfeit discrepancy is overridden with diagnostic trace', () {
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'front logo', part: 'front_display'),
        findingJson('none', 'CONFLICTS', images: ['P2'], area: 'back sensor', part: 'back_sensor', variation: 'RULED_OUT', observed: 'Plastic back cover.'),
      ];

      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: findings));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.diagnostics['validation_result'], 'overridden_to_inconclusive');
      expect(r.diagnostics['disagreement_reason'], 'unresolved_counterfeit_findings');
      expect(r.diagnostics['gemini_proposed_verdict'], 'AUTHENTIC');
    });

    test('Gemini proposes REPLICA with zero observed discrepancies is overridden to Inconclusive', () {
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'front display', part: 'front_display'),
        findingJson('none', 'MATCHES', images: ['P2'], area: 'back sensor', part: 'back_sensor'),
      ];

      final r = run(combinedJson(verdict: 'REPLICA', findings: findings));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.diagnostics['validation_result'], 'overridden_to_inconclusive');
      expect(r.diagnostics['disagreement_reason'], 'unsupported_counterfeit_claim');
    });

    test('Gemini proposes REPLICA based on visible knowledge tell is directly accepted', () {
      final findings = [
        findingJson('none', 'CONFLICTS', images: ['P3'], part: 'crown_side', variation: 'RULED_OUT', tell: true, hard: true, observed: 'Slightly rough knurling.'),
      ];

      final r = run(combinedJson(verdict: 'REPLICA', findings: findings));
      expect(r.verdict, Verdict.likelyReplica);
      expect(r.diagnostics['validation_result'], 'agreed');
      expect(r.diagnostics['final_verdict'], 'LIKELY_REPLICA');
    });
  });

  group('11. Privacy-safe diagnostics verification', () {
    test('serial numbers in observations are redacted and never logged in plain text', () {
      final findings = [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'display', part: 'front_display'),
        findingJson('none', 'MATCHES', images: ['P2'], area: 'sensor', part: 'back_sensor', detailKind: 'MATERIAL', hard: true, observed: 'Serial H123456789 visible.'),
        findingJson('none', 'MATCHES', images: ['P3'], area: 'crown', part: 'crown_side'),
      ];

      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: findings));
      final diag = r.diagnostics;
      expect(diag, isNotNull);
      expect(diag['identified_product'], isNotEmpty);
      expect(diag['identified_model'], isNotEmpty);
      expect(diag['submitted_photos_count'], 3);
      expect(diag['gemini_proposed_verdict'], 'AUTHENTIC');
      expect(diag['validation_result'], 'agreed');
      expect(diag['final_verdict'], 'LIKELY_AUTHENTIC');

      // Verify serial number redaction: H123456789 should be masked as H1***89
      final supporting = diag['supporting_findings'] as List;
      final serializedFinding = supporting.firstWhere((s) => s.toString().contains('Serial'));
      expect(serializedFinding, isNot(contains('H123456789')));
      expect(serializedFinding, contains('H1***89'));
    });
  });
}
