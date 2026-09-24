import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/evidence.dart';
import 'package:replica_detector/models/evidence_observation.dart';
import 'package:replica_detector/services/authentication_scoring_engine.dart';

import 'support/fixtures.dart';

ScoringEngineResult run({
  required List<EvidenceItem> evidence,
  required List<PartObservation> observations,
  List<CrossImageContradiction> contradictions = const [],
  int identification = 91,
}) {
  return AuthenticationScoringEngine.evaluate(
    product: testWatch,
    rawIdentificationConfidence: identification,
    requiredEvidence: evidence,
    capturedImages: imagesFor(evidence),
    observations: observations,
    contradictions: contradictions,
  );
}

void main() {
  group('QA 1 — consistent evidence across a complete submission (§53)', () {
    test('reaches Likely Authentic but never claims certainty', () {
      final r = run(evidence: fullWatchEvidence(), observations: cleanWatchObservations());

      expect(r.verdict, Verdict.likelyAuthentic);
      expect(r.authenticationConfidence, greaterThanOrEqualTo(72));
      expect(r.authenticationConfidence, lessThanOrEqualTo(94),
          reason: '100% certainty must be unreachable (§24)');
      expect(r.coveredCount, 6);
      expect(r.positiveFindings, isNotEmpty);
    });

    test('verdict label never promises a guarantee', () {
      final r = run(evidence: fullWatchEvidence(), observations: cleanWatchObservations());
      expect(r.verdict.label, 'Likely Authentic');
      for (final v in Verdict.values) {
        expect(v.label.toLowerCase(), isNot(contains('guarantee')));
        expect(v.label, isNot(contains('100')));
      }
    });
  });

  group('QA 2 — known replica signals (§29)', () {
    test('inconsistencies on a critical angle produce Likely Replica', () {
      final observations = [
        observation(id: 'full_watch', title: 'Full Watch', consistent: ['Case shape is close to reference']),
        observation(id: 'dial', title: 'Dial', inconsistent: [
          'Coronet is malformed with a filled centre',
          'SWISS MADE text sits too far from the minute track',
        ]),
        observation(id: 'crown', title: 'Crown', inconsistent: ['Knurling shows casting burrs']),
        observation(id: 'caseback', title: 'Caseback', consistent: ['Caseback is unengraved']),
        observation(id: 'bracelet_clasp', title: 'Bracelet & Clasp', inconsistent: ['Links rattle and end links gap at the lugs']),
        observation(id: 'reference_serial', title: 'Reference / Serial', inconsistent: ['Serial is shallow etched and the wrong length']),
      ];

      final r = run(evidence: fullWatchEvidence(), observations: observations);

      expect(r.verdict, Verdict.likelyReplica);
      expect(r.suspiciousFindings.length, greaterThanOrEqualTo(4));
      expect(r.authenticationConfidence, lessThanOrEqualTo(94));
    });

    test('the verdict is not hardcoded — the same images with clean observations pass', () {
      final evidence = fullWatchEvidence();
      final replica = run(evidence: evidence, observations: [
        observation(id: 'dial', title: 'Dial', inconsistent: ['Dial print bleeds at the edges']),
        observation(id: 'reference_serial', title: 'Reference / Serial', inconsistent: ['Wrong serial format']),
        ...cleanWatchObservations().where((o) => o.evidenceId != 'dial' && o.evidenceId != 'reference_serial'),
      ]);
      final genuine = run(evidence: evidence, observations: cleanWatchObservations());

      expect(replica.verdict, Verdict.likelyReplica);
      expect(genuine.verdict, Verdict.likelyAuthentic);
    });
  });

  group('QA 3 — a flawless photo of a fake is still investigated (§51, §39)', () {
    test('perfect image quality does not lift a flagged item to authentic', () {
      final evidence = fullWatchEvidence(quality: 99);
      final observations = [
        ...cleanWatchObservations().where((o) => o.evidenceId != 'dial'),
        observation(id: 'dial', title: 'Dial', inconsistent: ['Marker alignment is visibly rotated']),
      ];

      final r = run(evidence: evidence, observations: observations);

      expect(r.verdict, isNot(Verdict.likelyAuthentic),
          reason: 'A 99% quality photo of a flawed dial must not read as authentic');
      expect(r.verdict, Verdict.likelyReplica);
    });

    test('image quality and authenticity move independently', () {
      final lowQualityClean = run(
        evidence: fullWatchEvidence(quality: 68),
        observations: cleanWatchObservations(),
      );
      final highQualityFlawed = run(
        evidence: fullWatchEvidence(quality: 98),
        observations: [
          ...cleanWatchObservations().where((o) => o.evidenceId != 'reference_serial'),
          observation(id: 'reference_serial', title: 'Reference / Serial', inconsistent: ['Serial font is wrong for this reference']),
        ],
      );

      expect(lowQualityClean.verdict, Verdict.likelyAuthentic);
      expect(highQualityFlawed.verdict, Verdict.likelyReplica);
    });
  });

  group('QA 4 — insufficient evidence (§26, §52)', () {
    test('2 of 6 angles cannot yield a confident authentic result', () {
      final evidence = [
        item(id: 'full_watch', title: 'Full Watch', weight: EvidenceWeight.high, index: 1),
        item(id: 'crown', title: 'Crown', weight: EvidenceWeight.high, index: 2),
        item(id: 'dial', title: 'Dial', weight: EvidenceWeight.critical, index: 3, captured: false),
        item(id: 'caseback', title: 'Caseback', weight: EvidenceWeight.high, index: 4, captured: false),
        item(id: 'bracelet_clasp', title: 'Bracelet & Clasp', weight: EvidenceWeight.medium, index: 5, captured: false),
        item(id: 'reference_serial', title: 'Reference / Serial', weight: EvidenceWeight.critical, index: 6, captured: false),
      ];
      final observations = [
        observation(id: 'full_watch', title: 'Full Watch', consistent: ['Proportions look correct', 'Finish is even']),
        observation(id: 'crown', title: 'Crown', consistent: ['Crown machining is clean', 'Logo relief is sharp']),
      ];

      final r = run(evidence: evidence, observations: observations);

      expect(r.verdict, Verdict.inconclusive);
      expect(r.authenticationConfidence, lessThan(70));
      expect(r.coveredCount, 2);
      expect(r.totalCount, 6);
      expect(r.evidenceCoverageText, '2 of 6 photos added');
      expect(r.missingEvidenceDescriptions.length, 4);
    });

    test('missing critical evidence alone blocks Likely Authentic (§55)', () {
      final evidence = fullWatchEvidence()
          .map((e) => e.id == 'reference_serial'
              ? item(id: 'reference_serial', title: 'Reference / Serial', weight: EvidenceWeight.critical, index: 6, captured: false)
              : e)
          .toList();

      final r = run(evidence: evidence, observations: cleanWatchObservations());

      expect(r.verdict, Verdict.inconclusive);
      expect(r.missingEvidenceDescriptions.single, contains('Reference / Serial'));
      expect(r.nextChecks.join(' ').toLowerCase(), contains('reference / serial'));
      expect(r.nextChecks.first.toLowerCase(), startsWith('add a photo of'));
    });
  });

  group('QA 5 — declared-unavailable evidence (§27)', () {
    test('"I do not have this" lowers coverage and never counts as passing', () {
      final evidence = fullWatchEvidence()
          .map((e) => e.id == 'reference_serial'
              ? item(
                  id: 'reference_serial',
                  title: 'Reference / Serial',
                  weight: EvidenceWeight.critical,
                  index: 6,
                  captured: false,
                  unavailable: true,
                )
              : e)
          .toList();

      final r = run(evidence: evidence, observations: cleanWatchObservations());

      expect(r.verdict, Verdict.inconclusive);
      expect(r.coveredCount, 5);
      expect(r.missingEvidenceDescriptions.single, contains("you told us you don't have this"));
      final scored = r.scoredEvidenceItems.firstWhere((e) => e.id == 'reference_serial');
      expect(scored.status, EvidenceStatus.unavailable);
      expect(scored.score, 0, reason: 'Unavailable evidence must not score as passing');
    });
  });

  group('QA 6 — contradictory evidence (§54)', () {
    test('a critical cross-image conflict prevents an authentic verdict', () {
      final r = run(
        evidence: fullWatchEvidence(),
        observations: cleanWatchObservations(),
        contradictions: [
          const CrossImageContradiction(
            description: 'The reference on the caseback does not match the dial variant.',
            involvedPartIds: ['caseback', 'dial'],
            severity: ContradictionSeverity.critical,
          ),
        ],
      );

      expect(r.verdict, isNot(Verdict.likelyAuthentic));
      expect(r.contradictionDescriptions, hasLength(1));
    });

    test('a moderate conflict blocks authentic and lowers confidence', () {
      final clean = run(evidence: fullWatchEvidence(), observations: cleanWatchObservations());
      final conflicted = run(
        evidence: fullWatchEvidence(),
        observations: cleanWatchObservations(),
        contradictions: [
          const CrossImageContradiction(
            description: 'Bracelet finish differs between the full shot and the clasp shot.',
            involvedPartIds: ['full_watch', 'bracelet_clasp'],
            severity: ContradictionSeverity.moderate,
          ),
        ],
      );

      expect(clean.verdict, Verdict.likelyAuthentic);
      expect(conflicted.verdict, Verdict.inconclusive);
      expect(conflicted.authenticationConfidence, lessThan(clean.authenticationConfidence));
    });
  });

  group('QA 7 — poor image quality (§50)', () {
    test('a blurry kept photo is trusted less than a sharp one', () {
      final sharp = run(evidence: fullWatchEvidence(quality: 92), observations: cleanWatchObservations());

      final blurryEvidence = fullWatchEvidence(quality: 92)
          .map((e) => e.id == 'dial'
              ? item(id: 'dial', title: 'Dial', weight: EvidenceWeight.critical, index: 2, quality: 30, keptLowQuality: true)
              : e)
          .toList();
      final blurry = run(evidence: blurryEvidence, observations: cleanWatchObservations());

      expect(blurry.authenticationConfidence, lessThan(sharp.authenticationConfidence));
      final scored = blurry.scoredEvidenceItems.firstWhere((e) => e.id == 'dial');
      expect(scored.keptDespiteLowQuality, isTrue);
    });

    test('uniformly poor quality cannot produce Likely Authentic', () {
      final r = run(evidence: fullWatchEvidence(quality: 35), observations: cleanWatchObservations());
      expect(r.verdict, Verdict.inconclusive);
    });
  });

  group('QA 8 — unknown / weak identification (§55)', () {
    test('low identification confidence blocks an authentic verdict', () {
      final r = run(
        evidence: fullWatchEvidence(),
        observations: cleanWatchObservations(),
        identification: 25,
      );
      expect(r.verdict, Verdict.inconclusive);
      expect(r.identificationConfidence, 25);
      expect(r.rationale.toLowerCase(), contains("couldn't tell exactly what this item is"));
    });

    test('identification confidence is reported separately from authentication', () {
      final r = run(evidence: fullWatchEvidence(), observations: cleanWatchObservations(), identification: 91);
      expect(r.identificationConfidence, 91);
      expect(r.authenticationConfidence, isNot(91),
          reason: 'Authentication must be computed, not copied from identification');
    });
  });

  group('Evidence weighting (§21)', () {
    test('a flaw on packaging is not treated like a flaw on a critical angle', () {
      final base = [
        item(id: 'full_watch', title: 'Full Watch', weight: EvidenceWeight.high, index: 1),
        item(id: 'dial', title: 'Dial', weight: EvidenceWeight.critical, index: 2),
        item(id: 'crown', title: 'Crown', weight: EvidenceWeight.high, index: 3),
        item(id: 'caseback', title: 'Caseback', weight: EvidenceWeight.high, index: 4),
        item(id: 'reference_serial', title: 'Reference / Serial', weight: EvidenceWeight.critical, index: 5),
        item(id: 'packaging', title: 'Box & Papers', weight: EvidenceWeight.low, index: 6),
      ];

      final packagingFlaw = run(evidence: base, observations: [
        ...cleanWatchObservations().where((o) => o.evidenceId != 'bracelet_clasp'),
        observation(id: 'packaging', title: 'Box & Papers', inconsistent: ['Box label print is slightly soft']),
      ]);

      final dialFlaw = run(evidence: base, observations: [
        ...cleanWatchObservations().where((o) => o.evidenceId != 'bracelet_clasp' && o.evidenceId != 'dial'),
        observation(id: 'dial', title: 'Dial', inconsistent: ['Dial print is visibly soft']),
        observation(id: 'packaging', title: 'Box & Papers', consistent: ['Label matches the reference']),
      ]);

      expect(dialFlaw.verdict, Verdict.likelyReplica,
          reason: 'A flaw on a critical angle is decisive');
      expect(packagingFlaw.authenticationConfidence,
          isNot(equals(dialFlaw.authenticationConfidence)));
      expect(packagingFlaw.verdict, isNot(Verdict.likelyReplica),
          reason: 'A soft box label alone must not condemn the item');
    });
  });

  group('Narrative is evidence-specific (§35, §37, §43)', () {
    test('rationale names the actual product and the actual findings', () {
      final r = run(evidence: fullWatchEvidence(), observations: cleanWatchObservations());
      expect(r.rationale, contains('your Rolex Submariner Date'));
      expect(r.rationale, isNot(contains('The product looks good')));
      expect(r.rationale.toLowerCase(), contains('6 photos you added'));
    });

    test('an inconclusive rationale states what was missing', () {
      final evidence = fullWatchEvidence()
          .map((e) => e.id == 'dial'
              ? item(id: 'dial', title: 'Dial', weight: EvidenceWeight.critical, index: 2, captured: false)
              : e)
          .toList();
      final r = run(evidence: evidence, observations: cleanWatchObservations());

      expect(r.rationale, contains('Dial'));
      expect(r.rationale.toLowerCase(), contains("we're missing"));
    });

    test('unclear observations surface separately from suspicious ones', () {
      final r = run(evidence: fullWatchEvidence(), observations: [
        ...cleanWatchObservations().where((o) => o.evidenceId != 'reference_serial'),
        observation(id: 'reference_serial', title: 'Reference / Serial', uncertain: ['Serial is out of focus and cannot be read']),
      ]);

      expect(r.unclearFindings, isNotEmpty);
      expect(r.unclearFindings.first, contains('Reference / Serial'));
      expect(r.suspiciousFindings, isEmpty);
      expect(r.verdict, Verdict.inconclusive);
    });
  });
}
