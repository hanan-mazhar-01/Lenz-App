import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/core/config/authenticity_engine_config.dart';
import 'package:replica_detector/core/errors/app_error.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/product_reference.dart';
import 'package:replica_detector/repositories/authentication_repository.dart';
import 'package:replica_detector/repositories/gemini_authentication_repository.dart';
import 'package:replica_detector/repositories/history_repository.dart';
import 'package:replica_detector/viewmodels/scan_flow_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini.dart';

// Engine v4 final stage through the real view model and repository, with a
// fake backend. Checks requests, fallbacks and error handling; the canned
// answers are fixtures, not real model output.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GeminiAuthenticationRepository.clearRankingCache();
  });

  ({ScanFlowViewModel vm, FakeGeminiService gemini, HistoryRepository history, GeminiAuthenticationRepository repo}) build({
    Map<String, Object> responses = const {},
    Map<String, Object> errors = const {},
  }) {
    final gemini = FakeGeminiService(responses: responses, errors: errors);
    final history = HistoryRepository();
    final repo = GeminiAuthenticationRepository(geminiService: gemini, imagePrep: FakeImagePreparationService());
    return (
      vm: ScanFlowViewModel(authRepo: AuthenticationRepository(geminiRepo: repo), historyRepo: history),
      gemini: gemini,
      history: history,
      repo: repo,
    );
  }

  Map<String, Object> responses({Object? combined}) => {
        'product_identification': identificationJson(),
        'evidence_recommendation': recommendationJson(['back_sensor', 'device_info', 'crown_side', 'front_display', 'band_slot', 'other_side']),
        'photo_analysis:overview': photoAnalysisJson([assessmentJson('aw_software_ui', 'CONSISTENT')], matched: 'front_display'),
        'photo_analysis:back_sensor': photoAnalysisJson([assessmentJson('aw_sensor_construction', 'CONSISTENT')], matched: 'back_sensor'),
        'evidence_validation': photoCheckJson(matched: 'back_sensor'),
        'multi_image_forensic_observations': combined ?? combinedJson(verdict: 'AUTHENTIC', findings: authenticFindings()),
      };

  Future<void> scanTwoPhotos(ScanFlowViewModel vm) async {
    await vm.captureInitialPhoto(imagePath: '/tmp/front.jpg');
    vm.captureRecommended();
    await vm.submitEvidencePhoto('/tmp/back.jpg');
    await vm.acceptPendingPhoto();
  }

  test('the final stage sends every photo together in one call, with thinking enabled', () async {
    final h = build(responses: responses());
    await scanTwoPhotos(h.vm);
    await h.vm.runAnalysis();
    expect(h.gemini.callsMatching('multi_image_forensic_observations'), 1);
    expect(h.gemini.imagesFor('multi_image_forensic_observations'), 2, reason: 'first photo + evidence photo (no crops for fake files)');
    final i = h.gemini.calls.indexOf('multi_image_forensic_observations');
    expect(h.gemini.thinkingLevels[i], AuthenticityEngineConfig.finalThinkingLevel);
    expect(h.gemini.prompts[i], contains('No web search is available'));
    expect(h.gemini.prompts[i], contains('APP CHECKLIST'));
    expect(h.gemini.prompts[i], contains('P2:'));
  });

  test('no search or research request is ever made', () async {
    final h = build(responses: responses());
    await scanTwoPhotos(h.vm);
    await h.vm.runAnalysis();
    expect(h.gemini.calls.where((c) => c.contains('research') || c.contains('search')), isEmpty);
    expect(h.gemini.schemas.whereType<Map>().map((m) => m.toString()).join(), isNot(contains('google_search')));
    expect(h.gemini.prompts.join(' '), isNot(contains('Google Search')));
  });

  test('a supported Authentic proposal becomes the result and says what it rests on', () async {
    final h = build(responses: responses());
    await scanTwoPhotos(h.vm);
    await h.vm.runAnalysis();
    final r = h.vm.currentReport!;
    expect(r.verdict, Verdict.likelyAuthentic);
    expect(r.engineVersion, AuthenticityEngineConfig.engineVersion);
    expect(r.rationale, contains(ProductReference.basisSentence));
    final log = r.analysisLog;
    expect(log['final_stage'], 'combined');
    expect((log['checklist'] as Map)['claims'], isNotEmpty);
    expect(log.containsKey('product_reference'), isFalse);
    expect(r.assessment!.validate(), isEmpty);
    expect(r.assessment!.manufacturerVerificationStatus, 'NOT_VERIFIED');
  });

  test('every request of one scan carries the same correlation id; the next scan gets a new one', () async {
    final h = build(responses: responses());
    await scanTwoPhotos(h.vm);
    await h.vm.runAnalysis();
    final ids = h.gemini.scanIds.toSet();
    expect(ids, hasLength(1));
    expect(ids.single, matches(RegExp(r'^scan_[0-9]+_[0-9a-f]+$')));
    expect(h.vm.currentReport!.analysisLog['correlation_id'], ids.single);
    h.vm.startScan();
    await h.vm.captureInitialPhoto(imagePath: '/tmp/front2.jpg');
    expect(h.gemini.scanIds.last, isNot(ids.single));
  });

  test('a Replica proposal is accepted with differences on two independent parts', () async {
    final h = build(responses: responses(
      combined: combinedJson(verdict: 'REPLICA', findings: [
        findingJson('none', 'CONFLICTS', images: ['P2'], part: 'back_sensor', variation: 'RULED_OUT', observed: 'Cream plastic back with printed dots.'),
        findingJson('none', 'CONFLICTS', images: ['P1'], part: 'front_display', variation: 'RULED_OUT', observed: 'Printed screws.'),
      ]),
    ));
    await scanTwoPhotos(h.vm);
    await h.vm.runAnalysis();
    final r = h.vm.currentReport!;
    expect(r.verdict, Verdict.likelyReplica);
    expect(r.suspiciousFindings.join(' '), contains('Cream plastic'));
  });

  test('an unsupported proposal is reported as not sure with what is missing', () async {
    final h = build(responses: responses(
      combined: combinedJson(verdict: 'AUTHENTIC', findings: [findingJson('none', 'MATCHES', images: ['P1'], part: 'crown_side')], unresolved: [
        {'issue': 'The back of the watch was not photographed clearly.', 'resolving_photo': 'back_sensor', 'resolving_check': null},
      ]),
    ));
    await scanTwoPhotos(h.vm);
    await h.vm.runAnalysis();
    final r = h.vm.currentReport!;
    expect(r.verdict, Verdict.inconclusive);
    expect(r.limitations.join(' '), contains('back of the watch'));
    expect(r.analysisLog['decision_trace'].toString(), contains('Gemini proposed AUTHENTIC'));
  });

  test('an API error in the final stage is an error with retry, not a report', () async {
    final h = build(responses: responses(), errors: {'multi_image_forensic_observations': AppError.serviceUnreachable()});
    await scanTwoPhotos(h.vm);
    await h.vm.runAnalysis();
    expect(h.vm.currentStep, ScanStep.error);
    expect(h.vm.currentReport, isNull);
    expect(h.history.allReports, isEmpty);
  });

  test('a malformed answer is retried once, then succeeds', () async {
    final h = build(responses: {
      ...responses(),
      'multi_image_forensic_observations': [
        {'findings': 'oops'},
        combinedJson(verdict: 'AUTHENTIC', findings: authenticFindings()),
      ],
    });
    await scanTwoPhotos(h.vm);
    await h.vm.runAnalysis();
    expect(h.vm.currentReport, isNotNull);
    expect(h.gemini.callsMatching('multi_image_forensic_observations'), 2);
  });

  test('repeatedly malformed answers surface as an invalid-response error', () async {
    final h = build(responses: {
      ...responses(),
      'multi_image_forensic_observations': {'proposed_verdict': 'MAYBE'},
    });
    await scanTwoPhotos(h.vm);
    await h.vm.runAnalysis();
    expect(h.vm.currentStep, ScanStep.error);
    expect(h.vm.currentReport, isNull);
  });


  test('report numbers come from the scan, not fixed values', () async {
    final h = build(responses: responses());
    await scanTwoPhotos(h.vm);
    await h.vm.runAnalysis();
    final r = h.vm.currentReport!;
    // Identity: brand CONFIRMED (40), model PROBABLE (17 of 35), generation
    // unknown (0 of 25) in the fixture identification.
    expect(r.identificationConfidence, 57);
    // All three findings were judged clearly.
    expect(r.analysisConfidence, 100);
    final partial = build(responses: responses(combined: combinedJson(verdict: 'NOT_SURE', findings: [
      ...authenticFindings().take(2),
      findingJson('none', 'UNCLEAR', images: ['P2'], part: 'band_slot'),
      findingJson('none', 'NOT_VISIBLE', images: ['P2'], part: 'device_info'),
    ])));
    await scanTwoPhotos(partial.vm);
    await partial.vm.runAnalysis();
    expect(partial.vm.appError, isNull, reason: '${partial.vm.appError?.message}');
    expect(partial.vm.currentReport!.analysisConfidence, 50);
    final items = partial.vm.currentReport!.evidenceItems;
    expect(items.map((e) => e.clarity).toSet().length, greaterThan(1), reason: 'the evidence line differs per photo');
  });
}
