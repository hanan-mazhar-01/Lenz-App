// Fidelity dump: writes PNGs of every mood x view to /tmp/lenz_char_check
// when LENZ_DUMP=1 (used for visual comparison with the prototype refs).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/widgets/lenz/lenz.dart';

import 'lenz_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dump = Platform.environment['LENZ_DUMP'] == '1';

  test('dump renders', () async {
    await loadNunito();
    await LenzAssets.instance.ensureAllLoaded();
    expect(LenzAssets.instance.isReady, isTrue);
    const out = '/tmp/lenz_char_check';
    final settleS = double.tryParse(Platform.environment['LENZ_T'] ?? '') ?? 1.3;
    for (final view in LenzView.values) {
      for (final mood in LenzMood.values) {
        final rig = LenzRig(mood: mood, wake: false, random: math.Random(3));
        settle(rig, settleS);
        rig.blink = 0;
        rig.lookX = 0;
        rig.lookY = 0;
        final img = await renderRig(rig, view, width: 600, shadow: view == LenzView.full);
        if (dump) await writePng(img, '$out/${mood.name}_${view.name}.png');
      }
    }
    // Static pose: no oscillation, neutral gaze, open lids -> must equal artwork.
    final rig = LenzRig(wake: false, random: math.Random(1));
    for (final p in [LenzParam.bobAmp, LenzParam.magAmp, LenzParam.tailAmp, LenzParam.gazeN]) {
      rig.cur[p.index] = 0;
      rig.tgt[p.index] = 0;
    }
    final img = await renderRig(rig, LenzView.full, width: 1180, fx: false);
    if (dump) await writePng(img, '$out/static_full_1x.png');
  }, skip: !dump);

  testWidgets('dump icon close-up', (tester) async {
    await tester.runAsync(() => LenzAssets.instance.ensureIconLoaded());
    final key = GlobalKey();
    final c = LenzIconCloseupController();
    tester.view.physicalSize = const Size(1254, 1254);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> shot(String name, Size size) async {
      await tester.pumpWidget(Center(child: RepaintBoundary(key: key, child: SizedBox.fromSize(size: size, child: LenzIconCloseup(controller: c)))));
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = (await tester.runAsync(() => b.toImage()))!;
      await tester.runAsync(() => writePng(img, '/tmp/lenz_char_check/icon_$name.png'));
    }
    c.set(viewBox: LenzIconCloseupController.fullViewBox);
    await shot('static_full', const Size(1254, 1254));
    for (final t in [0.2, 0.6, 1.2, 1.8, 2.45, 3.0]) {
      c.applySplashScript(t);
      await shot('t$t', const Size(390, 844));
    }
  }, skip: !dump);
}
