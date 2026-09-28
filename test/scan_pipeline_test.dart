import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/core/config/authenticity_engine_config.dart';
import 'package:replica_detector/core/errors/app_error.dart';
import 'package:replica_detector/models/authentication_assessment.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/evidence_validation.dart';
import 'package:replica_detector/models/product_identification.dart';
import 'package:replica_detector/models/product_identity.dart';
import 'package:replica_detector/repositories/authentication_repository.dart';
import 'package:replica_detector/repositories/gemini_authentication_repository.dart';
import 'package:replica_detector/repositories/history_repository.dart';
import 'package:replica_detector/viewmodels/scan_flow_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini.dart';

// Pipeline tests with a fake Gemini. They check the flow, the requests made
// and error handling; the canned answers are fixtures, not real model output.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GeminiAuthenticationRepository.clearRankingCache();
  });

  ({ScanFlowViewModel vm, FakeGeminiService gemini, FakeImagePreparationService prep, HistoryRepository history}) build({
    Map<String, Object> responses = const {},
    Map<String, Object> errors = const {},
    // These tests exercise the capture flow and the engine v3 final stage,
    // which is kept for side-by-side comparison. The v4 combined stage is
    // covered in combined_final_stage_test.dart.
    FinalStageMode mode = FinalStageMode.legacyTextOnly,
  }) {
    final gemini = FakeGeminiService(responses: responses, errors: errors);
    final prep = FakeImagePreparationService();
    final history = HistoryRepository();
    final repo = AuthenticationRepository(
      geminiRepo: GeminiAuthenticationRepository(geminiService: gemini, imagePrep: prep, finalStageMode: mode),
    );
    return (vm: ScanFlowViewModel(authRepo: repo, historyRepo: history), gemini: gemini, prep: prep, history: history);
  }

  final deviceInfoAnalysis = photoAnalysisJson(
    [assessmentJson('aw_device_info', 'CONSISTENT', basis: 'DEVICE_REPORTED', kind: 'DEVICE_REPORTED')],
    matched: 'device_info',
    observedText: ['Apple Watch Ultra 2', 'MREJ3LL/A'],
    identity: {
      'brand': 'Apple',
      'model_family': 'Apple Watch Ultra',
      'generation': 'Ultra 2',
      'status': 'CONFIRMED',
      'source': 'DEVICE_REPORTED',
      'basis': 'About screen',
    },
  );

  Map<String, Object> happy({
    Object? backAnalysis,
    Object? finalEval,
    Object? check,
  }) =>
      {
        'product_identification': identificationJson(),
        'evidence_recommendation':
            recommendationJson(['back_sensor', 'device_info', 'crown_side', 'front_display', 'band_slot', 'other_side']),
        'photo_analysis:overview': photoAnalysisJson([assessmentJson('aw_software_ui', 'CONSISTENT')], matched: 'front_display'),
        'photo_analysis:back_sensor': backAnalysis ??
            photoAnalysisJson([
              assessmentJson('aw_sensor_construction', 'CONSISTENT'),
              assessmentJson('aw_back_material', 'CONSISTENT'),
              assessmentJson('aw_serial_text', 'NOT_VISIBLE'),
            ], matched: 'back_sensor'),
        'photo_analysis:device_info': deviceInfoAnalysis,
        'evidence_validation': check ?? photoCheckJson(matched: 'back_sensor'),
        'evidence_validation:device_info': photoCheckJson(matched: 'device_info'),
        'multi_image_forensic_observations': finalEval ?? finalEvaluationJson(),
      };

  Future<void> addPhoto(ScanFlowViewModel vm, String path, {bool force = false}) async {
    vm.captureRecommended();
    await vm.submitEvidencePhoto(path);
    await vm.acceptPendingPhoto(force: force);
  }

  group('Stage A: recognition from the first photo', () {
    test('identifies the product with per-attribute certainty and recommends one next photo', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');

      expect(h.vm.currentStep, ScanStep.itemIdentified);
      expect(h.vm.identity!.brand.status, AttributeStatus.confirmed);
      expect(h.vm.identity!.modelFamily.status, AttributeStatus.probable);
      expect(h.vm.identity!.generation.status, AttributeStatus.unknown);
      expect(h.vm.recommendedItem, isNotNull);
      expect(h.vm.recommendedItem!.recommendationReason, isNotEmpty);
      expect(h.vm.photos, hasLength(1), reason: 'the first photo counts as evidence');
      expect(h.vm.photos.first.requestId, 'front_display');
    });

    test('makes one identification call, one text-only recommendation call and one analysis of the first photo', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      expect(h.gemini.callsMatching('product_identification'), 1);
      expect(h.gemini.callsMatching('evidence_recommendation'), 1);
      expect(h.gemini.imagesFor('evidence_recommendation'), 0);
      expect(h.gemini.callsMatching('photo_analysis:overview'), 1);
      expect(h.gemini.imagesFor('photo_analysis:overview'), 1, reason: 'only the original photo, no generated crops');
    });

    test('never invents an identity when the first photo is not a product', () async {
      final h = build(responses: {
        'product_identification': identificationJson(status: 'not_product', reason: 'unsupported_object', productDetected: false),
      });
      await h.vm.captureInitialPhoto(imagePath: '/tmp/desk.jpg');
      expect(h.vm.currentStep, ScanStep.validationFeedback);
      expect(h.vm.currentProduct, isNull);
      expect(h.gemini.callsMatching('evidence_recommendation'), 0);
    });

    test('an unclear brand does not block the scan: category confidence is what gates it', () async {
      final h = build(responses: {
        ...happy(),
        'product_identification': identificationJson(brand: null, brandStatus: 'UNKNOWN', model: null, modelStatus: 'UNKNOWN', type: 'smartwatch'),
      });
      await h.vm.captureInitialPhoto(imagePath: '/tmp/watch.jpg');
      expect(h.vm.currentStep, ScanStep.itemIdentified);
      expect(h.vm.profileName, 'Smartwatch');
    });
  });

  group('Stage B: one informative photo at a time', () {
    test('the checklist lists the most informative photos first, capped at the photo limit', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      final items = h.vm.evidenceItems;
      expect(items.length, lessThanOrEqualTo(AuthenticityEngineConfig.maxPhotosPerScan - 1));
      expect(items.first.id, 'back_sensor', reason: 'highest-ranked photo first');
      expect(items.where((e) => e.hasPhoto), isEmpty, reason: 'the first photo never pre-fills a checklist item');
      expect(h.vm.acceptedEvidenceCount, 0);
      expect(h.vm.checklistProgress, 0);
      expect(h.vm.photoCount + items.length, lessThanOrEqualTo(AuthenticityEngineConfig.maxPhotosPerScan));
    });

    test('each photo is checked and analysed, then the next checklist photo opens (original flow)', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      h.vm.proceedToEvidenceChecklist();
      h.vm.startEvidenceCapture(0);
      expect(h.vm.currentEvidenceItem!.id, 'back_sensor');
      await h.vm.submitEvidencePhoto('/tmp/back.jpg');
      expect(h.vm.currentStep, ScanStep.photoQuality);
      expect(h.vm.pendingEvidence, isNotNull, reason: 'analysed before the user confirms');
      await h.vm.acceptPendingPhoto();

      expect(h.vm.currentStep, ScanStep.guidedCapture, reason: 'advances to the next checklist item');
      expect(h.vm.currentEvidenceIndex, 1);
      expect(h.vm.acceptedEvidenceCount, 1);
      expect(h.vm.checklistProgress, closeTo(1 / h.vm.totalEvidenceCount, 1e-9), reason: 'the camera indicator counts photos taken');
      expect(h.vm.photos.map((p) => p.requestId), ['front_display', 'back_sensor']);
      expect(h.gemini.imagesFor('evidence_validation'), 1);
      expect(h.gemini.imagesFor('photo_analysis:back_sensor'), 1, reason: 'only the original photo is sent; no crops are generated');
    });

    test('"Don\'t have" moves on, and the checklist returns once every item is resolved', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      h.vm.proceedToEvidenceChecklist();
      h.vm.startEvidenceCapture(1);
      for (var i = 0; i < 10 && h.vm.currentStep == ScanStep.guidedCapture; i++) {
        h.vm.markCurrentEvidenceUnavailable();
      }
      expect(h.vm.currentStep, ScanStep.dynamicEvidence);
      expect(h.vm.evidenceItems.skip(1).every((e) => e.isUnavailable), isTrue);
      expect(h.vm.canAnalyze, isTrue);
    });

    test('a photo of a different part is refused, says what it shows and what to photograph instead', () async {
      final h = build(responses: happy(
          check: photoCheckJson(matched: 'crown_side', showsRequested: false, requestedConfidence: 5, partShown: 'side with the crown')));
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      h.vm.startEvidenceCapture(h.vm.evidenceItems.indexWhere((e) => e.id == 'back_sensor'));
      await h.vm.submitEvidencePhoto('/tmp/crown.jpg');
      final v = h.vm.pendingValidation!;
      expect(v.verdict, EvidenceVerdict.rejectedWrongEvidence);
      expect(v.isOverridable, isFalse);
      expect(v.headline, "That's a different part");
      expect(v.guidance, 'This photo shows the side with the crown, but we need the back of the watch.');
      expect(v.callToAction, contains('Photograph the back of your Apple Watch'));
      expect(h.gemini.callsMatching('photo_analysis:back_sensor'), 0, reason: 'a wrong photo is never analysed');
      await h.vm.acceptPendingPhoto(force: true);
      expect(h.vm.photos, hasLength(1), reason: 'it can never be kept');
    });

    test('the right part only counts when it is clearly shown', () async {
      final h = build(responses: happy(check: photoCheckJson(matched: 'back_sensor', showsRequested: true, requestedConfidence: 30)));
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      h.vm.startEvidenceCapture(h.vm.evidenceItems.indexWhere((e) => e.id == 'back_sensor'));
      await h.vm.submitEvidencePhoto('/tmp/far_away.jpg');
      expect(h.vm.pendingValidation!.verdict, EvidenceVerdict.rejectedWrongEvidence);
    });

    test('an unrelated object is refused with a plain message', () async {
      final h = build(responses: happy(
          check: photoCheckJson(matched: 'none', showsProduct: false, showsRequested: false, requestedConfidence: 0, usable: false, partShown: 'a coffee mug')));
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/mug.jpg');
      final v = h.vm.pendingValidation!;
      expect(v.verdict, EvidenceVerdict.rejectedWrongEvidence);
      expect(v.guidance, startsWith('This photo shows a coffee mug, but we need the'));
    });

    test('a photo of a screen or an internet image is refused and cannot be forced in', () async {
      for (final source in ['SCREEN_OR_PRINT', 'INTERNET_IMAGE']) {
        final h = build(responses: happy(check: photoCheckJson(matched: 'back_sensor', source: source)));
        await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
        h.vm.startEvidenceCapture(0);
        await h.vm.submitEvidencePhoto('/tmp/screen.jpg');
        final v = h.vm.pendingValidation!;
        expect(v.verdict, EvidenceVerdict.rejectedWrongEvidence, reason: source);
        expect(v.isOverridable, isFalse);
        expect(v.guidance, contains('a picture from the internet or a screen'));
        expect(v.fix, contains('actual item'));
        await h.vm.acceptPendingPhoto(force: true);
        expect(h.vm.photos, hasLength(1), reason: 'never used as evidence');
        expect(h.gemini.callsMatching('photo_analysis:back_sensor'), 0);
      }
    });

    test('a screenshot is fine for the device information photo, not for other parts', () async {
      final ok = build(responses: {
        ...happy(),
        'evidence_validation:device_info': photoCheckJson(matched: 'device_info', source: 'DEVICE_SCREENSHOT'),
      });
      await ok.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      final idx = ok.vm.evidenceItems.indexWhere((e) => e.id == 'device_info');
      ok.vm.startEvidenceCapture(idx);
      await ok.vm.submitEvidencePhoto('/tmp/about.png');
      expect(ok.vm.pendingValidation!.verdict, EvidenceVerdict.accepted);
      final no = build(responses: happy(check: photoCheckJson(matched: 'back_sensor', source: 'DEVICE_SCREENSHOT')));
      await no.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      no.vm.startEvidenceCapture(0);
      await no.vm.submitEvidencePhoto('/tmp/shot.png');
      expect(no.vm.pendingValidation!.verdict, EvidenceVerdict.rejectedWrongEvidence);
    });

    test('a photo of something else is refused and cannot be forced in', () async {
      final h = build(responses: happy(check: photoCheckJson(matched: 'none', usable: false, showsProduct: false, showsRequested: false, requestedConfidence: 0)));
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      h.vm.captureRecommended();
      await h.vm.submitEvidencePhoto('/tmp/cat.jpg');
      expect(h.vm.pendingValidation!.verdict, EvidenceVerdict.rejectedWrongEvidence);
      expect(h.vm.pendingValidation!.isOverridable, isFalse);
      await h.vm.acceptPendingPhoto(force: true);
      expect(h.vm.photos, hasLength(1));
      expect(h.gemini.callsMatching('photo_analysis:back_sensor'), 0);
    });

    test('an unreadable detail explains exactly what to fix, and can be kept with less weight', () async {
      final h = build(responses: happy(
          check: photoCheckJson(matched: 'back_sensor', readability: 'NOT_READABLE', fix: 'Move closer so the engraving fills the frame.')));
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      h.vm.captureRecommended();
      await h.vm.submitEvidencePhoto('/tmp/far.jpg');
      final v = h.vm.pendingValidation!;
      expect(v.verdict, EvidenceVerdict.rejectedQuality);
      expect(v.guidance, 'Move closer so the engraving fills the frame.');
      await h.vm.acceptPendingPhoto(force: true);
      expect(h.vm.photos.last.keptDespiteLowQuality, isTrue);
    });

    test('the user can skip a request; it is not asked again and counts neither way', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      h.vm.captureRecommended();
      h.vm.markCurrentEvidenceUnavailable();
      expect(h.vm.recommendedItem!.id, isNot('back_sensor'));
      expect(h.vm.engineResult!.counterfeitGroups, isEmpty);
    });

    test('the photo limit is enforced', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      for (var i = 0; i < 10 && h.vm.canAddPhoto && h.vm.recommendedItem != null; i++) {
        await addPhoto(h.vm, '/tmp/p$i.jpg');
      }
      expect(h.vm.photoCount, lessThanOrEqualTo(AuthenticityEngineConfig.maxPhotosPerScan));
    });
  });

  group('Finishing and the final evaluation', () {
    test('the user can finish after the first photo; the result states what is unresolved', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      await h.vm.runAnalysis();
      final r = h.vm.currentReport!;
      expect(r.verdict, Verdict.inconclusive);
      expect(r.assessment!.remainingUncertainty, isNotEmpty);
      expect(r.assessment!.recommendedNextPhoto, isNotNull);
      expect(r.assessment!.recommendedNextPhoto!.optional, isFalse);
    });

    test('two informative photos can reach "consistent with authentic", with the next photo optional', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      await addPhoto(h.vm, '/tmp/back.jpg');
      await addPhoto(h.vm, '/tmp/about.png');
      expect(h.vm.evidenceSufficient, isTrue);
      expect(h.vm.nextPhotoOptional, isTrue);
      await h.vm.runAnalysis();
      final r = h.vm.currentReport!;
      expect(r.verdict, Verdict.likelyAuthentic);
      expect(r.assessment!.verdict, AssessmentVerdict.authenticVisual);
      expect(r.assessment!.manufacturerVerificationStatus, 'NOT_VERIFIED');
      expect(r.assessment!.explanation, contains('not been verified'));
      expect(r.identity?.generation.status ?? h.vm.identity!.generation.status, AttributeStatus.confirmed,
          reason: 'the device screen established the generation');
    });

    test('the final evaluation is one text-only call, reusing earlier analyses instead of re-sending photos', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      await addPhoto(h.vm, '/tmp/back.jpg');
      final analysesBefore = h.gemini.callsMatching('photo_analysis');
      await h.vm.runAnalysis();
      expect(h.gemini.callsMatching('multi_image_forensic_observations'), 1);
      expect(h.gemini.imagesFor('multi_image_forensic_observations'), 0);
      expect(h.gemini.callsMatching('photo_analysis'), analysesBefore);
    });

    test('decisive, variation-checked counterfeit evidence gives Replica', () async {
      final h = build(responses: happy(
        backAnalysis: photoAnalysisJson([
          assessmentJson('aw_back_material', 'INCONSISTENT',
              observation: 'The back plate is light cream plastic.', interpretation: 'Genuine Ultra backs are black ceramic and sapphire.'),
          assessmentJson('aw_back_fasteners', 'INCONSISTENT', observation: 'Flower shapes printed where the four screws should be.'),
        ], matched: 'back_sensor'),
        finalEval: finalEvaluationJson(variations: [
          {'key': 'back_sensor|aw_back_material', 'legitimate_variation': 'RULED_OUT', 'explanation': 'No Ultra has a light plastic back.'},
          {'key': 'back_sensor|aw_back_fasteners', 'legitimate_variation': 'RULED_OUT', 'explanation': 'All Ultra backs have four screws.'},
        ]),
      ));
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      await addPhoto(h.vm, '/tmp/back.jpg');
      expect(h.vm.evidenceSufficient, isTrue);
      await h.vm.runAnalysis();
      final r = h.vm.currentReport!;
      expect(r.verdict, Verdict.likelyReplica);
      expect(r.evidenceStrength, 'strong');
      expect(r.suspiciousFindings.join(' '), contains('cream plastic'));
      expect(r.assessment!.validate(), isEmpty);
    });

    test('when the final check finds a legitimate variation, the result is not forced to Replica', () async {
      final h = build(responses: happy(
        backAnalysis: photoAnalysisJson([assessmentJson('aw_back_material', 'INCONSISTENT')], matched: 'back_sensor'),
        finalEval: finalEvaluationJson(variations: [
          {'key': 'back_sensor|aw_back_material', 'legitimate_variation': 'LIKELY', 'explanation': 'Replacement back cover.'},
        ]),
      ));
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      await addPhoto(h.vm, '/tmp/back.jpg');
      await h.vm.runAnalysis();
      expect(h.vm.currentReport!.verdict, Verdict.inconclusive);
    });

    test('reports carry no numeric confidence, and do carry the structured assessment and API usage', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      await h.vm.runAnalysis();
      final r = h.vm.currentReport!;
      expect(r.engineVersion, AuthenticityEngineConfig.engineVersion);
      expect(r.overallScore, 0);
      expect(r.usesQualitativeStrength, isTrue);
      expect(r.strengthLabel, endsWith('evidence'));
      expect(r.assessment!.validate(), isEmpty);
      final usage = r.analysisLog['api_usage'] as Map;
      expect(usage['call_count'], h.gemini.calls.length);
      expect(usage['token_counts_estimated'], isTrue, reason: 'the fake backend reports no token counts');
    });

    test('a completed report is saved to history, round-trips through JSON, and keeps real paths', () async {
      final h = build(responses: happy());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      await addPhoto(h.vm, '/tmp/back.jpg');
      await h.vm.runAnalysis();
      expect(h.history.allReports, hasLength(1));
      final r = AuthenticationReport.fromJson(h.history.allReports.first.toJson());
      expect(r.assessment!.verdict, h.vm.currentReport!.assessment!.verdict);
      expect(r.evidenceItems.every((e) => e.capturedImagePath.startsWith('/documents/')), isTrue);
    });
  });

  group('Failures surface as failures, never as "Unable to Verify"', () {
    test('an API error in the final evaluation shows an error with retry, not a report', () async {
      final h = build(responses: happy(), errors: {'multi_image_forensic_observations': AppError.serviceUnreachable()});
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      await h.vm.runAnalysis();
      expect(h.vm.currentStep, ScanStep.error);
      expect(h.vm.currentReport, isNull);
      expect(h.history.allReports, isEmpty);
    });

    test('a malformed answer is retried once, then succeeds', () async {
      final h = build(responses: {
        ...happy(),
        'multi_image_forensic_observations': [
          {'unexpected': true},
          finalEvaluationJson(),
        ],
      });
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      await h.vm.runAnalysis();
      expect(h.vm.currentReport, isNotNull);
      expect(h.gemini.callsMatching('multi_image_forensic_observations'), 2);
    });

    test('a final check that omits a variation check is retried, then surfaced as an error', () async {
      final h = build(responses: happy(
        backAnalysis: photoAnalysisJson([assessmentJson('aw_back_material', 'INCONSISTENT')], matched: 'back_sensor'),
        finalEval: finalEvaluationJson(),
      ));
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      await addPhoto(h.vm, '/tmp/back.jpg');
      await h.vm.runAnalysis();
      expect(h.gemini.callsMatching('multi_image_forensic_observations'), 2);
      expect(h.vm.currentStep, ScanStep.error);
      expect(h.vm.currentReport, isNull, reason: 'an incomplete answer never becomes "Unable to Verify"');
    });

    test('repeatedly malformed answers surface as an invalid-response error', () async {
      final h = build(responses: {
        ...happy(),
        'photo_analysis:back_sensor': {'assessments': 'not a list'},
      });
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      h.vm.captureRecommended();
      await h.vm.submitEvidencePhoto('/tmp/back.jpg');
      expect(h.vm.currentStep, ScanStep.error);
      expect(h.vm.appError!.type, AppErrorType.invalidResponse);
      expect(h.vm.photos, hasLength(1));
    });

    test('retry replays the failed step', () async {
      final gemini = FakeGeminiService(responses: happy(), errors: {'evidence_recommendation': AppError.timeout()});
      final repo = AuthenticationRepository(
          geminiRepo: GeminiAuthenticationRepository(geminiService: gemini, imagePrep: FakeImagePreparationService()));
      final vm = ScanFlowViewModel(authRepo: repo, historyRepo: HistoryRepository());
      await vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      expect(vm.currentStep, ScanStep.error);
      gemini.errors.clear();
      await vm.retryLastAction();
      expect(vm.currentStep, ScanStep.itemIdentified);
    });

    test('an identification failure invents no product', () async {
      final h = build(errors: {'product_identification': AppError.timeout()});
      await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
      expect(h.vm.currentStep, ScanStep.error);
      expect(h.vm.currentProduct, isNull);
    });
  });

  test('only gemini-3.1-flash-lite is configured; no other model can be requested', () {
    expect(AuthenticityEngineConfig.defaultModel, 'gemini-3.1-flash-lite');
    expect(AuthenticityEngineConfig.pricePerMillionTokens.keys, ['gemini-3.1-flash-lite']);
  });

  test('starting a new scan clears everything', () async {
    final h = build(responses: happy());
    await h.vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
    await addPhoto(h.vm, '/tmp/back.jpg');
    h.vm.startScan();
    expect(h.vm.currentProduct, isNull);
    expect(h.vm.photos, isEmpty);
    expect(h.vm.evidenceItems, isEmpty);
    expect(h.vm.currentReport, isNull);
    expect(h.vm.pendingValidation, isNull);
    expect(h.vm.currentStep, ScanStep.directScan);
  });

  test('identification parses statuses and never upgrades an ungraded value to confirmed', () {
    final id = ProductIdentification.fromJson({
      ...identificationJson(generation: 'Ultra 2'),
      'generation_status': null,
    });
    expect(id.identity!.generation.status, AttributeStatus.probable);
    expect(id.itemBox, [0.2, 0.25, 0.8, 0.75]);
  });
}

extension on AuthenticationReport {
  ProductIdentity? get identity => product.identity;
}
