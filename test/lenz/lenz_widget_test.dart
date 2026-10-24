import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/views/debug/lenz_character_debug_screen.dart';
import 'package:replica_detector/widgets/lenz/lenz.dart';

import 'lenz_test_utils.dart';

Future<void> _load(WidgetTester tester) async {
  await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
  expect(LenzAssets.instance.isReady, isTrue);
  expect(LenzAssets.instance.isIconReady, isTrue);
}

void main() {
  setUpAll(() async {
    await loadNunito();
    await LenzAssets.instance.ensureAllLoaded();
  });

  testWidgets('every mood x view pumps frames without exceptions', (tester) async {
    await _load(tester);
    for (final view in LenzView.values) {
      for (final mood in LenzMood.values) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: SizedBox(width: 180, child: LenzCharacter(mood: mood, view: view, shadow: true))),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(tester.takeException(), isNull, reason: '${mood.name}/${view.name}');
      }
    }
    // Mood switch through didUpdateWidget + tap + controller.
    final ctrl = LenzController();
    await tester.pumpWidget(Center(child: SizedBox(width: 180, child: LenzCharacter(controller: ctrl))));
    expect(ctrl.isAttached, isTrue);
    ctrl.setMood(LenzMood.happy);
    ctrl.hop();
    await tester.tap(find.byType(LenzCharacter));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ctrl.mood, LenzMood.happy);
    await tester.pumpWidget(const SizedBox());
    expect(ctrl.isAttached, isFalse);
  });

  testWidgets('pointer tracking and reduced motion do not throw', (tester) async {
    await _load(tester);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Center(child: SizedBox(width: 200, child: LenzCharacter(view: LenzView.bust))),
      ),
    );
    final g = await tester.startGesture(const Offset(10, 10));
    await g.moveTo(const Offset(700, 500));
    await tester.pump(const Duration(milliseconds: 16));
    await g.up();
    expect(LenzPointer.idleMs, lessThan(2600));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('icon close-up paints and follows the splash script', (tester) async {
    await _load(tester);
    final c = LenzIconCloseupController();
    await tester.pumpWidget(Center(child: SizedBox(width: 300, height: 600, child: LenzIconCloseup(controller: c))));
    for (final t in [0.0, 0.6, 1.2, 1.8, 2.4, 3.0, 4.0]) {
      c.applySplashScript(t);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(c.viewBox, LenzIconCloseupController.fullViewBox);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pixel sanity: widget renders a plausible non-empty image', (tester) async {
    await _load(tester);
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: const SizedBox(width: 236, child: LenzCharacter(wake: false, fx: false)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = (await tester.runAsync(() => boundary.toImage()))!;
    final px = (await tester.runAsync(() => rgba(img)))!;
    final w = img.width, h = img.height;
    var minX = w, minY = h, maxX = -1, maxY = -1, opaque = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (px[(y * w + x) * 4 + 3] > 128) {
          opaque++;
          minX = math.min(minX, x);
          maxX = math.max(maxX, x);
          minY = math.min(minY, y);
          maxY = math.max(maxY, y);
        }
      }
    }
    // Artwork spans roughly x 107..1112, y 18..1239 of 1254; view is 40..1220 / -150..1250.
    expect(opaque, greaterThan(w * h * 0.25));
    expect(minX / w, closeTo((107 - 40) / 1180, 0.04));
    expect(maxX / w, closeTo((1112 - 40) / 1180, 0.04));
    expect(minY / h, closeTo((18 + 150) / 1400, 0.04));
    expect(maxY / h, closeTo((1239 + 150) / 1400, 0.04));
  });

  testWidgets('debug screen builds and switches the preview', (tester) async {
    await _load(tester);
    await tester.pumpWidget(const MaterialApp(home: LenzCharacterDebugScreen()));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.ensureVisible(find.text('happy').first);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.text('happy').first);
    await tester.pump(const Duration(milliseconds: 100));
    final tile = tester.widget<Material>(find.ancestor(of: find.text('happy').first, matching: find.byType(Material)).first);
    expect(tile.color, const Color(0xFFD6E8DE));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 3000));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('happy / full'), findsOneWidget);
    await tester.tap(find.text('Reduce motion'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  test('offscreen painter output is non-empty for each view', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await LenzAssets.instance.ensureLoaded();
    for (final view in LenzView.values) {
      final rig = LenzRig(wake: false, random: math.Random(2));
      final ui.Image img = await renderRig(rig, view, width: 200);
      final px = await rgba(img);
      var opaque = 0;
      for (var i = 3; i < px.length; i += 4) {
        if (px[i] > 128) opaque++;
      }
      expect(opaque, greaterThan(img.width * img.height * 0.2), reason: view.name);
    }
  });
}
