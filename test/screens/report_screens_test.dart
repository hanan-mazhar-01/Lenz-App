// Analyzing, report, part detail, tips, error and not-a-product screens
// (Lenz redesign). Behaviour + overflow tests always run; PNG dumps for
// side-by-side comparison with the prototype only run when
// LENZ_SCREEN_DUMP_DIR is set:
//
//   LENZ_SCREEN_DUMP_DIR=/tmp/x flutter test test/screens/report_screens_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/core/errors/app_error.dart';
import 'package:replica_detector/core/theme/app_theme.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/evidence.dart';
import 'package:replica_detector/models/product_identification.dart';
import 'package:replica_detector/views/report/authentication_report_view.dart';
import 'package:replica_detector/views/report/part_detail_view.dart';
import 'package:replica_detector/views/scan/analyzing_view.dart';
import 'package:replica_detector/views/scan/scan_error_view.dart';
import 'package:replica_detector/views/scan/scan_validation_result_view.dart';
import 'package:replica_detector/widgets/lenz/lenz.dart';
import 'package:replica_detector/widgets/ui/lenz_confetti.dart';
import 'package:replica_detector/widgets/ui/ui.dart';

import '../support/fixtures.dart';
import '../ui_kit/ui_test_utils.dart';

final String? _dumpDir = Platform.environment['LENZ_SCREEN_DUMP_DIR'];

// ---------------------------------------------------------------- fake data
const _bagPhoto = 'assets/lenz/categories/cat_bags.png';
const _watchPhoto = 'assets/lenz/categories/cat_watches.png';
const _accPhoto = 'assets/lenz/categories/cat_accessories.png';

EvidenceItem _part(
  String id,
  String title,
  EvidenceStatus status, {
  String photo = _bagPhoto,
  int clarity = 0,
  int score = 0,
  List<String> consistent = const [],
  List<String> flagged = const [],
  List<String> unclear = const [],
  List<String> observations = const [],
  String reason = '',
}) => EvidenceItem(
  id: id,
  index: 1,
  title: title,
  guide: 'Compare the stamp font, spacing and depth with genuine examples of this model.',
  reason: reason,
  capturedImagePath: photo,
  status: status,
  clarity: clarity,
  score: score,
  consistentSignals: consistent,
  inconsistentSignals: flagged,
  uncertainSignals: unclear,
  observations: observations,
);

AuthenticationReport _report(Verdict verdict, {bool legacy = false}) {
  final auth = verdict == Verdict.likelyAuthentic;
  final fake = verdict == Verdict.likelyReplica;
  final parts = [
    _part(
      'front',
      'Full front view',
      EvidenceStatus.consistent,
      clarity: 92,
      score: legacy ? 93 : 0,
      reason: 'Overall shape, proportions and panel alignment',
      consistent: [
        'Panel proportions match this model',
        'Handle drop and attachment points look right',
      ],
    ),
    _part(
      'stamp',
      'Heat stamp',
      fake ? EvidenceStatus.suspicious : EvidenceStatus.consistent,
      photo: _accPhoto,
      clarity: 78,
      score: legacy ? (fake ? 38 : 88) : 0,
      reason: 'Stamp font, spacing and depth',
      flagged: fake
          ? ['Letter spacing is wider than on genuine examples', 'Stamp depth looks shallow']
          : const [],
      consistent: fake ? const [] : ['Font weight and spacing look consistent'],
    ),
    _part(
      'hardware',
      'Hardware close-up',
      auth
          ? EvidenceStatus.consistent
          : (fake ? EvidenceStatus.suspicious : EvidenceStatus.inconclusive),
      photo: _watchPhoto,
      clarity: auth ? 70 : 35,
      score: legacy ? (fake ? 41 : 66) : 0,
      reason: 'Zipper pull, clasp and engraving',
      flagged: fake ? ['Engraving edges look soft'] : const [],
      unclear: auth || fake ? const [] : ['Glare hides the engraving'],
      observations: ['Gold-tone zipper pull with engraved logo'],
    ),
  ];
  return AuthenticationReport(
    id: 'r_${verdict.name}',
    product: testBag,
    verdict: verdict,
    overallScore: legacy ? (auth ? 94 : (fake ? 87 : 52)) : 0,
    evidenceStrength: legacy ? null : (auth ? 'strong' : (fake ? 'moderate' : 'limited')),
    engineVersion: legacy ? '2.0' : '4.1',
    quickSummaryPoints: auth
        ? [
            'Stitching, hardware and labels line up with this model',
            'No red flags in the photos you gave me',
          ]
        : fake
        ? [
            'Heat stamp spacing disagrees with genuine examples',
            'Needs a closer look: hardware engraving',
          ]
        : ['Glare hides the hardware engraving', 'Next photo: hardware close-up in soft light'],
    suspiciousFindings: fake ? ['Heat stamp spacing disagrees with genuine examples'] : const [],
    evidenceItems: parts,
    rationale: auth
        ? 'The visible construction details are consistent with a genuine Neverfull MM. Nothing contradicts that.'
        : fake
        ? 'Several product-specific details disagree with genuine examples. The stamp and engraving are the clearest.'
        : 'Some photos were too limited for a firm call. Add clearer shots of the unclear areas.',
    timestamp: DateTime(2026, 10, 1),
    isFavorite: auth,
    imageQualityScore: legacy ? 82 : 0,
    analysisConfidence: legacy ? 76 : 0,
    identificationConfidence: legacy ? 91 : 0,
    limitations: verdict == Verdict.inconclusive
        ? ['Strong glare on the hardware photo']
        : const [],
    recommendedViews: verdict == Verdict.inconclusive
        ? ['Hardware close-up without flash']
        : const [],
    needsMoreImages: verdict == Verdict.inconclusive,
    nextChecks: ['Compare the date code with the lining stamp'],
    physicalChecks: const [
      PhysicalCheck(
        title: 'Feel the hardware',
        description: 'Genuine hardware feels dense and cool.',
        whatToLookFor: 'Hollow or light pieces are a warning sign.',
      ),
    ],
  );
}

Widget _reportView(
  AuthenticationReport r, {
  bool capture = true,
  VoidCallback? onDone,
  VoidCallback? onFav,
  ValueChanged<EvidenceItem>? onPart,
}) => AuthenticationReportView(
  report: r,
  onDone: onDone ?? () {},
  onToggleFavorite: onFav ?? () {},
  onSelectPart: onPart ?? (_) {},
  onCaptureMoreEvidence: capture ? () {} : null,
);

Widget _analyzing() => AnalyzingView(
  items: [
    item(id: 'front', title: 'Front'),
    item(id: 'stamp', title: 'Heat stamp'),
    item(id: 'hardware', title: 'Hardware'),
  ],
  capturedImages: const {'front': _bagPhoto, 'stamp': _accPhoto, 'hardware': _watchPhoto},
  product: testBag,
  onBack: () {},
);

// ------------------------------------------------------------------ helpers
final _key = GlobalKey();

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  double width = 390,
  double height = 844,
  double textScale = 1,
  int ms = 1500,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const SizedBox()); // fresh state for every pump
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: RepaintBoundary(key: _key, child: screen),
    ),
  );
  await tester.runAsync(() async {
    for (final p in const [_bagPhoto, _watchPhoto, _accPhoto]) {
      await precacheImage(AssetImage(p), _key.currentContext!);
    }
  });
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _dump(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dumpDir!).createSync(recursive: true);
    File('$_dumpDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Pumps [screen] at phone size, then at 320x640 with text scale 1.3, and
/// expects no layout exception in either.
Future<void> _noOverflow(WidgetTester tester, Widget screen) async {
  await _pump(tester, screen);
  expect(tester.takeException(), isNull);
  await _pump(tester, screen, width: 320, height: 640, textScale: 1.3);
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(loadNunito);

  testWidgets('assets', (tester) async {
    await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
    expect(LenzAssets.instance.isReady, isTrue);
  });

  group('report', () {
    for (final v in Verdict.values) {
      testWidgets('${v.label}: verdict, real strength, no %, disclaimer, no overflow', (
        tester,
      ) async {
        await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
        final r = _report(v);
        await _noOverflow(tester, _reportView(r));
        expect(find.text(v.label), findsOneWidget);
        final word = {
          Verdict.likelyAuthentic: 'Strong',
          Verdict.likelyReplica: 'Moderate',
          Verdict.inconclusive: 'Limited',
        }[v]!;
        expect(find.text(word, skipOffstage: false), findsOneWidget);
        expect(find.textContaining('%', skipOffstage: false), findsNothing);
        expect(
          find.text('AI-assisted opinion, not an official authentication.', skipOffstage: false),
          findsOneWidget,
        );
        expect(find.byType(LenzCharacter), findsOneWidget);
        final ring = tester.widget<LenzRing>(find.byType(LenzRing));
        expect(
          ring.value,
          {
            Verdict.likelyAuthentic: 1.0,
            Verdict.likelyReplica: 0.66,
            Verdict.inconclusive: 0.33,
          }[v],
        );
        // No share feature in the app.
        expect(find.bySemanticsLabel('Share'), findsNothing);
      });
    }

    testWidgets('mood per verdict', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      for (final (v, m) in [
        (Verdict.likelyAuthentic, LenzMood.happy),
        (Verdict.likelyReplica, LenzMood.shocked),
        (Verdict.inconclusive, LenzMood.unsure),
      ]) {
        await _pump(tester, _reportView(_report(v)), ms: 300);
        expect(tester.widget<LenzCharacter>(find.byType(LenzCharacter)).mood, m);
      }
    });

    testWidgets('legacy report keeps its stored percentages', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      await _pump(tester, _reportView(_report(Verdict.likelyAuthentic, legacy: true)), ms: 3000);
      expect(find.text('94%', skipOffstage: false), findsOneWidget);
      expect(find.text('Photo quality', skipOffstage: false), findsOneWidget);
      expect(find.text('82%', skipOffstage: false), findsOneWidget);
    });

    testWidgets('callbacks: done, favorite, part, capture more only when given', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      var done = 0, fav = 0;
      EvidenceItem? part;
      await _pump(
        tester,
        _reportView(
          _report(Verdict.likelyReplica),
          onDone: () => done++,
          onFav: () => fav++,
          onPart: (p) => part = p,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.tap(find.bySemanticsLabel('Favorite'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(done, 1);
      expect(fav, 1);
      await tester.scrollUntilVisible(
        find.text('Heat stamp'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Heat stamp'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(part?.id, 'stamp');
      expect(find.text('Capture more evidence', skipOffstage: false), findsOneWidget);
      expect(find.text('Flagged', skipOffstage: false), findsWidgets);

      await _pump(tester, _reportView(_report(Verdict.likelyReplica), capture: false));
      expect(find.text('Capture more evidence', skipOffstage: false), findsNothing);
      expect(find.text('Done', skipOffstage: false), findsOneWidget);
    });

    testWidgets('confetti only on an authentic verdict', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      await _pump(tester, _reportView(_report(Verdict.likelyAuthentic)), ms: 300);
      expect(find.byType(LenzConfetti), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('other screens', () {
    testWidgets('analyzing: timed steps, real photos, no percent', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      await _noOverflow(tester, _analyzing());
      await _pump(tester, _analyzing(), ms: 200);
      expect(find.text('Analyzing'), findsOneWidget);
      expect(find.text('Inspecting photos'), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing); // one page, no scrolling
      expect(find.textContaining('%'), findsNothing);
      expect(find.byType(LenzJourneyStepper), findsOneWidget);
      expect(tester.widget<LenzCharacter>(find.byType(LenzCharacter).at(1)).mood, LenzMood.inspect);
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('AI analysis'), findsWidgets);
      expect(tester.widget<LenzCharacter>(find.byType(LenzCharacter).at(1)).mood, LenzMood.think);
    });

    testWidgets('part detail flagged / consistent', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final r = _report(Verdict.likelyReplica);
      final flagged = PartDetailView(
        item: r.evidenceItems[1],
        onBack: () {},
      );
      await _noOverflow(tester, flagged);
      expect(find.text('Inconsistencies flagged', skipOffstage: false), findsOneWidget);
      expect(tester.widget<LenzCharacter>(find.byType(LenzCharacter)).mood, LenzMood.shocked);
      expect(find.text('Physical detection tips', skipOffstage: false), findsNothing);
      expect(find.text('Check it yourself', skipOffstage: false), findsNothing);

      final ok = PartDetailView(
        item: r.evidenceItems[0],
        onBack: () {},
      );
      await _noOverflow(tester, ok);
      expect(find.text('Consistent manufacturing signals', skipOffstage: false), findsOneWidget);
      expect(tester.widget<LenzCharacter>(find.byType(LenzCharacter)).mood, LenzMood.pleased);
    });

    testWidgets('error: every AppErrorType renders its real copy', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final errors = [
        AppError.noInternet(),
        AppError.fromException('quota exceeded 429'),
        AppError.fromException('something odd'),
        for (final t in AppErrorType.values)
          AppError(type: t, title: 'Title ${t.name}', message: 'Message ${t.name}'),
      ];
      for (final e in errors) {
        var retry = 0;
        await _noOverflow(
          tester,
          ScanErrorView(
            errorMessage: e.message,
            appError: e,
            onRetry: () => retry++,
            onCancel: () {},
          ),
        );
        expect(find.text(e.title), findsOneWidget);
        expect(find.text(e.message), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Try again'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Try again'));
        expect(retry, 1);
      }
    });

    testWidgets('not a product: every reason renders', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      for (final (reason, status, photo) in [
        ('unsupported_object', IdentificationStatus.notProduct, _bagPhoto),
        ('not_real_photo', IdentificationStatus.unusableImage, _bagPhoto),
        ('image_too_dark', IdentificationStatus.unusableImage, null),
        ('no_visible_content', IdentificationStatus.unusableImage, null),
        ('insufficient_visual_quality', IdentificationStatus.unusableImage, _bagPhoto),
        ('human_detected', IdentificationStatus.notProduct, _bagPhoto),
        (
          'partial_product_insufficient_evidence',
          IdentificationStatus.insufficientEvidence,
          _bagPhoto,
        ),
      ]) {
        var again = 0, close = 0;
        await _noOverflow(
          tester,
          ScanValidationResultView(
            capturedImagePath: photo,
            status: status,
            reason: reason,
            message: 'No supported luxury product detected in that photo.',
            missingEvidence: reason.startsWith('partial')
                ? const ['Brand logo', 'Interior label']
                : const [],
            onTryAgain: () => again++,
            onClose: () => close++,
          ),
        );
        await tester.tap(find.bySemanticsLabel('Close'));
        expect(close, 1, reason: reason);
      }
    });
  });

  // ------------------------------------------------------------- PNG dumps
  group('dump', () {
    Future<void> shot(
      WidgetTester tester,
      String name,
      Widget screen, {
      int ms = 2500,
      bool small = false,
      double scroll = 0,
    }) async {
      debugDisableShadows = false;
      await _pump(
        tester,
        screen,
        ms: ms,
        width: small ? 320 : 390,
        height: small ? 640 : 844,
        textScale: small ? 1.3 : 1,
      );
      if (scroll > 0) {
        await tester.drag(find.byType(Scrollable).first, Offset(0, -scroll));
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      await _dump(tester, name);
      expect(tester.takeException(), isNull);
      debugDisableShadows = true;
    }

    testWidgets('screens', skip: _dumpDir == null, (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      await shot(tester, '15_analyzing_t0', _analyzing(), ms: 600);
      await shot(tester, '15_analyzing_t1', _analyzing(), ms: 2600);
      await shot(tester, '15_analyzing_t2', _analyzing(), ms: 6000);
      await shot(tester, '15_analyzing_small', _analyzing(), ms: 2600, small: true);
      await shot(
        tester,
        '16_report_authentic_confetti',
        _reportView(_report(Verdict.likelyAuthentic)),
        ms: 1000,
      );
      await shot(
        tester,
        '16_report_authentic',
        _reportView(_report(Verdict.likelyAuthentic)),
        ms: 4000,
      );
      await shot(tester, '16_report_replica', _reportView(_report(Verdict.likelyReplica)));
      await shot(
        tester,
        '16_report_replica_bottom',
        _reportView(_report(Verdict.likelyReplica)),
        scroll: 2000,
      );
      await shot(
        tester,
        '16_report_authentic_bottom_nocapture',
        _reportView(_report(Verdict.likelyAuthentic), capture: false),
        scroll: 2000,
      );
      await shot(
        tester,
        '16_report_legacy_mid',
        _reportView(_report(Verdict.likelyAuthentic, legacy: true)),
        scroll: 500,
        ms: 4000,
      );
      await shot(
        tester,
        '17_part_flagged_bottom',
        PartDetailView(
          item: _report(Verdict.likelyReplica).evidenceItems[1],
          onBack: () {},
        ),
        scroll: 2000,
      );
      await shot(tester, '16_report_unsure', _reportView(_report(Verdict.inconclusive)));
      await shot(
        tester,
        '16_report_legacy',
        _reportView(_report(Verdict.likelyAuthentic, legacy: true), capture: false),
        ms: 4000,
      );
      await shot(
        tester,
        '16_report_unsure_small',
        _reportView(_report(Verdict.inconclusive)),
        small: true,
      );
      final r = _report(Verdict.likelyReplica);
      await shot(
        tester,
        '17_part_flagged',
        PartDetailView(item: r.evidenceItems[1], onBack: () {}),
      );
      await shot(
        tester,
        '17_part_consistent',
        PartDetailView(item: r.evidenceItems[0], onBack: () {}),
      );
      await shot(
        tester,
        '17_part_small',
        PartDetailView(item: r.evidenceItems[1], onBack: () {}),
        small: true,
      );
      await shot(
        tester,
        '22_error_network',
        ScanErrorView(
          errorMessage: '',
          appError: AppError.noInternet(),
          onRetry: () {},
          onCancel: () {},
        ),
      );
      await shot(
        tester,
        '22_error_billing',
        ScanErrorView(
          errorMessage: '',
          appError: AppError.fromException('billing 402'),
          onRetry: () {},
          onCancel: () {},
        ),
      );
      await shot(
        tester,
        '22_error_small',
        ScanErrorView(errorMessage: 'boom', onRetry: () {}, onCancel: () {}),
        small: true,
      );
      Widget np(
        String reason,
        String? photo, {
        List<String> missing = const [],
      }) => ScanValidationResultView(
        capturedImagePath: photo,
        status: missing.isEmpty
            ? IdentificationStatus.notProduct
            : IdentificationStatus.insufficientEvidence,
        reason: reason,
        message:
            'No supported luxury product detected in that photo. Try again with the item centered.',
        missingEvidence: missing,
        onTryAgain: () {},
        onClose: () {},
      );
      await shot(tester, '21_not_product', np('unsupported_object', null));
      await shot(tester, '21_not_product_photo', np('human_detected', _bagPhoto));
      await shot(
        tester,
        '21_not_product_partial',
        np(
          'partial_product_insufficient_evidence',
          _bagPhoto,
          missing: ['Brand logo', 'Interior label'],
        ),
        small: true,
      );
    });
  });
}
