import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/core/errors/app_error.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/evidence_validation.dart';
import 'package:replica_detector/repositories/authentication_repository.dart';
import 'package:replica_detector/repositories/gemini_authentication_repository.dart';
import 'package:replica_detector/repositories/history_repository.dart';
import 'package:replica_detector/viewmodels/scan_flow_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({
    ScanFlowViewModel vm,
    FakeGeminiService gemini,
    FakeImagePreparationService prep,
    HistoryRepository history,
  }) build({
    Map<String, Map<String, dynamic>> responses = const {},
    Map<String, Object> errors = const {},
  }) {
    final gemini = FakeGeminiService(responses: responses, errors: errors);
    final prep = FakeImagePreparationService();
    final history = HistoryRepository();
    final repo = AuthenticationRepository(
      geminiRepo: GeminiAuthenticationRepository(geminiService: gemini, imagePrep: prep),
    );
    return (
      vm: ScanFlowViewModel(authRepo: repo, historyRepo: history),
      gemini: gemini,
      prep: prep,
      history: history,
    );
  }

  Map<String, Map<String, dynamic>> happyPath({bool suspicious = false}) => {
        'product_identification': identificationJson(),
        'evidence_plan': evidencePlanJson(),
        'evidence_validation': validationJson(),
        'multi_image_forensic_observations': observationsJson(suspicious: suspicious),
      };

  group('Identification is one fast call (§2, §3, §45)', () {
    test('a single photo produces an identification and a 5-6 angle plan', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');

      expect(h.vm.currentStep, ScanStep.itemIdentified);
      expect(h.vm.currentProduct!.brand, 'Rolex');
      expect(h.vm.currentProduct!.name, 'Submariner Date');
      expect(h.vm.totalEvidenceCount, inInclusiveRange(5, 6));
      expect(h.gemini.callsMatching('product_identification'), 1);
      expect(h.gemini.callsMatching('evidence_plan'), 1);
    });

    test('identification uploads exactly one, downscaled image', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');

      expect(h.gemini.imageCounts.first, 1);
      expect(h.prep.prepared.first, endsWith('|identification'),
          reason: 'Identification must use the small preset');
    });

    test('the captured photo is persisted before use', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');

      expect(h.prep.persisted, contains('/tmp/shot.jpg'));
      expect(h.vm.initialImagePath, startsWith('/documents/'));
      expect(h.vm.currentProduct!.imageAsset, startsWith('/documents/'),
          reason: "The product image is the user's own photo, not a bundled asset");
    });

    test('re-identifying the same image is served from cache, not re-billed', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      final first = h.gemini.callsMatching('product_identification');

      await h.vm.captureInitialPhoto(imagePath: h.vm.initialImagePath);

      expect(h.gemini.callsMatching('product_identification'), first,
          reason: 'Returning to the screen must not re-run identification (§3)');
    });

    test('the plan carries product-specific weights with critical angles', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');

      final critical = h.vm.evidenceItems.where((e) => e.isCritical).toList();
      expect(critical.length, greaterThanOrEqualTo(2));
      expect(critical.map((e) => e.id), containsAll(['dial', 'reference_serial']));
      expect(h.vm.evidenceItems.every((e) => e.guide.isNotEmpty), isTrue);
    });
  });

  group('Wrong evidence never enters the case file (§6, §9, §28)', () {
    test('a crown photo offered as the dial is rejected and not stored', () async {
      final h = build(responses: {
        ...happyPath(),
        'evidence_validation': validationJson(detected: 'crown', matches: false, matchConfidence: 3),
      });
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      h.vm.proceedToEvidenceChecklist();

      final dialIndex = h.vm.evidenceItems.indexWhere((e) => e.id == 'dial');
      h.vm.startEvidenceCapture(dialIndex);
      await h.vm.submitEvidencePhoto('/tmp/crown.jpg');

      expect(h.vm.currentStep, ScanStep.photoQuality);
      expect(h.vm.pendingValidation!.verdict, EvidenceVerdict.rejectedWrongEvidence);
      expect(h.vm.capturedImagePaths.containsKey('dial'), isFalse);

      // Even an explicit override cannot admit it.
      h.vm.acceptPendingPhoto(force: true);
      expect(h.vm.capturedImagePaths.containsKey('dial'), isFalse);
      expect(h.vm.acceptedEvidenceCount, 0);
    });

    test('the model is asked about the image, never told what the user called it', () async {
      final h = build(responses: {
        ...happyPath(),
        'evidence_validation': validationJson(),
      });
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/IMG_serial_number.jpg');

      expect(h.gemini.callsMatching('evidence_validation'), 1);
      expect(h.prep.prepared.any((p) => p.contains('|validation')), isTrue);
    });

    test('a valid photo is accepted and recorded with its three metrics', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/full.jpg');
      h.vm.acceptPendingPhoto();

      expect(h.vm.acceptedEvidenceCount, 1);
      final stored = h.vm.evidenceItems.first;
      expect(stored.hasPhoto, isTrue);
      expect(stored.photoQualityScore, 91);
      expect(stored.evidenceMatchScore, 96);
      expect(stored.usefulnessScore, 89);
      expect(stored.keptDespiteLowQuality, isFalse);
    });

    test('a poor-quality photo of the right area may be kept, flagged', () async {
      final h = build(responses: {
        ...happyPath(),
        'evidence_validation': validationJson(quality: 22, usefulness: 15),
      });
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/blurry.jpg');

      expect(h.vm.pendingValidation!.verdict, EvidenceVerdict.rejectedQuality);

      h.vm.acceptPendingPhoto();
      expect(h.vm.acceptedEvidenceCount, 0, reason: 'A plain accept must not admit it');

      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/blurry.jpg');
      h.vm.acceptPendingPhoto(force: true);

      expect(h.vm.acceptedEvidenceCount, 1);
      expect(h.vm.evidenceItems.first.keptDespiteLowQuality, isTrue);
    });
  });

  group('Nothing is mandatory, but gaps cost confidence (§4, §26, §27)', () {
    test('analysis runs with a partial submission', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');

      for (final id in ['full_watch', 'dial']) {
        h.vm.startEvidenceCapture(h.vm.evidenceItems.indexWhere((e) => e.id == id));
        await h.vm.submitEvidencePhoto('/tmp/$id.jpg');
        h.vm.acceptPendingPhoto();
      }

      expect(h.vm.canAnalyze, isTrue);
      await h.vm.runAnalysis();

      expect(h.vm.currentStep, ScanStep.authenticationReport);
      expect(h.vm.currentReport!.coveredEvidenceCount, 2);
      expect(h.vm.currentReport!.totalEvidenceCount, 6);
      expect(h.vm.currentReport!.verdict, Verdict.inconclusive,
          reason: 'Two of six angles cannot support a confident verdict');
    });

    test('the user is never blocked: zero requested angles still analyses', () async {
      final h = build(responses: {
        ...happyPath(),
        'multi_image_forensic_observations': {
          'evidence_observations': [
            {
              'evidence_id': 'overview',
              'title': 'Overview',
              'observations': ['A watch on a wrist'],
              'consistent_signals': <String>[],
              'inconsistent_signals': <String>[],
              'uncertain_signals': ['Dial detail is not legible at this distance'],
              'visible_quality': 70,
            }
          ],
          'contradictions': <Map<String, dynamic>>[],
          'missing_critical_checks': ['Dial', 'Reference / Serial'],
          'physical_checks': <Map<String, dynamic>>[],
        },
      });
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');

      expect(h.vm.acceptedEvidenceCount, 0);
      expect(h.vm.canAnalyze, isTrue,
          reason: 'Having no evidence photos must not block the user (§4, §27)');

      await h.vm.runAnalysis();

      expect(h.vm.currentReport, isNotNull);
      expect(h.vm.currentReport!.verdict, Verdict.inconclusive);
      expect(h.vm.currentReport!.coveredEvidenceCount, 0,
          reason: 'The identification photo is never credited to a requested angle');
      expect(h.vm.currentReport!.missingEvidence, hasLength(6));
      final analysisIndex = h.gemini.calls.indexWhere((c) => c.startsWith('multi_image_forensic'));
      expect(h.gemini.imageCounts[analysisIndex], 1);
    });

    test('analysis is refused only when there is no photo at all', () async {
      final h = build(responses: happyPath());
      expect(h.vm.canAnalyze, isFalse);
      await h.vm.runAnalysis();
      expect(h.vm.currentReport, isNull);
      expect(h.gemini.callsMatching('multi_image_forensic'), 0);
    });

    test('"I do not have this" marks the angle unavailable, not passing', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');

      final idx = h.vm.evidenceItems.indexWhere((e) => e.id == 'reference_serial');
      h.vm.markEvidenceUnavailableAt(idx);

      expect(h.vm.evidenceItems[idx].isUnavailable, isTrue);
      expect(h.vm.capturedImagePaths.containsKey('reference_serial'), isFalse);
      expect(h.vm.acceptedEvidenceCount, 0);
    });
  });

  group('All accepted photos go in one request (§15)', () {
    test('six accepted angles produce a single analysis call with six images', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');

      for (var i = 0; i < h.vm.evidenceItems.length; i++) {
        h.vm.startEvidenceCapture(i);
        await h.vm.submitEvidencePhoto('/tmp/angle$i.jpg');
        h.vm.acceptPendingPhoto();
      }

      await h.vm.runAnalysis();

      expect(h.gemini.callsMatching('multi_image_forensic'), 1);
      final analysisIndex = h.gemini.calls.indexWhere((c) => c.startsWith('multi_image_forensic'));
      expect(h.gemini.imageCounts[analysisIndex], 6);
      expect(h.vm.currentReport!.verdict, Verdict.likelyAuthentic);
      expect(h.vm.currentReport!.authenticationConfidence, lessThanOrEqualTo(94));
    });

    test('the final pass uses the detail-preserving preset', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/a.jpg');
      h.vm.acceptPendingPhoto();
      await h.vm.runAnalysis();

      expect(h.prep.prepared.any((p) => p.endsWith('|evidence')), isTrue);
    });

    test('a replica submission is reported as such, with named concerns', () async {
      final h = build(responses: happyPath(suspicious: true));
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');

      for (var i = 0; i < h.vm.evidenceItems.length; i++) {
        h.vm.startEvidenceCapture(i);
        await h.vm.submitEvidencePhoto('/tmp/angle$i.jpg');
        h.vm.acceptPendingPhoto();
      }
      await h.vm.runAnalysis();

      final report = h.vm.currentReport!;
      expect(report.verdict, Verdict.likelyReplica);
      expect(report.suspiciousFindings, isNotEmpty);
      expect(report.suspiciousFindings.first, contains('Dial'));
      expect(report.rationale, contains('Submariner Date'));
    });
  });

  group('Failures surface as failures (§44, §46)', () {
    test('a failed identification does not invent a product', () async {
      final h = build(errors: {'product_identification': AppError.timeout()});
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');

      expect(h.vm.currentStep, ScanStep.error);
      expect(h.vm.currentProduct, isNull);
      expect(h.vm.appError!.type, AppErrorType.timeout);
    });

    test('a failed analysis does not invent a report', () async {
      final h = build(
        responses: happyPath(),
        errors: {'multi_image_forensic': AppError.serverError(code: 503)},
      );
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/a.jpg');
      h.vm.acceptPendingPhoto();
      await h.vm.runAnalysis();

      expect(h.vm.currentReport, isNull);
      expect(h.vm.currentStep, ScanStep.error);
      expect(h.vm.appError!.type, AppErrorType.serverError);
      expect(h.history.allReports, isEmpty, reason: 'No fabricated report may reach history');
    });

    test('an offline analysis reports being offline', () async {
      final h = build(responses: happyPath(), errors: {'multi_image_forensic': AppError.noInternet()});
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/a.jpg');
      h.vm.acceptPendingPhoto();
      await h.vm.runAnalysis();

      expect(h.vm.appError!.type, AppErrorType.noInternet);
    });

    test('a failed validation does not silently accept the photo', () async {
      final h = build(responses: happyPath(), errors: {'evidence_validation': AppError.timeout()});
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/a.jpg');

      expect(h.vm.currentStep, ScanStep.error);
      expect(h.vm.acceptedEvidenceCount, 0);
    });

    test('retry replays the failed step', () async {
      final gemini = FakeGeminiService(
        responses: {'product_identification': identificationJson(), 'evidence_plan': evidencePlanJson()},
        errors: {'product_identification': AppError.timeout()},
      );
      final repo = AuthenticationRepository(
        geminiRepo: GeminiAuthenticationRepository(
          geminiService: gemini,
          imagePrep: FakeImagePreparationService(),
        ),
      );
      final vm = ScanFlowViewModel(authRepo: repo, historyRepo: HistoryRepository());

      await vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      expect(vm.currentStep, ScanStep.error);

      gemini.errors.clear();
      await vm.retryLastAction();

      expect(vm.currentStep, ScanStep.itemIdentified);
      expect(vm.currentProduct, isNotNull);
    });
  });

  group('Reports reach history only when real (§32)', () {
    test('a completed analysis is saved to history', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/a.jpg');
      h.vm.acceptPendingPhoto();
      await h.vm.runAnalysis();

      expect(h.history.allReports, hasLength(1));
      expect(h.history.allReports.first.id, h.vm.currentReport!.id);
      expect(h.history.allReports.first.timestamp.isAfter(DateTime(2020)), isTrue);
    });

    test('evidence items in the report carry the real captured paths', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/a.jpg');
      h.vm.acceptPendingPhoto();
      await h.vm.runAnalysis();

      final supplied = h.vm.currentReport!.acceptedEvidence;
      expect(supplied, hasLength(1));
      expect(supplied.first.capturedImagePath, startsWith('/documents/'));
    });
  });

  group('Starting a new scan clears everything', () {
    test('no state leaks between scans', () async {
      final h = build(responses: happyPath());
      await h.vm.captureInitialPhoto(imagePath: '/tmp/shot.jpg');
      h.vm.startEvidenceCapture(0);
      await h.vm.submitEvidencePhoto('/tmp/a.jpg');
      h.vm.acceptPendingPhoto();

      h.vm.startScan();

      expect(h.vm.currentProduct, isNull);
      expect(h.vm.evidenceItems, isEmpty);
      expect(h.vm.capturedImagePaths, isEmpty);
      expect(h.vm.currentReport, isNull);
      expect(h.vm.pendingValidation, isNull);
      expect(h.vm.currentStep, ScanStep.directScan);
    });
  });
}
