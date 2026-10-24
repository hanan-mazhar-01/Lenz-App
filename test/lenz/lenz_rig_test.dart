import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/widgets/lenz/lenz.dart';

void main() {
  group('meta.json parsing', () {
    for (final dir in ['assets/lenz/character', 'assets/lenz/icon_closeup']) {
      test('$dir eye openings: path bounds equal bbox', () {
        final text = File('$dir/meta.json').readAsStringSync();
        final meta = LenzMeta.parse(text);
        for (final eye in [meta.openL, meta.openR]) {
          final b = eye.path.getBounds();
          expect(b.left, closeTo(eye.x0, 0.01));
          expect(b.top, closeTo(eye.y0, 0.01));
          expect(b.right, closeTo(eye.x1, 0.01));
          expect(b.bottom, closeTo(eye.y1, 0.01));
        }
        final raw = json.decode(text) as Map<String, dynamic>;
        for (final k in raw.keys.where((k) => !k.startsWith('open'))) {
          final r = meta.layers[k]!;
          expect(r.x, (raw[k]['x'] as num).toDouble());
          expect(r.w, (raw[k]['w'] as num).toDouble());
        }
      });
    }

    test('character meta has all 10 layers', () {
      final meta = LenzMeta.parse(File('assets/lenz/character/meta.json').readAsStringSync());
      expect(meta.layers.keys.toSet(), LenzAssets.charLayers.toSet());
    });
  });

  group('mood table', () {
    test('every mood has a pose and only known params', () {
      expect(kLenzMoods.keys.toSet(), LenzMood.values.toSet());
      expect(kLenzDefaults.keys.toSet(), LenzParam.values.toSet());
      expect(kLenzMoods[LenzMood.idle], isEmpty);
    });

    test('spot-check values copied from rig.js', () {
      expect(lenzMoodValue(LenzMood.inspect, LenzParam.magS), 1.04);
      expect(lenzMoodValue(LenzMood.inspect, LenzParam.fxPing), 1);
      expect(lenzMoodValue(LenzMood.sorry, LenzParam.tailRot), -6);
      expect(lenzMoodValue(LenzMood.happy, LenzParam.lowL), 0.72);
      expect(lenzMoodValue(LenzMood.shy, LenzParam.lidTR), 1);
      expect(lenzMoodValue(LenzMood.focus, LenzParam.bRr), -5);
      expect(lenzMoodValue(LenzMood.idle, LenzParam.gazeN), 0.55);
      expect(kLenzMoods.values.fold<int>(0, (n, m) => n + m.length), 141);
    });

    test('view rects and aspect ratios', () {
      expect(LenzView.full.aspectRatio, 1180 / 1400);
      expect(LenzView.bust.aspectRatio, 900 / 860);
      expect(LenzView.peek.aspectRatio, 720 / 700);
    });
  });

  group('springs', () {
    for (final mood in LenzMood.values) {
      test('converges to ${mood.name} target', () {
        final rig = LenzRig(wake: true, random: math.Random(7));
        rig.setMood(mood);
        for (var i = 0; i < 400; i++) {
          rig.advance(0.016);
        }
        for (final p in LenzParam.values) {
          expect(rig[p], closeTo(lenzMoodValue(mood, p), 1e-3), reason: p.name);
        }
      });
    }

    test('reduced motion: all springs critically damped (no overshoot)', () {
      final rig = LenzRig(wake: false, reduceMotion: true, random: math.Random(1));
      rig.setMood(LenzMood.shocked);
      var maxNod = 0.0;
      for (var i = 0; i < 300; i++) {
        rig.advance(0.016);
        maxNod = math.min(maxNod, rig[LenzParam.nod]);
      }
      expect(maxNod, greaterThanOrEqualTo(-10.001));
      expect(rig.mot, 0.3);
    });

    test('wake opens the lids after ~260ms', () {
      final rig = LenzRig(random: math.Random(1));
      expect(rig[LenzParam.lidTL], 1);
      for (var i = 0; i < 10; i++) {
        rig.advance(0.016);
      }
      expect(rig.tgt[LenzParam.lidTL.index], 1);
      for (var i = 0; i < 60; i++) {
        rig.advance(0.016);
      }
      expect(rig.tgt[LenzParam.lidTL.index], 0);
      expect(rig[LenzParam.lidTL], lessThan(0.1));
    });

    test('tap bounce is an impulse that decays', () {
      final rig = LenzRig(wake: false, random: math.Random(1))..bounce();
      rig.advance(0.016);
      expect(rig[LenzParam.bump], lessThan(0));
      for (var i = 0; i < 300; i++) {
        rig.advance(0.016);
      }
      expect(rig[LenzParam.bump].abs(), lessThan(1e-3));
    });
  });
}
