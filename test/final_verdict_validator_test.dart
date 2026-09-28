import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/data/evidence_profiles.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/evidence_record.dart';
import 'package:replica_detector/models/product_reference.dart';
import 'package:replica_detector/services/evidence_decision_engine.dart';
import 'package:replica_detector/services/final_verdict_validator.dart';

import 'support/fake_gemini.dart';
import 'support/fixtures.dart';

// Rules of the engine v4 final stage (Gemini's own knowledge + app
// checklist, no external research). The inputs are hand-written fixtures;
// they test the decision rules, not model accuracy.

void main() {
  final profile = appleWatch();
  final checklist = ProductReference.checklist(profile);
  final photos = [
    photo('overview', const [], initial: true),
    photo('back_sensor', const []),
    photo('side_crown', const []),
  ];
  const images = {'P1': 'overview', 'P2': 'back_sensor', 'P3': 'side_crown', 'C1': 'back_sensor'};
  ReferenceClaim item(String checkpointId) => checklist.claims.firstWhere((c) => c.checkpointId == checkpointId);

  CombinedAnalysis parse(Map<String, dynamic> json, {ProductReference? list}) => CombinedAnalysis.parse(
        json,
        imageToPhoto: images,
        claimIds: {for (final c in (list ?? checklist).claims) c.id},
        requestIds: {for (final r in profile.profile.requests) r.id},
      );

  EngineResult run(
    Map<String, dynamic> json, {
    List<PhotoEvidence>? ps,
    ResolvedProfile? prof,
    EngineResult? preliminary,
  }) =>
      FinalVerdictValidator.validate(
        profile: prof ?? profile,
        photos: ps ?? photos,
        checklist: prof == null ? checklist : ProductReference.checklist(prof),
        analysis: parse(json, list: prof == null ? null : ProductReference.checklist(prof)),
        preliminary: preliminary,
      );

  group('Authentic', () {
    test('three specific matches on different parts, one hard to copy, in two photos give Authentic', () {
      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: authenticFindings()));
      expect(r.verdict, Verdict.likelyAuthentic);
      expect(r.authenticGroups, {'back_sensor', 'crown_side', 'front_display'});
      expect(r.hardToCopyGroups, {'back_sensor'});
      expect(r.supporting.first.referenceSource, contains("Gemini's own knowledge"));
      expect(r.supporting.first.referenceSource, contains('not externally verified'));
    });

    test('the rules never upgrade a "not sure" proposal', () {
      expect(run(combinedJson(verdict: 'NOT_SURE', findings: authenticFindings())).verdict, Verdict.inconclusive);
    });

    test('a proposal the rules do not support becomes not sure, with the reason', () {
      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: authenticFindings().take(1).toList()));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.gaps.map((g) => g.type), contains(GapType.independentGroups));
      expect(r.trace.join(' '), contains('Gemini proposed AUTHENTIC'));
    });

    test('generic quality never proves authenticity', () {
      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: [
        ...authenticFindings().take(1),
        findingJson('none', 'MATCHES', images: ['P3'], area: 'stitching', part: 'band_slot', basis: 'GENERIC_QUALITY'),
      ]));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.neutral, hasLength(1));
    });

    test('details on the same photographed part count as one part', () {
      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: [
        findingJson('none', 'MATCHES', images: ['P1'], area: 'logo', part: 'front_display'),
        findingJson('none', 'MATCHES', images: ['P3'], area: 'display edge', part: 'front_display'),
      ]));
      expect(r.authenticGroups, {'front_display'});
      expect(r.verdict, Verdict.inconclusive);
    });

    test('a close-up is not independent evidence: it counts as its parent photo', () {
      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: [
        findingJson('none', 'MATCHES', images: ['C1'], part: 'back_sensor', detailKind: 'MATERIAL', hard: true),
        findingJson('none', 'MATCHES', images: ['P2'], part: 'crown_side'),
        findingJson('none', 'MATCHES', images: ['C1'], part: 'front_display'),
      ]));
      expect(r.verdict, Verdict.inconclusive, reason: 'everything came from one photo');
      expect(r.gaps.map((g) => g.description).join(' '), contains('one photo'));
    });

    test('printed or engraved text and device screens never serve as the hard-to-copy match', () {
      final marking = run(combinedJson(verdict: 'NOT_SURE', findings: [
        findingJson('none', 'MATCHES', images: ['P2'], part: 'back_sensor', detailKind: 'MARKING', hard: true),
        ...authenticFindings().skip(1),
      ]));
      expect(marking.hardToCopyGroups, isEmpty);
      expect(marking.verdict, Verdict.inconclusive);
      final screen = run(combinedJson(verdict: 'AUTHENTIC', findings: [
        findingJson(item('aw_device_info').id, 'MATCHES', images: ['P2'], area: 'about screen', part: 'device_info', detailKind: 'SOFTWARE'),
        ...authenticFindings().skip(1),
      ]));
      expect(screen.hardToCopyGroups, isEmpty);
      expect(screen.records.firstWhere((x) => x.featureId == item('aw_device_info').id).kind, EvidenceKind.deviceReported);
    });

    test('knowledge Gemini is not sure of, or tied to an unknown generation, does not count', () {
      final unsure = run(combinedJson(verdict: 'AUTHENTIC', findings: [
        findingJson('none', 'MATCHES', images: ['P2'], part: 'back_sensor', detailKind: 'MATERIAL', hard: true, scope: 'NOT_SURE'),
        ...authenticFindings().skip(1),
      ]));
      expect(unsure.verdict, Verdict.inconclusive);
      expect(unsure.unclear, isNotEmpty);
      final noGeneration = appleWatch(generation: null);
      final json = combinedJson(verdict: 'AUTHENTIC', findings: [
        findingJson('none', 'MATCHES', images: ['P2'], part: 'back_sensor', detailKind: 'MATERIAL', hard: true, scope: 'THIS_GENERATION'),
        ...authenticFindings().skip(1),
      ]);
      expect(run(json, prof: noGeneration).verdict, Verdict.inconclusive);
      expect(run(json).verdict, Verdict.likelyAuthentic, reason: 'with the generation established it counts');
    });

    test('blurry photos lose reliability for fine detail', () {
      final blurry = [
        photo('overview', const [], initial: true, quality: const PhotoQualitySummary(detailReadability: 'NOT_READABLE')),
        photo('back_sensor', const [], quality: const PhotoQualitySummary(detailReadability: 'NOT_READABLE')),
        photo('side_crown', const []),
      ];
      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: authenticFindings()), ps: blurry);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.records.firstWhere((x) => x.group == 'back_sensor').reliability, Reliability.medium);
    });

    test('a serious per-photo difference the combined call did not settle blocks Authentic', () {
      final backPhoto = photo('back_sensor', [assess('aw_back_material', CheckpointOutcome.inconsistent)]);
      final withBack = [photos[0], backPhoto, photos[2]];
      final preliminary = EvidenceDecisionEngine.evaluate(profile: profile, photos: withBack);
      expect(preliminary.contradicting, isNotEmpty);
      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: authenticFindings()), ps: withBack, preliminary: preliminary);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.gaps.map((g) => g.description).join(' '), contains('did not settle it'));
    });
  });

  group('Replica', () {
    test('a decisive checklist difference, variation-checked, gives Replica', () {
      final backMaterial = item('aw_back_material');
      expect(backMaterial.decisiveIfDifferent, isTrue);
      final r = run(combinedJson(verdict: 'REPLICA', findings: [
        findingJson(backMaterial.id, 'CONFLICTS', images: ['P2'], part: 'back_sensor', variation: 'RULED_OUT', observed: 'Light cream plastic back.'),
      ]));
      expect(r.verdict, Verdict.likelyReplica);
      expect(r.decisiveCount, 1);
      expect(r.strength, EvidenceStrength.strong);
    });

    test("a difference from Gemini's knowledge directly supports Replica under chat-style verdict", () {
      final one = run(combinedJson(verdict: 'REPLICA', findings: [
        findingJson('none', 'CONFLICTS', images: ['P3'], part: 'crown_side', variation: 'RULED_OUT', tell: true, hard: true),
      ]));
      expect(one.verdict, Verdict.likelyReplica);
      final two = run(combinedJson(verdict: 'REPLICA', findings: [
        findingJson('none', 'CONFLICTS', images: ['P3'], part: 'crown_side', variation: 'RULED_OUT'),
        findingJson('none', 'CONFLICTS', images: ['P1'], part: 'front_display', variation: 'RULED_OUT'),
      ]));
      expect(two.verdict, Verdict.likelyReplica);
    });

    test('something not visible is never counterfeit evidence', () {
      final r = run(combinedJson(verdict: 'REPLICA', findings: [
        findingJson(item('aw_back_material').id, 'CONFLICTS', images: ['P2'], part: 'back_sensor', visibility: 'OBSCURED', variation: 'RULED_OUT'),
        findingJson('none', 'NOT_VISIBLE', images: ['P1'], part: 'crown_side'),
      ]));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.counterfeitGroups, isEmpty);
    });

    test('a likely legitimate variation keeps the result from being forced to Replica; a possible one makes it weak', () {
      final likely = run(combinedJson(verdict: 'REPLICA', findings: [
        findingJson(item('aw_back_material').id, 'CONFLICTS', images: ['P2'], part: 'back_sensor', variation: 'LIKELY', alternative: 'Replacement back cover.'),
      ]));
      expect(likely.verdict, Verdict.inconclusive);
      expect(likely.unclear.single.variationNote, 'Replacement back cover.');
      final possible = run(combinedJson(verdict: 'REPLICA', findings: [
        findingJson('none', 'CONFLICTS', images: ['P3'], part: 'crown_side', variation: 'POSSIBLE'),
        findingJson('none', 'CONFLICTS', images: ['P1'], part: 'front_display', variation: 'POSSIBLE'),
      ]));
      expect(possible.counterfeitGroups, isEmpty);
    });

    test('photo conditions downgrade a difference', () {
      final r = run(combinedJson(verdict: 'REPLICA', findings: [
        findingJson('none', 'CONFLICTS', images: ['P3'], part: 'crown_side', variation: 'RULED_OUT', alternative: 'Could be glare on the crown.'),
      ]));
      expect(r.records.single.reliability, Reliability.medium);
    });

    test('a missing detail counts only when the checklist documents it', () {
      final undocumented = checklist.claims.firstWhere((c) => !c.documented && !c.decisiveIfDifferent);
      final absent = run(combinedJson(verdict: 'NOT_SURE', findings: [
        findingJson(undocumented.id, 'CONFLICTS', images: ['P2'], part: 'back_sensor', differenceKind: 'ABSENT', variation: 'RULED_OUT'),
        findingJson('none', 'CONFLICTS', images: ['P3'], part: 'crown_side', differenceKind: 'ABSENT', variation: 'RULED_OUT'),
      ]));
      expect(absent.counterfeitGroups, isEmpty);
      final fasteners = item('aw_back_fasteners');
      expect(fasteners.documented, isTrue);
      final documented = run(combinedJson(verdict: 'REPLICA', findings: [
        findingJson(fasteners.id, 'CONFLICTS', images: ['P2'], part: 'back_sensor', differenceKind: 'ABSENT', variation: 'RULED_OUT'),
      ]));
      expect(documented.verdict, Verdict.likelyReplica);
    });

    test('with an unknown brand there is no verdict, even with a "decisive" difference', () {
      final unbranded = EvidenceProfileRegistry.resolve(identity(category: 'WATCH', type: 'smartwatch', brand: null, family: null));
      final list = ProductReference.checklist(unbranded);
      final brandItem = list.claims.firstWhere((c) => c.checkpointId == 'brand_marking');
      final r = FinalVerdictValidator.validate(
        profile: unbranded,
        photos: photos,
        checklist: list,
        analysis: CombinedAnalysis.parse(
          combinedJson(brand: null, verdict: 'REPLICA', findings: [
            findingJson(brandItem.id, 'CONFLICTS', images: ['P2'], variation: 'RULED_OUT', observed: 'No brand name or logo anywhere.'),
          ]),
          imageToPhoto: images,
          claimIds: {for (final c in list.claims) c.id},
          requestIds: const {},
        ),
      );
      expect(r.verdict, Verdict.inconclusive);
      expect(r.gaps.first.description, contains('brand could not be established'));
    });

    test('a critical contradiction between photos breaks identity consistency', () {
      final r = run(combinedJson(verdict: 'AUTHENTIC', findings: authenticFindings(), contradictions: [
        {'description': 'The back says 44mm, the box says 49mm.', 'image_ids': ['P1', 'P2'], 'severity': 'critical', 'identity_related': true},
      ]));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.identityMet, isFalse);
    });
  });

  group('Structure', () {
    test('findings on unknown images are dropped; unknown checklist ids become "none"', () {
      final a = parse(combinedJson(findings: [
        findingJson('b1', 'MATCHES', images: ['P9']),
        findingJson('r77', 'MATCHES', images: ['P1']),
      ]));
      expect(a.findings, hasLength(1));
      expect(a.findings.single.claimId, 'none');
      expect(a.droppedFindings, 1);
    });

    test('a missing required part is a format error (retried, never a result)', () {
      expect(() => parse({'findings': []}), throwsFormatException);
      expect(() => parse({...combinedJson(), 'proposed_verdict': 'MAYBE'}), throwsFormatException);
    });

    test('unresolved items point the planner at the photo that resolves them', () {
      final r = run(combinedJson(verdict: 'NOT_SURE', unresolved: [
        {'issue': 'The model information screen was not photographed.', 'resolving_photo': 'device_info', 'resolving_check': null},
      ]));
      final g = r.gaps.firstWhere((g) => g.description.contains('model information'));
      expect(g.targetCheckpointIds, isNotEmpty);
    });

    test('part names from the checklist group sensibly when no photo part is given', () {
      expect(FinalVerdictValidator.group('back material'), FinalVerdictValidator.group('back'));
      expect(FinalVerdictValidator.group('Digital Crown'), 'crown');
      expect(FinalVerdictValidator.group('about screen'), 'device');
    });

    test('the verdict reasoning is kept in the trace for diagnostics', () {
      final r = run(combinedJson(verdict: 'NOT_SURE'));
      expect(r.trace.join(' '), contains('fixture reasoning'));
    });
  });

  test('a "not sure" always says what is open, even when Gemini lists nothing unresolved', () {
    final r = run(combinedJson(verdict: 'NOT_SURE', findings: authenticFindings().take(2).toList()));
    expect(r.verdict, Verdict.inconclusive);
    expect(r.remainingUncertainty, isNotEmpty);
  });
}
