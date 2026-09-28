import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/data/evidence_profiles.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/evidence_record.dart';
import 'package:replica_detector/models/product_identity.dart';
import 'package:replica_detector/services/evidence_decision_engine.dart';

import 'support/fixtures.dart';

// Rule-level tests of the decision engine with hand-written observations.
// They check the decision logic, not accuracy on real products.

EngineResult run(ResolvedProfile p, List<PhotoEvidence> photos, {FinalEvaluation? fin}) =>
    EvidenceDecisionEngine.evaluate(profile: p, photos: photos, finalEvaluation: fin);

FinalEvaluation ruledOut(EngineResult r) => FinalEvaluation(variationChecks: {
      for (final rec in r.recordsNeedingVariationCheck)
        EvidenceDecisionEngine.recordKey(rec.photoId, rec.featureId): const VariationResult(VariationCheck.ruledOut, 'no genuine version has this'),
    });

FinalEvaluation variation(EngineResult r, VariationCheck v) => FinalEvaluation(variationChecks: {
      for (final rec in r.recordsNeedingVariationCheck)
        EvidenceDecisionEngine.recordKey(rec.photoId, rec.featureId): VariationResult(v, 'fixture'),
    });

void main() {
  final genuineAppleWatch = [
    photo('device_info', [
      assess('aw_device_info', CheckpointOutcome.consistent, kind: EvidenceKind.deviceReported, basis: ReferenceBasis.deviceReported),
    ]),
    photo('back_sensor', [
      assess('aw_sensor_construction', CheckpointOutcome.consistent),
      assess('aw_back_material', CheckpointOutcome.consistent),
    ]),
  ];

  group('Verdicts depend on evidence, never on the number of photos', () {
    test('two clear photos with independent hard-to-copy evidence are enough for Authentic', () {
      final r = run(appleWatch(), genuineAppleWatch);
      expect(r.verdict, Verdict.likelyAuthentic);
      expect(r.sufficient, isTrue);
      expect(r.authenticGroups, containsAll(['device_software', 'sensor']));
    });

    test('adding more photos of the same features does not change a supported verdict', () {
      final more = [
        ...genuineAppleWatch,
        photo('front_display', [assess('aw_software_ui', CheckpointOutcome.consistent)]),
        photo('other_side', [assess('aw_ultra_action_button', CheckpointOutcome.consistent)]),
      ];
      expect(run(appleWatch(), more).verdict, Verdict.likelyAuthentic);
    });

    test('a single photo with decisive counterfeit evidence is provisionally Replica', () {
      final r = run(appleWatch(), [
        photo('back_sensor', [
          assess('aw_back_material', CheckpointOutcome.inconsistent,
              observation: 'The back plate is light cream plastic.',
              interpretation: 'The genuine Ultra back is black ceramic and sapphire.'),
        ]),
      ]);
      expect(r.verdict, Verdict.likelyReplica);
      expect(r.awaitingFinalEvaluation, isTrue, reason: 'legitimate variations must still be ruled out');
      expect(r.decisiveCount, 1);
    });

    test('an unresolved result names what is missing instead of counting photos', () {
      final r = run(appleWatch(), [
        photo('front_display', [assess('aw_software_ui', CheckpointOutcome.consistent)]),
      ]);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.gaps.map((g) => g.type), contains(GapType.hardToCopy));
      expect(r.remainingUncertainty.join(' '), isNot(matches(RegExp(r'\d+ of \d+ photos'))));
    });
  });

  group('Absence and photo conditions are never counterfeit evidence', () {
    test('a serial number that is not visible is not evidence of anything', () {
      final r = run(appleWatch(), [
        ...genuineAppleWatch,
        photo('band_slot', [assess('aw_serial_text', CheckpointOutcome.notVisible)]),
      ]);
      expect(r.verdict, Verdict.likelyAuthentic);
      expect(r.counterfeitGroups, isEmpty);
    });

    test('a mismatch the model attributes to glare loses reliability', () {
      final r = run(appleWatch(), [
        photo('crown_side', [
          assess('aw_crown_construction', CheckpointOutcome.inconsistent,
              reliability: Reliability.medium, alternative: 'Could be glare on the crown.'),
        ]),
      ]);
      expect(r.counterfeitGroups, isEmpty);
      expect(r.records.single.reliability, Reliability.low);
    });

    test('offering a non-photo alternative does not by itself weaken a finding', () {
      final r = run(appleWatch(), [
        photo('back_sensor', [
          assess('aw_charging_contacts', CheckpointOutcome.inconsistent,
              observation: 'Two exposed metal charging pins on the back.',
              alternative: 'Could be an aftermarket charging adapter clipped on.'),
        ]),
      ]);
      expect(r.records.single.reliability, Reliability.high);
      expect(r.decisiveCount, 1);
    });

    test('fine detail from an unreadable photo cannot decide either way, and a retake is suggested', () {
      final r = run(appleWatch(), [
        photo('back_sensor', [
          assess('aw_sensor_construction', CheckpointOutcome.inconsistent),
        ], quality: const PhotoQualitySummary(detailReadability: 'NOT_READABLE', issues: ['SEVERE_BLUR'], fix: 'Tap to focus.')),
      ]);
      expect(r.counterfeitGroups, isEmpty);
      final retake = r.gaps.where((g) => g.type == GapType.unclearPhoto);
      expect(retake, isEmpty, reason: 'a LOW counterfeit record is still counterfeit direction, not unclear');
      expect(r.records.single.reliability, Reliability.low);
    });

    test('an unclear hard-to-copy detail asks for a retake of that photo', () {
      final r = run(appleWatch(), [
        photo('back_sensor', [assess('aw_sensor_construction', CheckpointOutcome.unclear, reliability: Reliability.low)],
            quality: const PhotoQualitySummary(detailReadability: 'PARTLY_READABLE', fix: 'Move closer.')),
      ]);
      final g = r.gaps.firstWhere((g) => g.type == GapType.unclearPhoto);
      expect(g.retakeRequestId, 'back_sensor');
      expect(g.fix, 'Move closer.');
    });
  });

  group('Generations are never compared across', () {
    test('a generation-specific mismatch is unclear while the generation is not established', () {
      final r = run(appleWatchSeries(generation: null), [
        photo('back_sensor', [assess('aw_sensor_layout', CheckpointOutcome.inconsistent)]),
      ]);
      expect(r.counterfeitGroups, isEmpty);
      expect(r.records.single.direction, EvidenceDirection.unclear);
    });

    test('the same mismatch counts once the generation is established', () {
      final r = run(appleWatchSeries(), [
        photo('back_sensor', [assess('aw_sensor_layout', CheckpointOutcome.inconsistent)]),
      ]);
      expect(r.counterfeitGroups, contains('sensor'));
    });

    test('Apple Watch authentic requires the generation: clean evidence without it stays unresolved', () {
      final r = run(appleWatchSeries(generation: null), genuineAppleWatch);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.gaps.first.type, GapType.identity);
      expect(r.gaps.first.targetCheckpointIds, contains('aw_device_info'));
    });
  });

  group('Copied features and copied serials never make an item authentic', () {
    test('matching copied design features is neutral', () {
      final r = run(appleWatch(), [
        photo('other_side', [assess('aw_ultra_action_button', CheckpointOutcome.consistent)]),
        photo('back_sensor', [assess('aw_charging_contacts', CheckpointOutcome.consistent)]),
        photo('crown_side', [assess('aw_crown_markings', CheckpointOutcome.consistent)]),
      ]);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.authenticGroups, isEmpty);
      expect(r.neutral, hasLength(3));
    });

    test('a genuine-looking serial copied onto a counterfeit is weak support only', () {
      final r = run(appleWatch(), [
        photo('band_slot', [assess('aw_serial_text', CheckpointOutcome.consistent, kind: EvidenceKind.observedFact)]),
        photo('other_side', [assess('aw_ultra_action_button', CheckpointOutcome.consistent)]),
        photo('front_display', [assess('aw_software_ui', CheckpointOutcome.consistent)]),
      ]);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.authenticGroups, isNot(contains('serial')));
    });

    test('findings outside the product checklist can neither confirm nor condemn', () {
      final r = run(appleWatch(), [
        photo('front_display', [
          assess('other', CheckpointOutcome.consistent, feature: 'Premium feel'),
          assess('other', CheckpointOutcome.inconsistent, feature: 'Box looks cheap'),
        ]),
      ]);
      expect(r.authenticGroups, isEmpty);
      expect(r.counterfeitGroups, isEmpty);
    });
  });

  group('Independence', () {
    test('two observations of one feature group are one piece of evidence', () {
      final r = run(appleWatch(), [
        photo('device_info', [assess('aw_device_info', CheckpointOutcome.consistent)]),
        photo('front_display', [assess('aw_software_ui', CheckpointOutcome.consistent)]),
      ]);
      expect(r.authenticGroups, {'device_software'});
      expect(r.verdict, Verdict.inconclusive);
    });

    test('the same picture submitted twice counts once', () {
      final a = photo('back_sensor', [assess('aw_back_engraving', CheckpointOutcome.inconsistent)], hash: 'ffff0000ffff0000');
      final b = photo('crown_side', [assess('aw_crown_construction', CheckpointOutcome.inconsistent)], hash: 'ffff0000ffff0001');
      final r = run(appleWatch(), [a, b]);
      expect(r.counterfeitGroups, {'back_text'});
      expect(r.trace.join(' '), contains('duplicate'));
    });

    test('equally reliable photos that disagree make the feature unclear', () {
      final r = run(appleWatch(), [
        photo('crown_side', [assess('aw_crown_construction', CheckpointOutcome.consistent, reliability: Reliability.medium)]),
        photo('front_display', [assess('aw_crown_construction', CheckpointOutcome.inconsistent, reliability: Reliability.medium)], photoId: 'p2'),
      ]);
      expect(r.authenticGroups, isEmpty);
      expect(r.counterfeitGroups, isEmpty);
      expect(r.remainingUncertainty.join(' '), contains('disagree'));
    });

    test('a clearer photo of the same feature outweighs a less clear one', () {
      final r = run(appleWatch(), [
        photo('crown_side', [assess('aw_crown_construction', CheckpointOutcome.consistent, reliability: Reliability.high)]),
        photo('front_display', [assess('aw_crown_construction', CheckpointOutcome.inconsistent, reliability: Reliability.medium)], photoId: 'p2'),
      ]);
      expect(r.authenticGroups, contains('crown'));
      expect(r.counterfeitGroups, isEmpty);
    });
  });

  group('A counterfeit verdict needs legitimate variations ruled out', () {
    final whiteBack = [
      photo('back_sensor', [
        assess('aw_back_material', CheckpointOutcome.inconsistent,
            observation: 'The back plate is light cream plastic.', interpretation: 'Genuine Ultra backs are black ceramic.'),
      ]),
    ];

    test('ruled out -> Replica', () {
      final pre = run(appleWatch(), whiteBack);
      final r = run(appleWatch(), whiteBack, fin: ruledOut(pre));
      expect(r.verdict, Verdict.likelyReplica);
      expect(r.awaitingFinalEvaluation, isFalse);
      expect(r.contradicting.single.variation, VariationCheck.ruledOut);
    });

    test('a likely legitimate variation removes it as counterfeit evidence', () {
      final pre = run(appleWatch(), whiteBack);
      final r = run(appleWatch(), whiteBack, fin: variation(pre, VariationCheck.likely));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.counterfeitGroups, isEmpty);
    });

    test('a possible variation leaves one indicator that needs corroboration', () {
      final pre = run(appleWatch(), whiteBack);
      final r = run(appleWatch(), whiteBack, fin: variation(pre, VariationCheck.possible));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.gaps.first.type, GapType.corroborateCounterfeit);
      expect(r.gaps.first.targetCheckpointIds, isNot(contains('aw_back_material')));
    });

    test('two independent medium mismatches reach Replica once checked', () {
      final photos = [
        photo('crown_side', [assess('aw_crown_construction', CheckpointOutcome.inconsistent, reliability: Reliability.medium)]),
        photo('other_side', [assess('aw_case_finish', CheckpointOutcome.inconsistent, reliability: Reliability.medium)]),
      ];
      final pre = run(appleWatch(), photos);
      expect(pre.counterfeitGroups, hasLength(2));
      expect(run(appleWatch(), photos, fin: ruledOut(pre)).verdict, Verdict.likelyReplica);
    });

    test('a cross-photo identity contradiction counts as counterfeit evidence', () {
      final r = run(appleWatch(), [
        photo('crown_side', [assess('aw_crown_construction', CheckpointOutcome.inconsistent, reliability: Reliability.medium)]),
      ], fin: FinalEvaluation(
        variationChecks: {EvidenceDecisionEngine.recordKey('crown_side', 'aw_crown_construction'): const VariationResult(VariationCheck.ruledOut, '')},
        contradictions: const [
          CrossPhotoContradiction(description: 'The screen reports Series 9 but the case is 49 mm.', severity: 'critical', identityRelated: true),
        ],
      ));
      expect(r.verdict, Verdict.likelyReplica);
    });
  });

  group('Contested and identity-inconsistent evidence is not forced into a verdict', () {
    test('a decisive mismatch next to a clean hard-to-copy feature is contested', () {
      final r = run(appleWatch(), [
        photo('device_info', [assess('aw_device_info', CheckpointOutcome.consistent)]),
        photo('back_sensor', [assess('aw_back_material', CheckpointOutcome.inconsistent)]),
      ]);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.contested, isTrue);
      expect(r.gaps.single.type, GapType.contested);
    });

    test('a decisive mismatch outweighs a single good-looking hard-to-copy feature', () {
      final photos = [
        photo('back_sensor', [
          assess('aw_sensor_construction', CheckpointOutcome.consistent),
          assess('aw_back_material', CheckpointOutcome.inconsistent),
        ]),
      ];
      final pre = run(appleWatch(), photos);
      expect(pre.contested, isFalse);
      expect(run(appleWatch(), photos, fin: ruledOut(pre)).verdict, Verdict.likelyReplica);
    });

    test('the final check reporting an identity inconsistency blocks Authentic', () {
      final r = run(appleWatch(), genuineAppleWatch, fin: const FinalEvaluation(identityConsistent: false));
      expect(r.verdict, Verdict.inconclusive);
      expect(r.gaps.any((g) => g.type == GapType.identity), isTrue);
    });
  });

  group('Authentic needs corroboration from more than one photo', () {
    test('everything looking right in a single photo is not enough', () {
      final r = run(appleWatch(), [
        photo('device_info', [
          assess('aw_device_info', CheckpointOutcome.consistent),
          assess('aw_sensor_construction', CheckpointOutcome.consistent),
        ]),
      ]);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.gaps.map((g) => g.description).join(' '), contains('one photo'));
    });
  });

  group('Brand imitation and unfamiliar products', () {
    final shoe = EvidenceProfileRegistry.resolve(identity(category: 'SNEAKER', brand: 'Michael Kors', family: null));

    test('an imitation brand marking is decisive and rests on the brand alone', () {
      final photos = [
        photo('side_profile', [
          assess('brand_marking', CheckpointOutcome.inconsistent,
              observation: 'Printed "MK SHOES" next to a tiger-head logo.',
              interpretation: 'Michael Kors never uses this marking.',
              alternative: 'Could be an unrelated budget brand.'),
        ]),
      ];
      final pre = run(shoe, photos);
      expect(pre.decisiveCount, 1);
      expect(run(shoe, photos, fin: ruledOut(pre)).verdict, Verdict.likelyReplica);
    });

    test('an "other" finding that describes a brand imitation maps to the brand-marking checkpoint', () {
      final r = run(shoe, [
        photo('side_profile', [assess('other', CheckpointOutcome.inconsistent, feature: 'Logo imitation of Michael Kors')]),
      ]);
      expect(r.records.single.featureId, 'brand_marking');
    });

    test('the generic profile never calls an item authentic', () {
      final generic = EvidenceProfileRegistry.resolve(identity(category: 'OTHER', brand: 'Acme', family: 'Widget'));
      expect(generic.profile.isGeneric, isTrue);
      final r = run(generic, [
        photo('label', [
          assess('gn_label', CheckpointOutcome.consistent),
          assess('gn_print_quality', CheckpointOutcome.consistent),
        ]),
      ]);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.gaps.any((g) => g.type == GapType.noAuthenticCriteria), isTrue);
    });
  });

  group('Evidence records carry what the brief requires', () {
    test('each record states source photo, model evaluated, reference, kind and reliability', () {
      final r = run(appleWatch(), genuineAppleWatch);
      for (final rec in r.records) {
        expect(rec.photoId, isNotEmpty);
        expect(rec.evaluatedModel, contains('Apple Watch Ultra'));
        expect(rec.referenceSource, isNotEmpty);
      }
      final device = r.records.firstWhere((x) => x.featureId == 'aw_device_info');
      expect(device.kind, EvidenceKind.deviceReported);
      expect(device.referenceSource, contains('not verified'));
      expect(device.corroborated, isTrue, reason: 'the sensor group independently points the same way');
    });

    test('AI knowledge is labelled as unverified', () {
      final r = run(appleWatch(), genuineAppleWatch);
      final sensor = r.records.firstWhere((x) => x.featureId == 'aw_sensor_construction');
      expect(sensor.referenceSource, contains('not independently verified'));
    });

    test('generation-specific comparisons with a probable generation are marked as assumptions', () {
      final r = run(appleWatchSeries(genStatus: AttributeStatus.probable), [
        photo('back_sensor', [assess('aw_sensor_layout', CheckpointOutcome.consistent)]),
      ]);
      expect(r.records.single.kind, EvidenceKind.unverifiedAssumption);
    });
  });

  test('progress reflects useful evidence, not photo count', () {
    final one = run(appleWatch(), [photo('front_display', [assess('aw_software_ui', CheckpointOutcome.consistent)])]);
    final two = run(appleWatch(), [
      photo('front_display', [assess('aw_software_ui', CheckpointOutcome.consistent)]),
      photo('other_side', [assess('aw_ultra_action_button', CheckpointOutcome.consistent)]),
    ]);
    expect(two.progress, one.progress, reason: 'a second photo of copied design adds no useful evidence');
    expect(run(appleWatch(), genuineAppleWatch).progress, 1.0);
  });
}
