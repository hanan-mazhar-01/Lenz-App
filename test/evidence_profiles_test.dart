import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/core/config/authenticity_engine_config.dart';
import 'package:replica_detector/data/evidence_profiles.dart';
import 'package:replica_detector/models/evidence_record.dart';
import 'package:replica_detector/models/product_identity.dart';
import 'package:replica_detector/services/authenticity_prompts.dart';
import 'package:replica_detector/services/evidence_decision_engine.dart';
import 'package:replica_detector/services/evidence_planner.dart';

import 'support/fixtures.dart';

void main() {
  group('Registry covers every supported category', () {
    for (final code in AuthenticityPrompts.categoryCodes) {
      test('$code resolves to a profile', () {
        final p = EvidenceProfileRegistry.resolve(identity(category: code, brand: 'Brand', family: 'Model'));
        expect(p.profile.requests, isNotEmpty);
        expect(p.profile.checkpoints, isNotEmpty);
      });
    }

    test('specific profiles are chosen by brand and product type', () {
      String id(String code, {String type = '', String? brand, String? family}) =>
          EvidenceProfileRegistry.resolve(identity(category: code, type: type, brand: brand, family: family)).id;
      expect(id('WATCH', type: 'smartwatch', brand: 'Apple', family: 'Apple Watch Series'), 'apple_watch');
      expect(id('WATCH', type: 'smartwatch', family: 'Apple Watch Ultra'), 'apple_watch');
      expect(id('WATCH', type: 'fitness band', brand: 'Huawei', family: 'Band 9'), 'smartwatch');
      expect(id('WATCH', type: 'mechanical watch', brand: 'Rolex', family: 'Submariner'), 'mechanical_watch');
      expect(id('SNEAKER', brand: 'Nike', family: 'Air Jordan 4'), 'footwear');
      expect(id('SHOE', brand: 'Gucci', family: 'Loafer'), 'footwear');
      expect(id('HANDBAG', brand: 'Louis Vuitton', family: 'Neverfull'), 'handbag');
      expect(id('SUNGLASSES', brand: 'Ray-Ban', family: 'Wayfarer'), 'eyewear');
      expect(id('EYEGLASSES', brand: 'Oakley', family: 'Holbrook'), 'eyewear');
      expect(id('ACCESSORY', type: 'belt', brand: 'Hermes', family: 'H belt'), 'accessory');
      expect(id('OTHER', brand: 'Acme', family: 'Thing'), 'generic');
    });

    test('an Apple-branded non-watch never gets the Apple Watch profile', () {
      final p = EvidenceProfileRegistry.resolve(identity(category: 'WALLET', type: 'card wallet', brand: 'Apple', family: 'MagSafe Wallet'));
      expect(p.id, isNot('apple_watch'));
    });

    test('profile data is internally consistent', () {
      for (final p in EvidenceProfileRegistry.profiles) {
        final ids = {for (final c in p.checkpoints) c.id};
        expect(ids.length, p.checkpoints.length, reason: '${p.id}: duplicate checkpoint id');
        final reqIds = {for (final r in p.requests) r.id};
        expect(reqIds.length, p.requests.length, reason: '${p.id}: duplicate request id');
        for (final r in p.requests) {
          for (final c in r.checkpointIds) {
            expect(ids, contains(c), reason: '${p.id}/${r.id} references unknown checkpoint $c');
          }
          expect(r.instruction.trim(), isNotEmpty);
          expect(r.why.trim(), isNotEmpty);
        }
        if (p.policy.allowsAuthentic && p.policy.minHardToCopyGroups > 0) {
          expect(p.checkpoints.any((c) => c.hardToCopy), isTrue, reason: '${p.id} can never be authentic');
        }
        // Serial numbers and identity codes are copied onto counterfeits:
        // they identify, they never authenticate.
        for (final c in p.checkpoints.where((c) => c.identityEstablishing && (c.id.contains('serial') || c.id.contains('code')))) {
          expect(c.authenticWeight.atLeast(Weight.medium), isFalse, reason: '${p.id}/${c.id}: serials and codes are copied');
        }
      }
    });

    test('the generic profile invents no product-specific criteria', () {
      final g = EvidenceProfileRegistry.byId('generic');
      expect(g.policy.allowsAuthentic, isFalse);
      expect(g.checkpoints.where((c) => c.counterfeitWeight == Weight.decisive).map((c) => c.id), ['brand_marking']);
    });
  });

  group('Apple Watch generations', () {
    GenerationSpec? gen(String family, String? g) =>
        EvidenceProfileRegistry.resolve(identity(brand: 'Apple', family: family, generation: g, type: 'smartwatch')).generation;

    test('generation text selects the right spec, including "series 1" vs "series 10"', () {
      expect(gen('Apple Watch Ultra', 'Ultra 2')?.id, 'ultra');
      expect(gen('Apple Watch Series', 'Series 10')?.id, 'series_10_11');
      expect(gen('Apple Watch Series', 'Series 9')?.id, 'series_7_9');
      expect(gen('Apple Watch Series', 'Series 1')?.id, 'series_0_3');
      expect(gen('Apple Watch SE', 'SE (2nd generation)')?.id, 'series_4_6_se');
      expect(gen('Apple Watch Series', null), isNull);
    });

    test('the "se" hint does not match "series"', () {
      expect(gen('Apple Watch Series', 'Series 7')?.id, 'series_7_9');
    });

    test('generation-specific checkpoints require the generation to be established', () {
      final p = appleWatch();
      for (final c in p.profile.checkpoints.where((c) => c.generationSpecific)) {
        expect(c.requires, ModelLevel.generation, reason: c.id);
      }
    });
  });

  group('Dynamic evidence selection', () {
    EvidencePlan planFor(ResolvedProfile p, List<PhotoEvidence> photos, {AiEvidenceRanking? ranking, Set<String> skipped = const {}}) {
      final r = EvidenceDecisionEngine.evaluate(profile: p, photos: photos);
      return EvidencePlanner.plan(profile: p, photos: photos, result: r, ranking: ranking, skipped: skipped);
    }

    test('after a front photo of an Apple Watch, the model information screen is asked for first', () {
      final plan = planFor(appleWatch(), [
        photo('front_display', [assess('aw_software_ui', CheckpointOutcome.consistent)], photoId: 'overview', initial: true),
      ]);
      expect(plan.recommended!.id, 'device_info');
      expect(plan.recommended!.reason, contains('information screen'));
      expect(plan.nextOptional, isFalse);
      expect(plan.ranked[1].id, 'back_sensor', reason: 'the back is the most informative exterior photo');
    });

    test('once the device screen is in, the back is asked for, not the crown or bands', () {
      final plan = planFor(appleWatch(), [
        photo('front_display', [assess('aw_software_ui', CheckpointOutcome.consistent)], photoId: 'overview', initial: true),
        photo('device_info', [assess('aw_device_info', CheckpointOutcome.consistent)]),
      ]);
      expect(plan.recommended!.id, 'back_sensor');
    });

    test('an unknown generation makes the identity-establishing photo the priority', () {
      final plan = planFor(appleWatchSeries(generation: null), [
        photo('back_sensor', [assess('aw_sensor_construction', CheckpointOutcome.consistent)]),
      ]);
      expect(plan.recommended!.id, 'device_info');
      expect(plan.recommended!.reason, contains('model'));
    });

    test('one counterfeit indicator asks for an independent second detail', () {
      final plan = planFor(appleWatch(), [
        photo('crown_side', [assess('aw_crown_construction', CheckpointOutcome.inconsistent, reliability: Reliability.medium)]),
      ]);
      final rec = plan.recommended!;
      expect(rec.id, isNot('crown_side'));
      expect(rec.reason.toLowerCase(), contains('independent'));
    });

    test('photos already taken or skipped are never requested again', () {
      final plan = planFor(appleWatch(), [
        photo('back_sensor', [assess('aw_sensor_construction', CheckpointOutcome.consistent)]),
      ], skipped: {'device_info'});
      expect(plan.ranked.map((r) => r.id), isNot(contains('back_sensor')));
      expect(plan.ranked.map((r) => r.id), isNot(contains('device_info')));
    });

    test('when the evidence is sufficient, the next photo is optional', () {
      final plan = planFor(appleWatch(), [
        photo('device_info', [assess('aw_device_info', CheckpointOutcome.consistent)]),
        photo('back_sensor', [assess('aw_sensor_construction', CheckpointOutcome.consistent)]),
      ]);
      expect(plan.nextOptional, isTrue);
      expect(plan.recommended?.reason, startsWith('Optional'));
    });

    test('the model-specific ranking re-orders requests within the profile', () {
      final p = EvidenceProfileRegistry.resolve(identity(category: 'SNEAKER', brand: 'Nike', family: 'Air Jordan 4'));
      final base = planFor(p, const []);
      final ranked = planFor(p, const [],
          ranking: const AiEvidenceRanking(entries: {
            'heel': AiRankEntry(value: 'HIGH', assessable: true),
            'size_tag': AiRankEntry(value: 'LOW', assessable: true),
          }));
      expect(base.recommended!.id, 'size_tag');
      expect(ranked.ranked.indexWhere((r) => r.id == 'heel'), lessThan(ranked.ranked.indexWhere((r) => r.id == 'size_tag')));
    });

    test('an unclear key detail suggests a retake, but only once', () {
      final p = appleWatch();
      final photos = [
        photo('back_sensor', [assess('aw_sensor_construction', CheckpointOutcome.unclear, reliability: Reliability.low)],
            quality: const PhotoQualitySummary(detailReadability: 'PARTLY_READABLE', fix: 'Move closer.')),
      ];
      final r = EvidenceDecisionEngine.evaluate(profile: p, photos: photos);
      final first = EvidencePlanner.plan(profile: p, photos: photos, result: r);
      expect(first.recommended!.isRetake, isTrue);
      expect(first.recommended!.reason, contains('Move closer.'));
      final again = EvidencePlanner.plan(profile: p, photos: photos, result: r, retakeSuggestions: {'back_sensor': 1});
      expect(again.recommended!.isRetake, isFalse);
    });

    test('the photo limit stops further recommendations', () {
      final photos = [
        for (final id in ['front_display', 'back_sensor', 'crown_side', 'band_slot', 'other_side', 'device_info'])
          photo(id, [assess('aw_case_finish', CheckpointOutcome.unclear)]),
      ];
      expect(photos.length, AuthenticityEngineConfig.maxPhotosPerScan);
      final plan = planFor(appleWatch(), photos);
      expect(plan.limitReached, isTrue);
      expect(plan.recommended, isNull);
    });

    test('planning is deterministic', () {
      final p = appleWatch();
      final photos = [photo('front_display', [assess('aw_software_ui', CheckpointOutcome.consistent)])];
      final a = planFor(p, photos).ranked.map((r) => r.id).toList();
      final b = planFor(p, photos).ranked.map((r) => r.id).toList();
      expect(a, b);
    });
  });

  group('First close-up per category is the most discriminative default', () {
    String first(String code, {String type = '', String? brand = 'Brand', String? family = 'Model'}) {
      final p = EvidenceProfileRegistry.resolve(identity(category: code, type: type, brand: brand, family: family));
      final r = EvidenceDecisionEngine.evaluate(profile: p, photos: const []);
      return EvidencePlanner.plan(profile: p, photos: const [], result: r).recommended!.id;
    }

    test('defaults', () {
      expect(first('SNEAKER'), 'size_tag');
      expect(first('HANDBAG'), 'interior_label');
      expect(first('SUNGLASSES'), 'temple_inside');
      expect(first('CLOTHING'), 'neck_label');
      expect(first('WATCH', type: 'smartwatch', brand: 'Huawei'), 'device_info');
    });
  });

  test('identity attributes never become confirmed without a status', () {
    final a = IdentityAttribute.fromParts('Series 9', null);
    expect(a.status, AttributeStatus.probable);
    expect(IdentityAttribute.fromParts('unknown', 'CONFIRMED').isKnown, isFalse);
  });
}
