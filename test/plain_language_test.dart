import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/data/authentication_rules.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/evidence.dart';
import 'package:replica_detector/models/evidence_validation.dart';
import 'package:replica_detector/models/photo_quality.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/data/evidence_profiles.dart';
import 'package:replica_detector/models/evidence_record.dart';
import 'package:replica_detector/services/assessment_builder.dart';
import 'package:replica_detector/services/evidence_decision_engine.dart';

import 'support/fixtures.dart';

/// Terms a normal user should never meet in the interface (§1).
const _bannedInUi = [
  'production identifier',
  'model-specific',
  'reference area',
  'hardware geometry',
  'case geometry',
  'construction characteristic',
  'component relationship',
  'manufacturing marker',
  'typography consistency',
  'authentication evidence',
  'evidence type mismatch',
  'cross-evidence contradiction',
  'evidence coverage insufficient',
  'visual entropy',
  'feature extraction',
  'object segmentation',
  'forensic',
];

void expectPlain(String text, {String? where}) {
  final lower = text.toLowerCase();
  for (final term in _bannedInUi) {
    expect(lower, isNot(contains(term)),
        reason: '"$term" leaked into user-facing text${where == null ? '' : ' ($where)'}: "$text"');
  }
}

void main() {
  group('Evidence requests read like a person wrote them (§2, §3, §11, §12)', () {
    test('every blueprint has a short title, one-line guide and one-line why', () {
      for (final c in ProductCategory.values) {
        for (final b in AuthenticationRules.forCategory(c).evidenceBlueprint) {
          expectPlain(b.title, where: '${c.label} title');
          expectPlain(b.guide, where: '${c.label} guide');
          expectPlain(b.why, where: '${c.label} why');

          expect(b.title.split(' ').length, lessThanOrEqualTo(4),
              reason: 'Title too long: "${b.title}"');
          expect('.'.allMatches(b.guide).length, lessThanOrEqualTo(2),
              reason: 'Guide should be 1-2 short sentences: "${b.guide}"');
          expect(b.guide.length, lessThanOrEqualTo(90), reason: b.guide);
          expect(b.why.length, lessThanOrEqualTo(70), reason: b.why);
          expect(b.why, isNotEmpty);
        }
      }
    });

    test('the spec\'s example titles are the ones actually used (§5-§8)', () {
      String titlesOf(ProductCategory c) =>
          AuthenticationRules.forCategory(c).evidenceBlueprint.map((e) => e.title).join('|');

      expect(titlesOf(ProductCategory.watches),
          'Full Watch|Dial|Crown|Back|Bracelet / Clasp|Number / Engraving');
      expect(titlesOf(ProductCategory.bags),
          'Full Bag|Logo|Inside|Tag / Number|Stitching|Zipper / Hardware');
      expect(titlesOf(ProductCategory.sneakers),
          'Full Shoe|Logo|Size Tag|Stitching|Bottom|Box Label');
      expect(titlesOf(ProductCategory.clothing),
          'Full Item|Logo / Design|Neck Tag|Wash Tag|Stitching|Print / Embroidery');
    });

    test('each category asks for 4-6 photos, never more (§17)', () {
      for (final c in ProductCategory.values) {
        final n = AuthenticationRules.forCategory(c).evidenceBlueprint.length;
        expect(n, inInclusiveRange(4, 6), reason: '${c.label} asks for $n photos');
      }
    });

    test('the watch guides match the spec examples (§5)', () {
      final watch = AuthenticationRules.forCategory(ProductCategory.watches).evidenceBlueprint;
      expect(watch[0].guide, 'Take a photo of the whole watch.');
      expect(watch[1].guide, 'Take a close-up of the front of the watch.');
      expect(watch[2].guide, 'Take a close-up of the small knob on the side.');
      expect(watch[3].guide, 'Turn the watch over and take a photo of the back.');
    });
  });

  group('Importance reads as an invitation, not a demand (§18)', () {
    test('no weight is labelled Required or Mandatory', () {
      for (final w in EvidenceWeight.values) {
        expect(w.userLabel.toLowerCase(), isNot(contains('mandatory')));
        expect(w.userLabel.toLowerCase(), isNot(contains('required')));
        expect(w.userLabel.toLowerCase(), isNot(contains('critical')));
      }
      expect(EvidenceWeight.critical.userLabel, 'Needed');
      expect(EvidenceWeight.medium.userLabel, 'Helpful');
      expect(EvidenceWeight.low.userLabel, 'Optional');
    });

    test('the internal weights are untouched, so scoring is unaffected (§26, §32)', () {
      expect(EvidenceWeight.critical.factor, 1.0);
      expect(EvidenceWeight.low.factor, 0.2);
      expect(EvidenceWeight.critical.label, 'Critical');
    });
  });

  group('The engine stays technical where the user cannot see it (§26, §32)', () {
    test('the model briefing keeps the strict terminology', () {
      final briefing = AuthenticationRules.forCategory(ProductCategory.bags).inspectionBriefing;
      expect(briefing, contains('TYPOGRAPHY'));
      expect(briefing, contains('kerning'));
      expect(briefing, contains('expected on genuine'));
    });

    test('but every rule also carries a plain tip for the user (§25)', () {
      for (final c in ProductCategory.values) {
        for (final r in AuthenticationRules.forCategory(c).inspectionRules) {
          expect(r.simpleTip, isNotEmpty);
          expectPlain(r.simpleTip, where: '${c.label} tip');
          expect(r.simpleTip.length, lessThanOrEqualTo(110), reason: r.simpleTip);
        }
      }
    });

    test('dimension names have a plain alias for display', () {
      expect(InspectionDimension.typography.simpleLabel, 'Lettering');
      expect(InspectionDimension.hardware.simpleLabel, 'Metal parts');
      expect(InspectionDimension.serial.simpleLabel, 'Numbers and engraving');
    });
  });

  group('Rejection and quality messages sound human (§21, §22)', () {
    EvidenceValidationResult make(Map<String, dynamic> json) =>
        EvidenceValidationResult.fromJson(json,
            requestedEvidenceId: 'dial', requestedEvidenceTitle: 'Dial');

    test('wrong-part message names both parts in everyday words', () {
      final r = make({
        'evidence_type_detected': 'back of the watch',
        'match_to_requested_evidence': false,
        'photo_quality_score': 90,
      });
      expect(r.guidance, 'This photo shows the back of the watch, but we need the dial.');
      expectPlain(r.headline);
      expectPlain(r.guidance);
      expectPlain(r.callToAction);
    });

    test('quality fixes are short and actionable', () {
      final tooFar = PhotoQualityResult.fromJson({
        'photo_quality_score': 50,
        'sharpness': 80,
        'lighting': 80,
        'framing': 80,
        'detail': 20,
      });
      expect(tooFar.firstFix, 'Move a little closer');

      final badFraming = PhotoQualityResult.fromJson({
        'photo_quality_score': 50,
        'sharpness': 80,
        'lighting': 80,
        'framing': 20,
        'detail': 80,
      });
      expect(badFraming.firstFix, 'Keep the whole item in frame');

      final great = PhotoQualityResult.fromJson({
        'photo_quality_score': 93,
        'sharpness': 93,
        'lighting': 92,
        'framing': 94,
        'detail': 93,
      });
      expect(great.firstFix, isNull);
      expect(great.simpleSummary, 'Clear and easy to check');
    });

    test('usefulness is explained without jargon', () {
      final goodPhotoWrongView = make({
        'evidence_type_detected': 'dial',
        'match_to_requested_evidence': true,
        'match_confidence': 70,
        'photo_quality_score': 90,
        'sharpness': 90,
        'lighting': 90,
        'framing': 90,
        'detail': 90,
        'authentication_usefulness': 30,
      });
      expect(goodPhotoWrongView.usefulnessLabel, 'Not much to go on');
      expect(goodPhotoWrongView.usefulnessExplanation,
          "Good photo, but this view doesn't show enough of the detail we need.");
    });
  });

  group('The report explains itself in plain words (§24)', () {
    EngineResult run(ResolvedProfile p, List<PhotoEvidence> photos) =>
        EvidenceDecisionEngine.evaluate(profile: p, photos: photos);

    String explain(ResolvedProfile p, EngineResult r) =>
        AssessmentBuilder.explanation(result: r, modelLabel: p.evaluatedModelLabel, brand: p.identity.brand.value ?? '');

    test('every generated sentence avoids technical vocabulary', () {
      final p = appleWatch();
      final r = run(p, [
        photo('device_info', [assess('aw_device_info', CheckpointOutcome.consistent)]),
        photo('back_sensor', [assess('aw_sensor_construction', CheckpointOutcome.consistent)]),
      ]);
      expectPlain(explain(p, r), where: 'explanation');
      for (final u in r.remainingUncertainty) {
        expectPlain(u, where: 'uncertainty');
      }
      for (final g in r.gaps) {
        expectPlain(g.description, where: 'gap');
      }
    });

    test('an unresolved result says what is missing in plain words', () {
      final p = appleWatch();
      final r = run(p, [photo('front_display', [assess('aw_software_ui', CheckpointOutcome.consistent)])]);
      final text = explain(p, r);
      expect(r.verdict, Verdict.inconclusive);
      expect(text, contains('information screen'));
      expect(text, isNot(contains('Ultra Ultra')));
      expectPlain(text);
    });

    test('photo requests and their reasons are written for a person holding the item', () {
      for (final profile in EvidenceProfileRegistry.profiles) {
        for (final req in profile.requests) {
          expectPlain(req.title, where: '${profile.id}/${req.id} title');
          expectPlain(req.instruction, where: '${profile.id}/${req.id} instruction');
          expectPlain(req.why, where: '${profile.id}/${req.id} why');
          expect(req.title.split(' ').length, lessThanOrEqualTo(5), reason: req.title);
        }
      }
    });
  });

  group('Camera guides adapt to the requested part (§14)', () {
    test('a dial gets a circle, a tag gets a small rectangle, full item gets a big frame', () {
      expect(CaptureFrame.forEvidence('dial', title: 'Dial'), CaptureFrame.circle);
      expect(CaptureFrame.forEvidence('caseback', title: 'Back'), CaptureFrame.circle);
      expect(CaptureFrame.forEvidence('size_tag', title: 'Size Tag'), CaptureFrame.smallRect);
      expect(CaptureFrame.forEvidence('box_label', title: 'Box Label'), CaptureFrame.smallRect);
      expect(CaptureFrame.forEvidence('full_watch', title: 'Full Watch'), CaptureFrame.fullItem);
      expect(CaptureFrame.forEvidence('stitching', title: 'Stitching'), CaptureFrame.closeUp);
      expect(CaptureFrame.forEvidence('interior', title: 'Inside'), CaptureFrame.tall);
    });

    test('an unknown id still gets a usable frame', () {
      final frame = CaptureFrame.forEvidence('mystery_angle', title: 'Something');
      expect(frame.widthFactor, greaterThan(0));
      expect(frame.aspect, greaterThan(0));
    });
  });
}
