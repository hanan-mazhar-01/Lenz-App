// Lenz scan capture journey: camera -> identify -> evidence -> guided
// capture -> validating -> photo quality.
//
// Always runs: every screen/state renders without layout errors at 390x844
// and on a small phone (320x640) with text scale 1.3, and the camera guides
// and CaptureTips stay on screen.
//
// With LENZ_SCAN_DUMP=1 it also writes PNGs for visual comparison with the
// prototype references:
//
//   LENZ_SCAN_DUMP=1 flutter test test/screens/scan_capture_screens_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:replica_detector/core/theme/app_theme.dart';
import 'package:replica_detector/models/capture_guide.dart';
import 'package:replica_detector/models/evidence.dart';
import 'package:replica_detector/models/evidence_validation.dart';
import 'package:replica_detector/models/photo_quality.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/services/storage_service.dart';
import 'package:replica_detector/viewmodels/scan_flow_viewmodel.dart';
import 'package:replica_detector/views/scan/direct_scan_view.dart';
import 'package:replica_detector/views/scan/dynamic_evidence_view.dart';
import 'package:replica_detector/views/scan/guided_capture_view.dart';
import 'package:replica_detector/views/scan/identifying_view.dart';
import 'package:replica_detector/views/scan/photo_quality_view.dart';
import 'package:replica_detector/views/scan/validating_photo_view.dart';
import 'package:replica_detector/widgets/camera/capture_guide_captions.dart';
import 'package:replica_detector/widgets/camera/capture_guide_overlay.dart';
import 'package:replica_detector/widgets/lenz/lenz.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui_kit/ui_test_utils.dart' show loadNunito;

final bool _dump = Platform.environment['LENZ_SCAN_DUMP'] == '1';
const String _out =
    '/tmp/claude-1000/-home-hanan-Documents-Flutter-Flutter-practice-Verado-Studio-replica-detector/20c8dca2-5206-4d74-b31e-e62ce23c25e4/scratchpad/lenz_screens';

const _bagArt = 'assets/lenz/categories/cat_bags.png';
const _watchArt = 'assets/lenz/categories/cat_watches.png';

/// Stand-in for the live camera feed (tests have no camera).
const Widget _fakeFeed = DecoratedBox(
  decoration: BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(0, -.16),
      radius: .9,
      colors: [Color(0xFF34503F), Color(0xFF0C1511)],
    ),
  ),
);

const _product = Product(
  id: 'p_bag',
  name: 'Neverfull MM',
  brand: 'Louis Vuitton',
  model: 'Neverfull MM',
  category: ProductCategory.bags,
  imageAsset: _bagArt,
  identificationConfidence: 0.92,
);

EvidenceItem _part(
  String id,
  int index,
  String title,
  String guide, {
  CaptureGuideType type = CaptureGuideType.generic,
  CaptureTips tips = CaptureTips.standard,
  String photo = '',
}) => EvidenceItem(
  id: id,
  index: index,
  title: title,
  guide: guide,
  guideType: type,
  tips: tips,
  capturedImagePath: photo,
  status: photo.isEmpty ? EvidenceStatus.pending : EvidenceStatus.captured,
  aiChecks: const ['Stitch count per inch', 'Thread colour'],
);

final _parts = [
  _part(
    'front',
    1,
    'Full front view',
    'Overall shape, proportions and panel alignment',
    type: CaptureGuideType.bagFull,
    tips: CaptureTips.fullView,
    photo: _bagArt,
  ),
  _part(
    'hardware',
    2,
    'Hardware close-up',
    'Zipper pull, clasp and engraved logos',
    type: CaptureGuideType.hardware,
    tips: CaptureTips.closeUp,
    photo: _bagArt,
  ),
  _part(
    'stitch',
    3,
    'Stitching detail',
    'Stitch count, spacing and thread tension',
    type: CaptureGuideType.macro,
    tips: CaptureTips.closeUp,
  ),
  _part(
    'label',
    4,
    'Interior label',
    'Heat stamp, font weight and spacing',
    type: CaptureGuideType.label,
    tips: CaptureTips.text,
  ),
  _part(
    'date',
    5,
    'Date code',
    'Date code stamp inside the bag',
    type: CaptureGuideType.bagInterior,
    tips: CaptureTips.text,
  ),
];

EvidenceValidationResult _validation({
  required int sharp,
  required int light,
  required int quality,
  int match = 96,
  bool matches = true,
  String detected = 'Stitching detail',
}) => EvidenceValidationResult(
  requestedEvidenceId: 'stitch',
  requestedEvidenceTitle: 'Stitching detail',
  evidenceTypeDetected: detected,
  matchToRequestedEvidence: matches,
  matchConfidence: matches ? match : 12,
  quality: PhotoQualityResult(
    qualityScore: quality,
    qualityStatus: PhotoQualityStatus.fromScore(quality),
    explanation: 'test',
    sharpness: sharp,
    lighting: light,
    framing: 80,
    detail: 76,
  ),
  usabilityScore: quality,
  authenticationUsefulness: matches ? 82 : 0,
  reason: 'The stitching is clearly visible.',
);

Widget _guided(CaptureGuideType type, String title, String guide, CaptureTips tips, {int n = 3}) =>
    GuidedCaptureView(
      currentItem: _part('g_$n', n, title, guide, type: type, tips: tips),
      currentIndex: n - 1,
      totalCount: 5,
      photoNumber: n,
      maxPhotos: 5,
      evidenceProgress: .4,
      progressLabel: '2 of 5 photos taken',
      onCapture: ([_]) {},
      onMarkUnavailable: () {},
      onBack: () {},
      previewOverride: _fakeFeed,
    );

final Map<String, Widget Function()> _screens = {
  '10_camera': () => DirectScanView(onClose: () {}, onCapture: (_) {}, previewOverride: _fakeFeed),
  '10_camera_unavailable': () => DirectScanView(onClose: () {}, onCapture: (_) {}),
  '11_identify_searching': () => IdentifyingView(
    scanState: ScanLifecycleState.identifying,
    product: null,
    capturedImagePath: _bagArt,
    onContinue: () {},
    onBack: () {},
  ),
  '11_identify': () => IdentifyingView(
    scanState: ScanLifecycleState.identified,
    product: _product,
    capturedImagePath: _bagArt,
    evidenceCount: 5,
    onContinue: () {},
    onBack: () {},
  ),
  '11_identify_low': () => IdentifyingView(
    scanState: ScanLifecycleState.identified,
    product: const Product(
      id: 'p_bag',
      name: 'Neverfull MM',
      brand: 'Louis Vuitton',
      model: 'Neverfull MM',
      category: ProductCategory.bags,
      imageAsset: _bagArt,
      identificationConfidence: .38,
    ),
    evidenceCount: 5,
    onContinue: () {},
    onBack: () {},
  ),
  '12_evidence': () => DynamicEvidenceView(
    product: _product,
    evidenceItems: _parts,
    capturedImages: {
      for (final p in _parts)
        if (p.hasPhoto) p.id: p.capturedImagePath,
    },
    acceptedCount: 2,
    canAnalyze: false,
    onSelectPart: (_) {},
    onMarkUnavailable: (_) {},
    onClearEvidence: (_) {},
    onAnalyze: () {},
    onBack: () {},
  ),
  '13_capture_macro': () => _guided(
    CaptureGuideType.macro,
    'Stitching detail',
    'Stitch count, spacing and thread tension.',
    CaptureTips.closeUp,
  ),
  '13_capture_watch_round': () => _guided(
    CaptureGuideType.watchFaceRound,
    'Dial',
    'The whole dial, straight on, with the hands visible.',
    CaptureTips.standard,
    n: 2,
  ),
  '13_capture_shoe_side': () => _guided(
    CaptureGuideType.shoeSide,
    'Side profile',
    'The outer side of the shoe, toe to heel.',
    CaptureTips.fullView,
    n: 1,
  ),
  '13_capture_label': () => _guided(
    CaptureGuideType.label,
    'Interior label',
    'Heat stamp, font weight and spacing.',
    CaptureTips.text,
    n: 4,
  ),
  '13_capture_watch_back': () => _guided(
    CaptureGuideType.watchBack,
    'Caseback',
    'The back of the watch with any engravings.',
    CaptureTips.closeUp,
    n: 5,
  ),
  '13_capture_glasses': () => _guided(
    CaptureGuideType.glassesFront,
    'Front of the frame',
    'Lay the glasses flat and show both lenses.',
    CaptureTips.fullView,
    n: 1,
  ),
  '14_quality_good': () => PhotoQualityView(
    item: _parts[2],
    photoPath: _bagArt,
    validation: _validation(sharp: 94, light: 88, quality: 90),
    onKeep: () {},
    onRetake: () {},
    onChooseAnother: () {},
  ),
  '14_quality_blurry': () => PhotoQualityView(
    item: _parts[2],
    photoPath: _bagArt,
    validation: _validation(sharp: 38, light: 71, quality: 42, match: 90),
    onKeep: () {},
    onKeepAnyway: () {},
    onRetake: () {},
    onChooseAnother: () {},
  ),
  '14_quality_wrong_part': () => PhotoQualityView(
    item: _parts[2],
    photoPath: _watchArt,
    validation: _validation(
      sharp: 90,
      light: 86,
      quality: 88,
      matches: false,
      detected: 'a watch dial',
    ),
    onKeep: () {},
    onRetake: () {},
    onChooseAnother: () {},
  ),
  '15_validating': () => ValidatingPhotoView(item: _parts[2]),
};

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required Size size,
  double textScale = 1,
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<StorageService>.value(
      value: StorageService(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(top: 12),
          ),
          child: child!,
        ),
        home: RepaintBoundary(key: boundary, child: screen),
      ),
    ),
  );
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (i % 6 == 0) {
      // Let asset images decode.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    }
  }
}

Future<void> _write(GlobalKey key, String name) async {
  final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await b.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  Directory(_out).createSync(recursive: true);
  File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await loadNunito();
    await LenzAssets.instance.ensureAllLoaded();
  });

  for (final entry in _screens.entries) {
    for (final small in [false, true]) {
      final label = small ? '${entry.key}_320' : entry.key;
      testWidgets('$label renders without layout errors', (tester) async {
        debugDisableShadows = !_dump;
        final key = GlobalKey();
        await _pump(
          tester,
          entry.value(),
          size: small ? const Size(320, 640) : const Size(390, 844),
          textScale: small ? 1.3 : 1,
          boundary: key,
        );
        expect(tester.takeException(), isNull);
        if (_dump) await tester.runAsync(() => _write(key, label));
        debugDisableShadows = true;
      });
    }
  }

  testWidgets('capture screen shows one short caption; the CaptureTips live in the sheet', (tester) async {
    var skipped = 0;
    await _pump(
      tester,
      GuidedCaptureView(
        currentItem: _part('g_3', 3, 'Interior label', 'Heat stamp, font weight and spacing.',
            type: CaptureGuideType.label, tips: CaptureTips.text),
        currentIndex: 2,
        totalCount: 5,
        photoNumber: 3,
        maxPhotos: 5,
        onCapture: ([_]) {},
        onMarkUnavailable: () => skipped++,
        onBack: () {},
        previewOverride: _fakeFeed,
      ),
      size: const Size(390, 844),
    );
    final overlay = tester.widget<CaptureGuideOverlay>(find.byType(CaptureGuideOverlay));
    expect(overlay.type, CaptureGuideType.label);
    expect(overlay.label, 'Fit the label');
    expect(find.text('Fit the label'), findsOneWidget);
    expect(find.text('Heat stamp'), findsOneWidget);
    // Long text is not on the camera.
    expect(find.text(CaptureTips.text.distance), findsNothing);
    expect(find.text(CaptureTips.text.focus), findsNothing);
    expect(find.text(CaptureTips.text.lighting), findsNothing);
    expect(find.textContaining('framing aid'), findsNothing);
    for (final t in ['Light', 'Focus', 'Glare', 'Example', 'Skip']) {
      expect(find.text(t), findsOneWidget);
    }

    // Example opens the sheet with the full tips and the disclaimer.
    await tester.tap(find.text('Example'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text(CaptureTips.text.distance), findsOneWidget);
    expect(find.text(CaptureTips.text.focus), findsOneWidget);
    expect(find.text(CaptureTips.text.lighting), findsOneWidget);
    expect(find.text('Photo 3 of up to 5'), findsOneWidget);
    expect(find.textContaining('framing aid only'), findsOneWidget);
    await tester.ensureVisible(find.text('Got it'));
    await tester.pump();
    await tester.tap(find.text('Got it'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text(CaptureTips.text.distance), findsNothing);

    // A chip opens it too.
    await tester.tap(find.text('Glare'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text(CaptureTips.text.lighting), findsOneWidget);
    await tester.ensureVisible(find.text('Got it'));
    await tester.pump();
    await tester.tap(find.text('Got it'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    // "Skip" is the existing "Can't take" action.
    await tester.tap(find.text('Skip'));
    expect(skipped, 1);
  });

  testWidgets('every guide type has a caption of at most five words', (tester) async {
    for (final t in CaptureGuideType.values) {
      final c = captureGuideCaption(t);
      expect(c.split(' ').length, lessThanOrEqualTo(5), reason: t.name);
    }
  });

  testWidgets('camera tip chips are static advice, never "detected" states', (tester) async {
    await _pump(
      tester,
      DirectScanView(onClose: () {}, onCapture: (_) {}, previewOverride: _fakeFeed),
      size: const Size(390, 844),
    );
    for (final t in ['Well lit', 'Centered', 'In focus']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Scan product'), findsOneWidget);
  });

  testWidgets('evidence actions keep the real rules', (tester) async {
    var selected = -1;
    var analyzed = false;
    await _pump(
      tester,
      DynamicEvidenceView(
        product: _product,
        evidenceItems: _parts,
        capturedImages: const {'front': _bagArt},
        acceptedCount: 1,
        canAnalyze: true,
        onSelectPart: (i) => selected = i,
        onMarkUnavailable: (_) {},
        onClearEvidence: (_) {},
        onAnalyze: () => analyzed = true,
        onBack: () {},
      ),
      size: const Size(390, 844),
    );
    // Not every part captured -> the bottom action opens the next part.
    await tester.tap(find.text('Take next photo'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(selected, 1);
    expect(analyzed, isFalse);
    expect(find.text('1/5'), findsOneWidget);
  });

  testWidgets('photo review wires keep / retake / keep anyway', (tester) async {
    var kept = 0, anyway = 0, retake = 0;
    await _pump(
      tester,
      PhotoQualityView(
        item: _parts[2],
        photoPath: _bagArt,
        validation: _validation(sharp: 38, light: 71, quality: 42, match: 90),
        onKeep: () => kept++,
        onKeepAnyway: () => anyway++,
        onRetake: () => retake++,
        onChooseAnother: () {},
      ),
      size: const Size(390, 844),
    );
    expect(find.text('38%'), findsOneWidget);
    expect(find.text('Too blurry'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Keep anyway'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.text('Choose another photo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Keep anyway'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Retake photo'));
    await tester.pump(const Duration(milliseconds: 300));
    expect((kept, anyway, retake), (0, 1, 1));
  });
}
