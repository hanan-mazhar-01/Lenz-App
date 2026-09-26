// Repeat-scan consistency (§17, §32-33).
//
// The same physical item scanned repeatedly produces slightly different
// Gemini output each time: a detail described as "not visible" one run and
// "missing" the next, glare read as a flaw, a strength over-claimed. These
// tests replay realistic variants of that output for one genuine item and
// require the verdict to stay stable. Every variant is also run through the
// v1 engine (restored from git) so the before/after is measured, not claimed.

import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/data/authentication_rules.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/evidence.dart';
import 'package:replica_detector/models/evidence_finding.dart';
import 'package:replica_detector/models/evidence_observation.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/models/product_identification.dart';
import 'package:replica_detector/services/authentication_scoring_engine.dart';
import 'package:replica_detector/services/scan_consistency_service.dart';

import 'support/fixtures.dart';
import 'support/legacy_scoring_engine_v1.dart';

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

// ------------------------------------------------------------ JSON builders

Map<String, dynamic> f(
  String type,
  String strength,
  String dimension,
  String feature,
  String observation, {
  bool modelSpecific = false,
  String? alt,
}) =>
    {
      'feature': feature,
      'dimension': dimension,
      'type': type,
      'strength': strength,
      'observation': observation,
      'model_specific': modelSpecific,
      'alternative_explanation': alt,
    };

Map<String, dynamic> auth(String dim, String feature, String obs) =>
    f('AUTHENTIC_INDICATOR', 'MODERATE', dim, feature, obs, modelSpecific: true);

Map<String, dynamic> part(String id, String title, List<Map<String, dynamic>> findings, {int quality = 88}) =>
    {'evidence_id': id, 'title': title, 'visible_quality': quality, 'observations': ['$title visible'], 'findings': findings};

/// What a clean analysis of a genuine Apple Watch looks like.
List<Map<String, dynamic>> genuineAppleWatchParts() => [
      part('front_display', 'Front', [
        auth('SHAPE', 'Display bezel', 'Thin, even black border around the curved display'),
        auth('DESIGN', 'Interface', 'watchOS watch face fills the screen as expected for Series 9'),
      ]),
      part('back_sensor', 'Back', [
        auth('PRODUCT_SPECIFIC', 'Sensor layout', 'Sensor window and lens arrangement match Series 9'),
        auth('TYPOGRAPHY', 'Back text', 'Printed text around the sensor is crisp and evenly spaced'),
      ]),
      part('side_crown', 'Crown Side', [
        auth('HARDWARE', 'Digital Crown', 'Crown has fine even ridges and sits where expected'),
        auth('HARDWARE', 'Side button', 'Side button is flush and correctly proportioned'),
      ]),
      part('other_side', 'Other Side', [auth('CONSTRUCTION', 'Speaker openings', 'Speaker openings are cleanly machined')]),
      part('band_connector', 'Band / Connector', [auth('HARDWARE', 'Band slot', 'Band slot edges are clean with flush release button')]),
      part('about_screen', 'About Screen', [auth('SERIAL_MARKING', 'About screen', 'Model shown matches Series 9 45mm')]),
    ];

List<Map<String, dynamic>> withExtra(String evidenceId, List<Map<String, dynamic>> extra, {int? quality}) {
  final parts = genuineAppleWatchParts();
  return [
    for (final p in parts)
      if (p['evidence_id'] == evidenceId)
        {
          ...p,
          'findings': [...(p['findings'] as List), ...extra],
          'visible_quality': ?quality,
        }
      else
        p,
  ];
}

/// One simulated Gemini response variant for the same genuine watch.
class Variant {
  final String name;
  final List<Map<String, dynamic>> parts;
  final int identification;
  final Set<String> notSupplied;
  const Variant(this.name, this.parts, {this.identification = 90, this.notSupplied = const {}});
}

final genuineVariants = <Variant>[
  Variant('clean analysis', genuineAppleWatchParts()),
  Variant('serial "not visible" typed as counterfeit', withExtra('back_sensor', [
    f('COUNTERFEIT_INDICATOR', 'STRONG', 'SERIAL_MARKING', 'Serial number',
        'Serial number is not visible on the back, cannot verify authenticity', modelSpecific: true),
  ])),
  Variant('glare read as a logo flaw', withExtra('front_display', [
    f('COUNTERFEIT_INDICATOR', 'MODERATE', 'LOGO', 'Screen edge',
        'Edge of the display looks uneven, possibly due to glare from the lighting'),
  ])),
  Variant('mechanical-watch rule misapplied (v1 prompt)', withExtra('side_crown', [
    f('COUNTERFEIT_INDICATOR', 'MODERATE', 'HARDWARE', 'Crown knurling',
        'Crown lacks the machined knurling expected on a genuine watch crown'),
  ])),
  Variant('strength over-claimed, not model-specific', withExtra('front_display', [
    f('COUNTERFEIT_INDICATOR', 'STRONG', 'SHAPE', 'Bezel', 'Bezel appears slightly thicker than typical'),
  ])),
  Variant('strong claim with a benign explanation', withExtra('back_sensor', [
    f('COUNTERFEIT_INDICATOR', 'STRONG', 'PRODUCT_SPECIFIC', 'Sensor ring',
        'Sensor ring spacing differs from the Series 9 layout', modelSpecific: true,
        alt: 'Close-up lens distortion can stretch the ring spacing'),
  ])),
  Variant('flaw seen only on a blurry photo', withExtra('band_connector', [
    f('COUNTERFEIT_INDICATOR', 'STRONG', 'HARDWARE', 'Release button',
        'Band release button edge appears rough', modelSpecific: true),
  ], quality: 48)),
  Variant('two complaints about the same area', withExtra('front_display', [
    f('COUNTERFEIT_INDICATOR', 'MODERATE', 'SHAPE', 'Corner radius', 'Corner radius looks tighter than expected'),
    f('COUNTERFEIT_INDICATOR', 'MODERATE', 'SHAPE', 'Glass curve', 'Glass curve looks flatter than expected'),
  ])),
  Variant('model identification uncertain', withExtra('back_sensor', [
    f('COUNTERFEIT_INDICATOR', 'STRONG', 'PRODUCT_SPECIFIC', 'Sensor layout',
        'Sensor layout does not match the Series 9 arrangement', modelSpecific: true),
  ]), identification: 55),
  Variant('model returned fewer findings this run', [
    part('front_display', 'Front', [auth('SHAPE', 'Display bezel', 'Thin, even black border')]),
    part('back_sensor', 'Back', [auth('PRODUCT_SPECIFIC', 'Sensor layout', 'Sensor layout matches Series 9')]),
    part('side_crown', 'Crown Side', [auth('HARDWARE', 'Digital Crown', 'Crown ridges are fine and even')]),
    part('other_side', 'Other Side', const []),
    part('band_connector', 'Band / Connector', const []),
    part('about_screen', 'About Screen', const []),
  ]),
  Variant('about screen not photographed', genuineAppleWatchParts(), notSupplied: {'about_screen'}),
  Variant('legacy untyped output with absence wording', [
    for (final p in genuineAppleWatchParts())
      {
        'evidence_id': p['evidence_id'],
        'title': p['title'],
        'visible_quality': 88,
        'observations': ['visible'],
        'consistent_signals': [for (final x in p['findings'] as List) (x as Map)['observation']],
        'inconsistent_signals': p['evidence_id'] == 'back_sensor'
            ? ['Serial number not clearly visible on the caseback']
            : <String>[],
        'uncertain_signals': <String>[],
      },
  ]),
];

// ----------------------------------------------------------------- running

List<EvidenceItem> planFor(Product product, {Set<String> notSupplied = const {}}) {
  final rules = AuthenticationRules.resolve(
    category: product.category,
    brand: product.brand,
    model: product.model,
    name: product.name,
  );
  return [
    for (final (i, b) in rules.evidenceBlueprint.indexed)
      item(id: b.id, title: b.title, weight: b.weight, index: i + 1, captured: !notSupplied.contains(b.id)),
  ];
}

List<PartObservation> parse(List<Map<String, dynamic>> parts) =>
    GeminiEvidenceResponse.fromJson({'evidence_observations': parts}).partObservations;

({Verdict v1, Verdict v2, int v2Confidence}) score(Product product, Variant variant) {
  final evidence = planFor(product, notSupplied: variant.notSupplied);
  final observations = parse(variant.parts);
  final v1 = LegacyScoringEngineV1.evaluate(
    product: product,
    rawIdentificationConfidence: variant.identification,
    requiredEvidence: evidence,
    capturedImages: imagesFor(evidence),
    observations: observations,
    contradictions: const [],
  );
  final v2 = AuthenticationScoringEngine.evaluate(
    product: product,
    rawIdentificationConfidence: variant.identification,
    requiredEvidence: evidence,
    capturedImages: imagesFor(evidence),
    observations: observations,
    contradictions: const [],
  );
  return (v1: v1.verdict, v2: v2.verdict, v2Confidence: v2.authenticationConfidence);
}

void printTable(String title, List<(String, Verdict, Verdict, int)> rows) {
  final b = StringBuffer('\n$title\n');
  b.writeln('| # | Scan variant | Engine v1 | Engine v2 |');
  b.writeln('|---|---|---|---|');
  for (final (i, r) in rows.indexed) {
    b.writeln('| ${i + 1} | ${r.$1} | ${r.$2.label} | ${r.$3.label} (${r.$4}%) |');
  }
  // ignore: avoid_print
  print(b);
}

void main() {
  group('Same genuine Apple Watch, 12 scans with realistic model variation', () {
    final rows = [
      for (final v in genuineVariants)
        (() {
          final s = score(appleWatch, v);
          return (v.name, s.v1, s.v2, s.v2Confidence);
        })(),
    ];

    test('prints the v1 vs v2 comparison', () {
      printTable('GENUINE Apple Watch - repeated scans', rows);
    });

    test('engine v2 never calls the genuine watch a replica', () {
      for (final r in rows) {
        expect(r.$3, isNot(Verdict.likelyReplica), reason: 'variant "${r.$1}" flipped to replica');
      }
    });

    test('engine v2 never alternates between authentic and replica', () {
      final verdicts = rows.map((r) => r.$3).toSet();
      expect(verdicts.containsAll({Verdict.likelyAuthentic, Verdict.likelyReplica}), isFalse);
    });

    test('engine v2: every scan is Appears Authentic or Unable to Verify', () {
      final authentic = rows.where((r) => r.$3 == Verdict.likelyAuthentic).length;
      final inconclusive = rows.where((r) => r.$3 == Verdict.inconclusive).length;
      expect(authentic + inconclusive, rows.length);
      expect(authentic, greaterThanOrEqualTo(6));
    });

    test('scanned one after another, the session assessment stays Appears Authentic', () {
      final history = <AuthenticationReport>[];
      final start = DateTime(2026, 9, 26, 12);
      final shown = <Verdict>[];
      final session = <Verdict?>[];
      for (final (i, v) in genuineVariants.indexed) {
        final evidence = planFor(appleWatch, notSupplied: v.notSupplied);
        final result = AuthenticationScoringEngine.evaluate(
          product: appleWatch,
          rawIdentificationConfidence: v.identification,
          requiredEvidence: evidence,
          capturedImages: imagesFor(evidence),
          observations: parse(v.parts),
          contradictions: const [],
        );
        final at = start.add(Duration(minutes: i));
        final report = ScanConsistencyService.reconcile(
          report: AuthenticationReport(
            id: 'scan_$i',
            product: appleWatch,
            verdict: result.verdict,
            overallScore: result.authenticationConfidence,
            quickSummaryPoints: const [],
            evidenceItems: const [],
            rationale: result.rationale,
            timestamp: at,
            fingerprint: ScanConsistencyService.fingerprint(appleWatch),
            engineVersion: '2.0',
            analysisLog: {'strongCounterfeitCount': result.strongCounterfeitCount},
          ),
          history: history,
          now: at,
        );
        history.add(report);
        shown.add(report.verdict);
        session.add(report.consistency?.sessionVerdict);
      }
      // ignore: avoid_print
      print('\nSession over 12 scans - shown: ${shown.map((v) => v.code).join(', ')}'
          '\nSession over 12 scans - session assessment: ${session.map((v) => v?.code ?? '-').join(', ')}');
      expect(shown, isNot(contains(Verdict.likelyReplica)));
      expect(session.skip(1).every((v) => v == Verdict.likelyAuthentic), isTrue);
    });

    test('the same noise did flip engine v1 (the bug being fixed)', () {
      final v1Replica = rows.where((r) => r.$2 == Verdict.likelyReplica).length;
      expect(v1Replica, greaterThan(0));
    });
  });

  group('A real replica is still caught', () {
    List<Map<String, dynamic>> replicaParts({bool dropOne = false, bool addNoise = false}) => [
          part('front_display', 'Front', [
            f('COUNTERFEIT_INDICATOR', 'STRONG', 'SHAPE', 'Display', 'Flat rectangular screen with a thick uneven bezel; Series 9 has a curved edge-to-edge display', modelSpecific: true),
            if (addNoise) f('AMBIGUOUS', 'WEAK', 'COLOR_TEXTURE', 'Case colour', 'Case colour hard to judge'),
          ]),
          part('back_sensor', 'Back', [
            if (!dropOne)
              f('COUNTERFEIT_INDICATOR', 'STRONG', 'PRODUCT_SPECIFIC', 'Sensor', 'Plastic back with a single green LED; no real generation has this layout', modelSpecific: true),
          ]),
          part('side_crown', 'Crown Side', [
            f('COUNTERFEIT_INDICATOR', 'STRONG', 'HARDWARE', 'Crown', 'Crown is a smooth plastic knob with no ridges and does not match any Apple Watch generation', modelSpecific: true),
          ]),
          part('other_side', 'Other Side', [
            if (addNoise) auth('CONSTRUCTION', 'Openings', 'Speaker openings present'),
          ]),
          part('band_connector', 'Band / Connector', const []),
          part('about_screen', 'About Screen', [
            f('COUNTERFEIT_INDICATOR', 'STRONG', 'SERIAL_MARKING', 'Interface', 'The About screen is an Android-style menu, not watchOS', modelSpecific: true),
          ]),
        ];

    final variants = [
      Variant('clear replica', replicaParts()),
      Variant('one indicator missing this run', replicaParts(dropOne: true)),
      Variant('with extra ambiguous noise', replicaParts(addNoise: true)),
      Variant('both variations', replicaParts(dropOne: true, addNoise: true)),
      Variant('about screen not photographed', replicaParts(), notSupplied: {'about_screen'}),
    ];
    final rows = [
      for (final v in variants)
        (() {
          final s = score(appleWatch, v);
          return (v.name, s.v1, s.v2, s.v2Confidence);
        })(),
    ];

    test('prints the comparison', () => printTable('REPLICA Apple Watch - repeated scans', rows));

    test('never Appears Authentic, and consistently Likely Replica', () {
      for (final r in rows) {
        expect(r.$3, Verdict.likelyReplica, reason: 'variant "${r.$1}"');
      }
    });
  });

  group('Eyewear has its own pipeline (§5)', () {
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
      final coded = ProductIdentification.fromJson({
        'status': 'product_detected',
        'product_detected': true,
        'category_code': 'SUNGLASSES',
        'product_category': 'Sunglasses',
        'brand': 'Ray-Ban',
        'confidence': 0.9,
      });
      expect(coded.toProduct(imageAsset: '/tmp/x.jpg').categoryCode, 'SUNGLASSES');
    });

    test('eyewear checklist covers temples, hinge, markings and lens logo', () {
      final ids = AuthenticationRules.forCategory(ProductCategory.eyewear).evidenceBlueprint.map((b) => b.id).toList();
      expect(ids, containsAll(['front_frame', 'temple_outside', 'inside_temple_markings', 'hinge', 'lens_logo']));
      final rules = AuthenticationRules.forCategory(ProductCategory.eyewear);
      expect(rules.cautions.join(' ').toLowerCase(), contains('reflection'));
      expect(rules.identityEvidenceIds, contains('inside_temple_markings'));
    });

    test('reflections on genuine sunglasses never produce a replica verdict', () {
      final parts = [
        part('front_frame', 'Front', [
          auth('SHAPE', 'Frame', 'Frame shape and symmetry match the RB2140 Wayfarer'),
          f('COUNTERFEIT_INDICATOR', 'MODERATE', 'COLOR_TEXTURE', 'Lens tint', 'Lens tint looks more blue than G-15 because of reflections'),
        ]),
        part('temple_outside', 'Side / Arm', [auth('LOGO', 'Temple logo', 'Metal Ray-Ban plaque is level and cleanly inset')]),
        part('inside_temple_markings', 'Inside Arms', [
          auth('SERIAL_MARKING', 'Markings', 'RB2140 901 50-22 printed crisply in the usual layout'),
        ]),
        part('hinge', 'Hinge', [auth('HARDWARE', 'Hinge', 'Seven-barrel style hinge with clean screws')]),
        part('bridge_nose_pads', 'Nose Area', [auth('CONSTRUCTION', 'Bridge', 'Moulded bridge, no pads, as expected')]),
        part('lens_logo', 'Lens Logo', [
          f('COUNTERFEIT_INDICATOR', 'STRONG', 'LOGO', 'Lens etching', 'Lens etching is not visible in this photo', modelSpecific: true),
        ]),
      ];
      final s = score(sunglasses, Variant('reflections + unreadable lens etching', parts));
      expect(s.v2, isNot(Verdict.likelyReplica));
    });
  });

  group('Missing evidence is uncertainty, never counterfeit evidence (§3)', () {
    for (final text in [
      'Serial number not visible',
      'Box not provided',
      'Engraving cannot be read at this distance',
      'Stitching is obscured by the strap',
      'Authentication tag not shown in the photos',
      'Unable to verify the model code',
    ]) {
      test('"$text" is reclassified as missing', () {
        final r = AuthenticationScoringEngine.evaluate(
          product: testWatch,
          rawIdentificationConfidence: 90,
          requiredEvidence: fullWatchEvidence(),
          capturedImages: imagesFor(fullWatchEvidence()),
          observations: [
            ...cleanWatchObservations().where((o) => o.evidenceId != 'reference_serial'),
            typedObservation('reference_serial', 'Reference / Serial', [
              finding('reference_serial', FindingType.counterfeitIndicator,
                  strength: FindingStrength.strong, dimension: 'SERIAL_MARKING', observation: text, modelSpecific: true),
            ]),
          ],
          contradictions: const [],
        );
        expect(r.suspiciousFindings, isEmpty);
        expect(r.verdict, isNot(Verdict.likelyReplica));
        final normalized = r.normalizedFindings.firstWhere((f) => f.observation == text);
        expect(normalized.type, FindingType.missing);
      });
    }
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

  group('No fabricated verification (§28-29)', () {
    test('a visible serial is reported as observed text only', () {
      final r = AuthenticationScoringEngine.evaluate(
        product: appleWatch,
        rawIdentificationConfidence: 90,
        requiredEvidence: planFor(appleWatch),
        capturedImages: imagesFor(planFor(appleWatch)),
        observations: parse(genuineAppleWatchParts()),
        contradictions: const [],
        analysis: GeminiEvidenceResponse.fromJson({
          'evidence_observations': genuineAppleWatchParts(),
          'observed_text': ['Serial GH7KL2XQ1'],
          'identification': {'category': 'WATCH', 'model_confirmed': true, 'model_confidence': 90},
        }),
      );
      expect(r.limitations.join(' '), contains('has not been checked with the brand'));
      expect(r.rationale.toLowerCase(), isNot(contains('database')));
    });
  });
}
