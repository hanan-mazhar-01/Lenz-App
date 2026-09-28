// Repeat-scan consistency (§17, §32-33).
//
// The same physical item scanned repeatedly produces slightly different
// model output each run: a detail read as unclear once and consistent the
// next, glare mistaken for a flaw, a reliability over-claimed. These tests
// replay such variants through the engine and require the verdict to stay
// stable. They are rule tests on hand-written variants, not a dataset.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/evidence_record.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/models/product_identification.dart';
import 'package:replica_detector/services/evidence_decision_engine.dart';
import 'package:replica_detector/services/scan_consistency_service.dart';

import 'support/fixtures.dart';

const appleWatch = Product(
  id: 'p_aw',
  name: 'Apple Watch Series 9',
  brand: 'Apple',
  model: 'Series 9 45mm Aluminium',
  category: ProductCategory.watches,
  imageAsset: '/tmp/primary.jpg',
  identificationConfidence: 0.9,
  categoryCode: 'WATCH',
);

const sunglasses = Product(
  id: 'p_rb',
  name: 'Wayfarer',
  brand: 'Ray-Ban',
  model: 'RB2140',
  category: ProductCategory.eyewear,
  imageAsset: '/tmp/primary.jpg',
  identificationConfidence: 0.88,
  categoryCode: 'SUNGLASSES',
);

/// One noisy "run" of the analysis on a genuine Series 9: each checkpoint may
/// be over- or under-read, and glare sometimes produces a spurious mismatch
/// that the model itself attributes to reflections.
List<PhotoEvidence> genuineRun(Random rnd) {
  Reliability rel() => [Reliability.high, Reliability.medium, Reliability.medium][rnd.nextInt(3)];
  CheckpointOutcome clean() => rnd.nextInt(5) == 0 ? CheckpointOutcome.unclear : CheckpointOutcome.consistent;
  return [
    photo('device_info', [assess('aw_device_info', CheckpointOutcome.consistent, reliability: rel())]),
    photo('back_sensor', [
      assess('aw_sensor_construction', clean(), reliability: rel()),
      assess('aw_back_engraving', clean(), reliability: rel()),
      if (rnd.nextBool())
        assess('aw_sensor_layout', CheckpointOutcome.inconsistent,
            reliability: Reliability.medium, alternative: 'Could be reflections on the sensor glass.'),
      assess('aw_serial_text', CheckpointOutcome.notVisible),
    ]),
    photo('crown_side', [assess('aw_crown_construction', clean(), reliability: rel())]),
  ];
}

List<PhotoEvidence> replicaRun(Random rnd) => [
      photo('back_sensor', [
        assess('aw_charging_contacts', CheckpointOutcome.inconsistent,
            reliability: rnd.nextInt(4) == 0 ? Reliability.medium : Reliability.high,
            observation: 'Two exposed metal charging pins beside the sensor.'),
        assess('aw_sensor_construction', CheckpointOutcome.inconsistent, reliability: Reliability.medium),
      ]),
      photo('front_display', [
        assess('aw_software_ui', rnd.nextBool() ? CheckpointOutcome.inconsistent : CheckpointOutcome.unclear,
            reliability: Reliability.medium, observation: 'Android-style settings menu.'),
      ]),
    ];

FinalEvaluation checked(EngineResult r) => FinalEvaluation(variationChecks: {
      for (final rec in r.recordsNeedingVariationCheck)
        EvidenceDecisionEngine.recordKey(rec.photoId, rec.featureId): const VariationResult(VariationCheck.ruledOut, ''),
    });

Verdict finalVerdict(List<PhotoEvidence> photos) {
  final p = appleWatchSeries();
  final pre = EvidenceDecisionEngine.evaluate(profile: p, photos: photos);
  return EvidenceDecisionEngine.evaluate(profile: p, photos: photos, finalEvaluation: checked(pre)).verdict;
}

void main() {
  group('Same genuine Apple Watch, 20 noisy runs', () {
    final verdicts = [for (var i = 0; i < 20; i++) finalVerdict(genuineRun(Random(i)))];

    test('is never called a replica', () {
      expect(verdicts, isNot(contains(Verdict.likelyReplica)));
    });

    test('is consistent with authentic in most runs and never alternates with replica', () {
      final authentic = verdicts.where((v) => v == Verdict.likelyAuthentic).length;
      expect(authentic, greaterThanOrEqualTo(15), reason: '$verdicts');
    });
  });

  group('Same replica Apple Watch, 20 noisy runs', () {
    final verdicts = [for (var i = 0; i < 20; i++) finalVerdict(replicaRun(Random(100 + i)))];

    test('is never called authentic', () {
      expect(verdicts, isNot(contains(Verdict.likelyAuthentic)));
    });

    test('is a replica in every run where the decisive detail was read reliably', () {
      expect(verdicts.where((v) => v == Verdict.likelyReplica).length, greaterThanOrEqualTo(15), reason: '$verdicts');
    });
  });

  group('Eyewear identification', () {
    test('sunglasses and eyeglasses map to the eyewear profile', () {
      for (final label in ['Sunglasses', 'Eyeglasses', 'Optical frames']) {
        final id = ProductIdentification.fromJson({
          'status': 'product_detected',
          'reason': 'valid_luxury_product',
          'product_detected': true,
          'product_category': label,
          'brand': 'Ray-Ban',
          'product_name': 'Wayfarer',
          'confidence': 0.9,
        });
        expect(id.resolvedProductCategory, ProductCategory.eyewear, reason: label);
      }
    });
  });

  group('Consistency for engine v3 reports (no numeric confidence)', () {
    AuthenticationReport v3(String id, Verdict verdict, String strength, {int minutesAgo = 0, int strong = 0}) =>
        AuthenticationReport(
          id: id,
          product: appleWatch,
          verdict: verdict,
          overallScore: 0,
          quickSummaryPoints: const [],
          evidenceItems: const [],
          rationale: 'r',
          timestamp: DateTime(2026, 9, 26, 12).subtract(Duration(minutes: minutesAgo)),
          fingerprint: ScanConsistencyService.fingerprint(appleWatch),
          engineVersion: '3.0',
          evidenceStrength: strength,
          analysisLog: {'strongCounterfeitCount': strong, 'flaggedEvidenceIds': const [], 'authenticEvidenceIds': const []},
        );

    test('a moderate earlier authentic result is protected from a weak flip', () {
      final r = ScanConsistencyService.reconcile(
        report: v3('new', Verdict.likelyReplica, 'moderate', strong: 0),
        history: [v3('old', Verdict.likelyAuthentic, 'moderate', minutesAgo: 10)],
        now: DateTime(2026, 9, 26, 12),
      );
      expect(r.verdict, Verdict.inconclusive);
      expect(r.consistency!.flipPrevented, isTrue);
      expect(r.overallScore, 0, reason: 'no percentage is invented for v3 reports');
      expect(r.evidenceStrength, 'limited');
    });

    test('an earlier limited result protects nothing', () {
      final r = ScanConsistencyService.reconcile(
        report: v3('new', Verdict.likelyReplica, 'moderate'),
        history: [v3('old', Verdict.likelyAuthentic, 'limited', minutesAgo: 10)],
        now: DateTime(2026, 9, 26, 12),
      );
      expect(r.verdict, Verdict.likelyReplica);
    });
  });

  group('Consistency across scans (§17-19)', () {
    AuthenticationReport report(
      String id,
      Verdict verdict,
      int confidence, {
      int minutesAgo = 0,
      int strong = 0,
      List<String> flagged = const [],
      List<String> authenticIds = const [],
      List<String> observedText = const [],
      DateTime? now,
    }) {
      final fp = ScanConsistencyService.fingerprint(appleWatch, observedText: observedText);
      return AuthenticationReport(
        id: id,
        product: appleWatch,
        verdict: verdict,
        overallScore: confidence,
        quickSummaryPoints: const [],
        evidenceItems: const [],
        rationale: 'r',
        timestamp: (now ?? DateTime(2026, 9, 26, 12)).subtract(Duration(minutes: minutesAgo)),
        fingerprint: fp,
        engineVersion: '2.0',
        analysisLog: {
          'strongCounterfeitCount': strong,
          'flaggedEvidenceIds': flagged,
          'authenticEvidenceIds': authenticIds,
        },
      );
    }

    final now = DateTime(2026, 9, 26, 12);

    test('a weak new replica result does not overturn a stable authentic one', () {
      final earlier = report('a', Verdict.likelyAuthentic, 88, minutesAgo: 10);
      final flipped = report('b', Verdict.likelyReplica, 62, strong: 1);
      final r = ScanConsistencyService.reconcile(report: flipped, history: [earlier], now: now);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.consistency!.flipPrevented, isTrue);
      expect(r.consistency!.rawVerdict, Verdict.likelyReplica, reason: 'the raw result is kept for the log');
      expect(r.consistency!.sessionVerdict, Verdict.likelyAuthentic);
    });

    test('§18 example 1: authentic, authentic, inconclusive -> session stays authentic', () {
      final s1 = report('s1', Verdict.likelyAuthentic, 88, minutesAgo: 20);
      final s2 = report('s2', Verdict.likelyAuthentic, 84, minutesAgo: 10);
      final s3 = report('s3', Verdict.inconclusive, 55);
      final r = ScanConsistencyService.reconcile(report: s3, history: [s1, s2], now: now);
      expect(r.verdict, Verdict.inconclusive);
      expect(r.consistency!.sessionVerdict, Verdict.likelyAuthentic);
      expect(r.consistency!.sessionScanCount, 3);
    });

    test('§18 example 2: repeated strong counterfeit evidence overrides an earlier authentic result', () {
      final s1 = report('s1', Verdict.likelyAuthentic, 88, minutesAgo: 20);
      // Scan 2 had strong evidence but was held back as inconclusive.
      final s2raw = report('s2', Verdict.likelyReplica, 80, minutesAgo: 10, strong: 1);
      final s2 = ScanConsistencyService.reconcile(report: s2raw, history: [s1], now: now);
      expect(s2.verdict, Verdict.inconclusive);
      final s3raw = report('s3', Verdict.likelyReplica, 82, strong: 1);
      final s3 = ScanConsistencyService.reconcile(report: s3raw, history: [s1, s2], now: now);
      expect(s3.verdict, Verdict.likelyReplica, reason: 'new strong evidence, repeated, can change the result');
      expect(s3.consistency!.sessionVerdict, Verdict.likelyReplica);
    });

    test('§19: a single scan with multiple strong verified indicators overrides immediately', () {
      final earlier = report('a', Verdict.likelyAuthentic, 88, minutesAgo: 10);
      final strong = report('b', Verdict.likelyReplica, 90, strong: 3);
      final r = ScanConsistencyService.reconcile(report: strong, history: [earlier], now: now);
      expect(r.verdict, Verdict.likelyReplica);
      expect(r.consistency!.flipPrevented, isFalse);
    });

    test('replica -> authentic only when the flagged details are now shown and look right', () {
      final earlier = report('a', Verdict.likelyReplica, 85, minutesAgo: 10, flagged: ['front_display', 'side_crown']);
      final partial = report('b', Verdict.likelyAuthentic, 80, authenticIds: ['front_display']);
      expect(ScanConsistencyService.reconcile(report: partial, history: [earlier], now: now).verdict,
          Verdict.inconclusive);
      final full = report('c', Verdict.likelyAuthentic, 80, authenticIds: ['front_display', 'side_crown', 'back_sensor']);
      expect(ScanConsistencyService.reconcile(report: full, history: [earlier], now: now).verdict,
          Verdict.likelyAuthentic);
    });

    test('different serials mean different physical items: no anchoring', () {
      final earlier = report('a', Verdict.likelyAuthentic, 88, minutesAgo: 10, observedText: ['Serial GH7KL2XQ1']);
      final other = report('b', Verdict.likelyReplica, 70, strong: 1, observedText: ['Serial ZZ99PP11AA']);
      final r = ScanConsistencyService.reconcile(report: other, history: [earlier], now: now);
      expect(r.verdict, Verdict.likelyReplica);
      expect(r.consistency!.previousReportId, isNull);
    });

    test('a different physical item of the same model, hours later, is not anchored to it', () {
      // Neither scan ever reads a serial/marking (the common case for a
      // phone photo) - same brand/model is only a guess that they're the
      // same physical watch, and that guess should not hold for long.
      final earlier = report('a', Verdict.likelyAuthentic, 88, minutesAgo: 200);
      final differentWatch = report('b', Verdict.inconclusive, 55);
      final r = ScanConsistencyService.reconcile(report: differentWatch, history: [earlier], now: now);
      expect(r.verdict, Verdict.inconclusive, reason: 'own raw verdict stands, unaffected by the unrelated earlier scan');
      expect(r.consistency!.previousReportId, isNull);
    });

    test('a different physical item of the same model, minutes later (same sitting), is still anchored', () {
      final earlier = report('a', Verdict.likelyAuthentic, 88, minutesAgo: 10);
      final second = report('b', Verdict.inconclusive, 55);
      final r = ScanConsistencyService.reconcile(report: second, history: [earlier], now: now);
      expect(r.consistency!.previousReportId, 'a');
    });

    test('fingerprint is semantic: angle/lighting-independent, brand and category aware', () {
      final a = ScanConsistencyService.fingerprint(appleWatch);
      final b = ScanConsistencyService.fingerprint(appleWatch, analysedModel: 'Series 9 45mm Aluminium');
      expect(a.split('#').first, startsWith('WATCH|apple|'));
      expect(ScanConsistencyService.isSameProduct(a, a), isTrue);
      expect(ScanConsistencyService.isSameProduct(a, ScanConsistencyService.fingerprint(sunglasses)), isFalse);
      expect(b.split('|')[2], contains('series-9'));
    });

    test('results from engine v1 never anchor new results', () {
      final v1 = report('a', Verdict.likelyReplica, 90, minutesAgo: 10);
      final legacy = AuthenticationReport.fromJson({...v1.toJson(), 'engineVersion': '1.0'});
      final fresh = report('b', Verdict.likelyAuthentic, 85);
      final r = ScanConsistencyService.reconcile(report: fresh, history: [legacy], now: now);
      expect(r.verdict, Verdict.likelyAuthentic);
    });
  });

}
