import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/capture_guide.dart';
import 'package:replica_detector/models/evidence_record.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/repositories/collection_repository.dart';
import 'package:replica_detector/repositories/gemini_authentication_repository.dart';
import 'package:replica_detector/repositories/history_repository.dart';
import 'package:replica_detector/services/storage_service.dart';
import 'package:replica_detector/viewmodels/history_viewmodel.dart';
import 'package:replica_detector/viewmodels/scan_flow_viewmodel.dart';
import 'package:replica_detector/views/history/history_screen.dart';
import 'package:replica_detector/views/report/authentication_report_view.dart';
import 'package:replica_detector/views/scan/dynamic_evidence_view.dart';
import 'package:replica_detector/views/scan/identifying_view.dart';
import 'package:replica_detector/views/scan/photo_quality_view.dart';
import 'package:replica_detector/widgets/camera/capture_guide_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini.dart';
import 'support/fixtures.dart';

/// The original screens (restored) render the new engine's data on a small
/// phone without layout errors, and never show "0%" for new reports.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GeminiAuthenticationRepository.clearRankingCache();
  });

  Future<void> pumpPhone(WidgetTester tester, Widget child,
      {List<ChangeNotifierProvider> providers = const [], double width = 360}) async {
    tester.view.physicalSize = Size(width * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: StorageService()),
        ChangeNotifierProvider<CollectionRepository>.value(value: CollectionRepository()),
        ...providers,
      ],
      child: MaterialApp(home: child),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  final repo = GeminiAuthenticationRepository(geminiService: FakeGeminiService(), imagePrep: FakeImagePreparationService());
  final product = Product(
    id: 'p',
    name: 'Apple Watch Ultra',
    brand: 'Apple',
    model: 'Apple Watch Ultra',
    category: ProductCategory.watches,
    imageAsset: '/tmp/none.jpg',
    categoryCode: 'WATCH',
    identity: identity(type: 'smartwatch', brand: 'Apple', family: 'Apple Watch Ultra', generation: 'Ultra 2'),
  );
  final ctx = repo.createContext(product);
  final photos = [
    photo('front_display', [assess('aw_software_ui', CheckpointOutcome.consistent)], photoId: 'overview', initial: true),
    photo('back_sensor', [assess('aw_sensor_construction', CheckpointOutcome.consistent)]),
  ];
  final result = repo.evaluate(ctx, photos);
  final plan = repo.plan(ctx, photos, result);
  final items = GeminiAuthenticationRepository.requestItems(ctx, plan, photos, const {}).take(6).toList();

  testWidgets('original checklist screen renders the planned photos', (tester) async {
    await pumpPhone(
      tester,
      DynamicEvidenceView(
        product: ctx.product,
        evidenceItems: items,
        capturedImages: {for (final e in items) if (e.hasPhoto) e.id: e.capturedImagePath},
        acceptedCount: photos.length,
        canAnalyze: true,
        onSelectPart: (_) {},
        onMarkUnavailable: (_) {},
        onClearEvidence: (_) {},
        onAnalyze: () {},
        onBack: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('We need a closer look'), findsOneWidget);
    expect(find.text('Model information screen', skipOffstage: false), findsWidgets);
  });

  testWidgets('original identified screen renders', (tester) async {
    // The original screen's stage rows are sized for real fonts; the test
    // font draws every glyph as a full square, so give it more width. The
    // screen itself is unchanged from before this work.
    await pumpPhone(
      width: 700,
      tester,
      IdentifyingView(
        scanState: ScanLifecycleState.identified,
        product: ctx.product,
        evidenceCount: items.length,
        onContinue: () {},
        onBack: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Item identified'), findsOneWidget);
  });

  testWidgets('original photo review screen renders', (tester) async {
    await pumpPhone(
      tester,
      PhotoQualityView(
        item: items.first,
        photoPath: '/tmp/b.jpg',
        validation: validation(id: 'back_sensor', title: 'Back of the watch'),
        onKeep: () {},
        onRetake: () {},
        onChooseAnother: () {},
      ),
    );
    expect(tester.takeException(), isNull);
  });

  Future<AuthenticationReport> v3Report() async {
    final gemini = FakeGeminiService(responses: {
      'multi_image_forensic_observations': combinedJson(verdict: 'AUTHENTIC', findings: authenticFindings()),
    });
    final r = GeminiAuthenticationRepository(geminiService: gemini, imagePrep: FakeImagePreparationService());
    return r.finalizeReport(ctx: ctx, photos: [
      ...photos,
      photo('device_info', [assess('aw_device_info', CheckpointOutcome.consistent)]),
    ]);
  }

  testWidgets('original report screen shows a new report without "0%"', (tester) async {
    final report = await tester.runAsync(v3Report);
    expect(report!.verdict, Verdict.likelyAuthentic);
    await pumpPhone(
      tester,
      AuthenticationReportView(
        report: report,
        onDone: () {},
        onToggleFavorite: () {},
        onSelectPart: (_) {},
        onOpenDetectYourself: () {},
        onCaptureMoreEvidence: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Appears Authentic'), findsOneWidget);
    expect(find.text('0%', skipOffstage: false), findsNothing);
    expect(find.textContaining('0% confidence', skipOffstage: false), findsNothing);
  });

  testWidgets('history shows new reports without "0%"', (tester) async {
    final report = await tester.runAsync(v3Report);
    final history = HistoryRepository();
    history.addReport(report!);
    await pumpPhone(
      tester,
      HistoryScreen(onOpenReport: (_) {}, onStartScan: () {}),
      providers: [
        ChangeNotifierProvider<HistoryRepository>.value(value: history),
        ChangeNotifierProvider<HistoryViewModel>(create: (_) => HistoryViewModel(historyRepo: history)),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('every camera guide paints without errors', (tester) async {
    await pumpPhone(
      tester,
      Scaffold(
        body: Wrap(children: [
          for (final t in CaptureGuideType.values) ...[
            CaptureGuideIllustration(type: t, size: 48),
            SizedBox(width: 120, height: 120, child: CaptureGuideOverlay(type: t, label: 'framing aid only')),
          ],
        ]),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
