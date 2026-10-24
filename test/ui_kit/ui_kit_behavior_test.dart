
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/core/theme/app_colors.dart';
import 'package:replica_detector/core/theme/app_theme.dart';
import 'package:replica_detector/core/theme/app_typography.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/widgets/animations/bounce_button.dart';
import 'package:replica_detector/widgets/animations/fade_slide_transition.dart';
import 'package:replica_detector/widgets/ui/lenz_svg_path.dart';
import 'package:replica_detector/widgets/ui/ui.dart';

import 'ui_test_utils.dart';

/// Tight bounds by sampling (Path.getBounds includes conic control points).
Rect _tight(Path p) {
  Rect? r;
  for (final m in p.computeMetrics()) {
    for (var d = 0.0; d <= m.length; d += .1) {
      final o = m.getTangentForOffset(d)!.position;
      final pr = Rect.fromLTRB(o.dx, o.dy, o.dx, o.dy);
      r = r == null ? pr : r.expandToInclude(pr);
    }
  }
  return r ?? Rect.zero;
}

Finder _icon(String name) =>
    find.byWidgetPredicate((w) => w is LenzIcon && w.name == name);

void main() {
  setUpAll(loadNunito);

  group('tokens and theme', () {
    test('LenzColors match the prototype palette', () {
      expect(LenzColors.ivory, const Color(0xFFFCF8F6));
      expect(LenzColors.ink, const Color(0xFF10241C));
      expect(LenzColors.forest, const Color(0xFF122F24));
      expect(LenzColors.forest2, const Color(0xFF1D4C3A));
      expect(LenzColors.mint, const Color(0xFFD6E8DE));
      expect(LenzColors.mint2, const Color(0xFFEAF4EE));
      expect(LenzColors.leaf, const Color(0xFF2EA44F));
      expect(LenzColors.gold, const Color(0xFFD4AF37));
      expect(LenzColors.gold2, const Color(0xFFF4D97B));
      expect(LenzColors.muted, const Color(0xFF66716B));
      expect(LenzColors.ok, const Color(0xFF1F8A4C));
      expect(LenzColors.okSoft, const Color(0xFFDDF1E4));
      expect(LenzColors.bad, const Color(0xFFC23B3B));
      expect(LenzColors.badSoft, const Color(0xFFFBE0DC));
      expect(LenzColors.warn, const Color(0xFFB9741A));
      expect(LenzColors.warnSoft, const Color(0xFFFBEBC1));
    });

    test('spring / ease curves and shadows', () {
      expect(LenzMotion.spring, const Cubic(.34, 1.56, .64, 1));
      expect(LenzMotion.ease, const Cubic(.2, .8, .2, 1));
      // the spring overshoots
      expect(LenzMotion.spring.transform(.6), greaterThan(1));
      // countUp is 1-(1-t)^3
      expect(LenzMotion.countUp.transform(.5), closeTo(.875, 1e-9));
      expect(LenzShadows.sh1, hasLength(2));
      expect(LenzShadows.sh2.last.blurRadius, 40);
    });

    test('type scale uses Nunito with the prototype sizes', () {
      expect(LenzText.display.fontSize, 32);
      expect(LenzText.display.fontWeight, FontWeight.w900);
      expect(LenzText.display.letterSpacing, closeTo(-1.12, 1e-9));
      expect(LenzText.title.fontSize, 22);
      expect(LenzText.sub.fontSize, 14.5);
      expect(LenzText.cap.fontSize, 12.5);
      expect(LenzText.display.fontFamily, 'Nunito');
    });

    test('legacy AppColors / AppTypography keep their API and use the palette', () {
      expect(AppColors.warmIvory, LenzColors.ivory);
      expect(AppColors.deepForestGreen, LenzColors.forest);
      expect(AppColors.nearBlack, LenzColors.ink);
      expect(AppColors.danger, LenzColors.bad);
      expect(AppTypography.titleLarge.fontFamily, 'Nunito');
      expect(AppTypography.bodyMedium.fontSize, 14.5);
      expect(AppTypography.scoreNumber.fontWeight, FontWeight.w900);
    });

    test('AppTheme is the light Nunito Material 3 theme', () {
      final t = AppTheme.lightTheme;
      expect(t.useMaterial3, isTrue);
      expect(t.brightness, Brightness.light);
      expect(t.scaffoldBackgroundColor, LenzColors.ivory);
      expect(t.colorScheme.primary, LenzColors.forest);
      expect(t.textTheme.bodyMedium!.fontFamily, 'Nunito');
      expect(AppTheme.darkTheme.brightness, Brightness.light);
    });

    test('CSS angle gradient points along the 155deg line', () {
      final g = LenzGradients.hero;
      final shader = g.createShader(const Rect.fromLTWH(0, 0, 350, 236));
      expect(shader, isNotNull);
    });
  });

  group('svg paths and icons', () {
    test('parser handles absolute, relative, h/v, curves and arcs', () {
      final p = parseSvgPathData('M0 0h10v10H0z');
      expect(p.getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
      final rel = parseSvgPathData('m1 1l2 2 2-2');
      expect(rel.getBounds(), const Rect.fromLTRB(1, 1, 5, 3));
      final arc = parseSvgPathData('M0 0a5 5 0 0 1 10 0');
      final b = arc.getBounds();
      expect(b.width, closeTo(10, .01));
      expect(b.top, closeTo(-5, .05));
      final compact = parseSvgPathData('M12 17h.01M1.300-1.900L2 2');
      expect(compact.getBounds().left, closeTo(1.3, 1e-6));
      expect(() => parseSvgPathData('M0 0 Q'), throwsFormatException);
    });

    test('every prototype icon parses and fits the 24px viewBox', () {
      expect(LenzIcons.all.length, 45);
      for (final name in LenzIcons.all) {
        final paths = lenzIconPaths(name);
        expect(paths, isNotEmpty, reason: name);
        for (final p in paths) {
          final b = _tight(p);
          expect(b.left, greaterThanOrEqualTo(-.5), reason: name);
          expect(b.top, greaterThanOrEqualTo(-.5), reason: name);
          expect(b.right, lessThanOrEqualTo(24.5), reason: name);
          expect(b.bottom, lessThanOrEqualTo(24.5), reason: name);
        }
      }
    });

    testWidgets('LenzIcon takes size and uses the icon theme colour', (tester) async {
      await pumpLenz(
        tester,
        const IconTheme(
          data: IconThemeData(color: Colors.red, size: 30),
          child: LenzIcon(LenzIcons.home),
        ),
      );
      expect(tester.getSize(find.byType(LenzIcon)), const Size(30, 30));
    });
  });

  group('buttons', () {
    testWidgets('LenzButton taps, disabled and loading do not', (tester) async {
      var taps = 0;
      await pumpLenz(
        tester,
        Column(children: [
          LenzButton(label: 'Go', onPressed: () => taps++),
          LenzButton(label: 'Off', onPressed: null),
          LenzButton(label: 'Busy', loading: true, onPressed: () => taps += 100),
        ]),
      );
      await tester.tap(find.text('Go'));
      await tester.tap(find.text('Off'), warnIfMissed: false);
      await tester.tap(find.byType(CircularProgressIndicator), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
    });

    testWidgets('LenzButton has the prototype geometry', (tester) async {
      await pumpLenz(
        tester,
        Column(children: [
          LenzButton(label: 'md', onPressed: () {}),
          LenzButton(label: 'sm', size: LenzButtonSize.sm, onPressed: () {}),
        ]),
        textScale: 1,
      );
      final md = tester.getSize(find.byType(LenzButton).at(0));
      final sm = tester.getSize(find.byType(LenzButton).at(1));
      expect(md.height, 58);
      expect(sm.height, 44);
      expect(md.width, 280);
    });

    testWidgets('press scales down with the spring and returns to 1', (tester) async {
      await pumpLenz(
        tester,
        Center(child: LenzButton(label: 'Press', expand: false, onPressed: () {})),
        textScale: 1,
      );
      double scale() => tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byType(LenzPressable),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .storage[0];
      expect(scale(), 1);
      final g = await tester.startGesture(tester.getCenter(find.text('Press')));
      await tester.pump(const Duration(milliseconds: 120)); // tap-down deadline
      await tester.pump(const Duration(milliseconds: 300));
      expect(scale(), closeTo(.96, .001));
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(scale(), closeTo(1, .001));
    });

    testWidgets('BounceButton (legacy) still works', (tester) async {
      var taps = 0;
      await pumpLenz(
        tester,
        BounceButton(onTap: () => taps++, child: const Text('legacy')),
      );
      await tester.tap(find.text('legacy'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
    });

    testWidgets('FadeSlideTransition (legacy) stays hidden for its delay, then fades in', (tester) async {
      await pumpLenz(
        tester,
        const FadeSlideTransition(
          delay: Duration(milliseconds: 200),
          child: Text('hello'),
        ),
      );
      expect(
        tester.widget<Opacity>(find.ancestor(of: find.text('hello'), matching: find.byType(Opacity)).first).opacity,
        0,
      );
      await tester.pump(const Duration(milliseconds: 300)); // delay elapsed
      await tester.pump(const Duration(seconds: 1));
      expect(find.ancestor(of: find.text('hello'), matching: find.byType(Opacity)), findsNothing);
    });
  });

  group('controls', () {
    testWidgets('LenzSegmented toggles and the thumb slides', (tester) async {
      var index = 0;
      await pumpLenz(
        tester,
        StatefulBuilder(
          builder: (context, setState) => LenzSegmented(
            labels: const ['Sign in', 'Create account'],
            index: index,
            onChanged: (i) => setState(() => index = i),
          ),
        ),
        textScale: 1,
      );
      double thumbLeft() =>
          tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).left!;
      expect(thumbLeft(), 0);
      await tester.tap(find.text('Create account'));
      await tester.pump();
      expect(index, 1);
      await tester.pump(const Duration(milliseconds: 600));
      // (280 - 10 - 4) / 2 + 4 = 137
      expect(thumbLeft(), closeTo(137, .01));
      await tester.tap(find.text('Sign in'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(index, 0);
      expect(thumbLeft(), 0);
    });

    testWidgets('LenzSwitch and LenzCheck toggle', (tester) async {
      var on = false;
      var checked = false;
      await pumpLenz(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Row(children: [
            LenzSwitch(value: on, onChanged: (v) => setState(() => on = v)),
            const SizedBox(width: 20),
            LenzCheck(value: checked, onChanged: (v) => setState(() => checked = v)),
          ]),
        ),
      );
      await tester.tap(find.byType(LenzSwitch));
      await tester.tap(find.byType(LenzCheck));
      await tester.pump(const Duration(milliseconds: 500));
      expect(on, isTrue);
      expect(checked, isTrue);
      expect(tester.getSize(find.byType(LenzSwitch)), const Size(52, 32));
      expect(tester.getSize(find.byType(LenzCheck)), const Size(26, 26));
    });

    testWidgets('LenzField: focus callback, obscure toggle, error text', (tester) async {
      final focus = <bool>[];
      final controller = TextEditingController();
      await pumpLenz(
        tester,
        LenzField(
          controller: controller,
          hint: 'Password',
          icon: LenzIcons.lock,
          obscure: true,
          errorText: 'Too short',
          onFocusChanged: focus.add,
        ),
        textScale: 1,
      );
      expect(find.text('Too short'), findsOneWidget);
      expect(_icon(LenzIcons.eye), findsOneWidget);
      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 300));
      expect(focus, [true]);
      await tester.enterText(find.byType(TextField), 'secret');
      expect(controller.text, 'secret');
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      await tester.tap(_icon(LenzIcons.eye));
      await tester.pump();
      expect(_icon(LenzIcons.eyeOff), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
      expect(tester.getSize(find.byType(AnimatedContainer).first).height, 58);
    });

    testWidgets('LenzChip selection and LenzPill.verdict labels', (tester) async {
      var taps = 0;
      await pumpLenz(
        tester,
        Wrap(children: [
          LenzChip(label: 'Bags', selected: true, onTap: () => taps++),
          LenzPill.verdict(Verdict.likelyAuthentic),
          LenzPill.verdict(Verdict.likelyReplica),
          LenzPill.verdict(Verdict.inconclusive),
        ]),
      );
      await tester.tap(find.text('Bags'));
      expect(taps, 1);
      expect(find.text('Authentic'), findsOneWidget);
      expect(find.text('Replica'), findsOneWidget);
      expect(find.text('Not sure'), findsOneWidget);
    });

    test('LenzVerdictStyle maps the Verdict enum', () {
      expect(LenzVerdictStyle.of(Verdict.likelyAuthentic).label, 'Appears Authentic');
      expect(LenzVerdictStyle.of(Verdict.likelyReplica).label, 'Likely Replica');
      expect(LenzVerdictStyle.of(Verdict.inconclusive).label, 'Unable to Verify');
      expect(LenzVerdictStyle.of(Verdict.likelyReplica).short, 'Replica');
      expect(LenzVerdictStyle.of(Verdict.likelyAuthentic).color, LenzColors.ok);
      expect(LenzVerdictStyle.of(Verdict.likelyReplica).soft, LenzColors.badSoft);
      expect(LenzVerdictStyle.ofOrUnsure(null).kind, LenzVerdictKind.unsure);
    });
  });

  group('progress', () {
    LenzRingPainter ringPainter(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find
            .descendant(of: find.byType(LenzRing), matching: find.byType(CustomPaint))
            .first,
      );
      return paint.painter! as LenzRingPainter;
    }

    testWidgets('LenzRing starts empty and reaches its value', (tester) async {
      await pumpLenz(tester, const LenzRing(value: .75, child: Text('75')));
      expect(ringPainter(tester).progress, 0);
      await tester.pump(const Duration(milliseconds: 700)); // delay + part of 1.4s
      final mid = ringPainter(tester).progress;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(.75));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(ringPainter(tester).progress, closeTo(.75, 1e-6));
    });

    testWidgets('LenzRing retargets from the current value', (tester) async {
      Widget ring(double v) => LenzRing(value: v);
      await pumpLenz(tester, ring(.2));
      await tester.pump(const Duration(seconds: 2));
      expect(ringPainter(tester).progress, closeTo(.2, 1e-6));
      await pumpLenz(tester, ring(.9));
      await tester.pump(const Duration(seconds: 2));
      expect(ringPainter(tester).progress, closeTo(.9, 1e-6));
    });

    testWidgets('LenzMeter fills to its value', (tester) async {
      await pumpLenz(tester, const LenzMeter(value: .5), textScale: 1);
      FractionallySizedBox box() =>
          tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
      expect(box().widthFactor, 0);
      await tester.pump(const Duration(milliseconds: 2000));
      expect(box().widthFactor, closeTo(.5, 1e-6));
      expect(tester.getSize(find.byType(LenzMeter)).height, 10);
    });

    testWidgets('AnimatedCount counts up with a cubic ease-out', (tester) async {
      await pumpLenz(
        tester,
        const AnimatedCount(to: 94, suffix: '%', style: LenzText.title),
      );
      expect(find.text('0%'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600)); // half way
      final mid = int.parse(
        tester.widget<Text>(find.byType(Text)).data!.replaceAll('%', ''),
      );
      expect(mid, closeTo((94 * .875).round(), 3));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('94%'), findsOneWidget);
    });
  });

  group('motion helpers', () {
    testWidgets('LenzStagger reveals children one after another', (tester) async {
      await pumpLenz(
        tester,
        const LenzStagger(children: [Text('A'), Text('B'), Text('C')]),
      );
      double opacityOf(String t) => tester
          .widget<Opacity>(
            find.ancestor(of: find.text(t), matching: find.byType(Opacity)).first,
          )
          .opacity;
      expect(opacityOf('A'), 0);
      await tester.pump(const Duration(milliseconds: 350));
      // A (120ms lead) is well on its way, C (230ms lead) has barely started.
      expect(opacityOf('A'), greaterThan(opacityOf('C')));
      await tester.pump(const Duration(seconds: 2));
      for (final t in ['A', 'B', 'C']) {
        expect(find.ancestor(of: find.text(t), matching: find.byType(Opacity)), findsNothing);
      }
    });

    testWidgets('LenzJourneyStepper moves its fill and rider to the step', (tester) async {
      await pumpLenz(
        tester,
        const LenzJourneyStepper(step: 4, rider: SizedBox(height: 56)),
        textScale: 1,
      );
      Rect riderRect() => tester.getRect(
            find.descendant(
              of: find.byType(LenzJourneyStepper),
              matching: find.byWidgetPredicate(
                (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle && (w.decoration as BoxDecoration).color == LenzColors.mint,
              ),
            ),
          );
      final start = riderRect().center.dx;
      await tester.pump(const Duration(milliseconds: 2000));
      final end = riderRect().center.dx;
      // pumpLenz pads the page by 20: stepper padding 6 + 14 inset.
      expect(start, closeTo(20 + 6 + 14, 1));
      expect(end, closeTo(20 + 280 - 6 - 14, 1));
    });

    testWidgets('showLenzToast appears and disappears after ~2.6s', (tester) async {
      await pumpLenz(tester, const SizedBox());
      final context = tester.element(find.byType(SizedBox).first);
      showLenzToast(context, 'Saved to favorites');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Saved to favorites'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2800));
      expect(find.text('Saved to favorites'), findsNothing);
    });

    testWidgets('a new toast replaces the current one', (tester) async {
      await pumpLenz(tester, const SizedBox());
      final context = tester.element(find.byType(SizedBox).first);
      showLenzToast(context, 'one');
      await tester.pump(const Duration(milliseconds: 200));
      showLenzToast(context, 'two');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('one'), findsNothing);
      expect(find.text('two'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('sheets', () {
    testWidgets('showLenzConfirm resolves true on ok and false on cancel', (tester) async {
      bool? result;
      var okCalled = false;
      await pumpLenz(
        tester,
        Builder(
          builder: (context) => LenzButton(
            label: 'open',
            onPressed: () => showLenzConfirm(
              context,
              title: 'Log out?',
              text: 'You can sign back in any time.',
              okLabel: 'Log out',
              onOk: () => okCalled = true,
            ).then((v) => result = v),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Log out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(result, isFalse);
      expect(okCalled, isFalse);
      expect(find.text('Log out?'), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text('Log out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(result, isTrue);
      expect(okCalled, isTrue);
    });

    testWidgets('a sheet can be dragged down to dismiss', (tester) async {
      await pumpLenz(
        tester,
        Builder(
          builder: (context) => LenzButton(
            label: 'open',
            onPressed: () => showLenzSheet<void>(
              context,
              builder: (_) => const SizedBox(height: 200, child: Text('sheet body')),
            ),
          ),
        ),
        textScale: 1,
        height: 700,
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('sheet body'), findsOneWidget);
      await tester.fling(find.text('sheet body'), const Offset(0, 400), 1500);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('sheet body'), findsNothing);
    });

    testWidgets('the confirm sheet shows the character slot', (tester) async {
      await pumpLenz(
        tester,
        Builder(
          builder: (context) => LenzButton(
            label: 'open',
            onPressed: () => showLenzConfirm(
              context,
              title: 'T',
              text: 'x',
              character: (_) => const SizedBox(key: Key('slot'), height: 100),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const Key('slot')), findsOneWidget);
      // the slot is laid out 150px wide, like `width:150px` in confirmSheet()
      expect(tester.getSize(find.byKey(const Key('slot'))).width, 150);
    });
  });

  group('tab bar', () {
    Future<List<String>> pumpBar(
      WidgetTester tester, {
      int current = 0,
      bool hidden = false,
    }) async {
      final log = <String>[];
      await pumpLenz(
        tester,
        Scaffold(
          body: Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LenzTabBar(
                currentIndex: current,
                hidden: hidden,
                onTab: (i) => log.add('tab$i'),
                onScan: () => log.add('scan'),
              ),
            ),
          ]),
        ),
        scaffold: false,
        textScale: 1,
      );
      await tester.pump(const Duration(seconds: 1));
      return log;
    }

    testWidgets('tapping tabs reports indices 0..3 and the FAB reports scan', (tester) async {
      final log = await pumpBar(tester);
      await tester.tap(find.text('Home'));
      await tester.tap(find.text('History'));
      await tester.tap(find.text('Saved'));
      await tester.tap(find.text('Profile'));
      await tester.tap(_icon(LenzIcons.camera));
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, ['tab0', 'tab1', 'tab2', 'tab3', 'scan']);
    });

    testWidgets('geometry: docked 82px bar, 68px FAB raised into the notch', (tester) async {
      await pumpBar(tester);
      final bar = tester.getRect(
        find.descendant(
          of: find.byType(LenzTabBar),
          matching: find.byType(CustomPaint),
        ).first,
      );
      expect(bar.height, 82);
      expect(bar.left, 0);
      expect(bar.right, 320);
      expect(bar.bottom, closeTo(640, .01));
      final fab = tester.getRect(
        find.ancestor(of: _icon(LenzIcons.camera), matching: find.byType(DecoratedBox)).first,
      );
      expect(fab.width, 68);
      expect(fab.center.dx, closeTo(160, .01));
      expect(fab.top, closeTo(bar.top - 28, .01));
    });

    testWidgets('the active tab has no rounded container behind its icon', (tester) async {
      await pumpBar(tester, current: 3);
      final pills = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(16),
      );
      expect(pills, findsNothing);
      // the active label is still emphasised and the leaf indicator is shown
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('hidden bar slides away and ignores taps', (tester) async {
      final log = await pumpBar(tester, hidden: true);
      await tester.tap(find.text('Home'), warnIfMissed: false);
      expect(log, isEmpty);
      final op = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
      expect(op.opacity, 0);
    });

    testWidgets('hide / show animates translateY', (tester) async {
      var hidden = false;
      late StateSetter set;
      await pumpLenz(
        tester,
        Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            set = setState;
            return Stack(children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LenzTabBar(
                  currentIndex: 0,
                  hidden: hidden,
                  onTab: (_) {},
                  onScan: () {},
                ),
              ),
            ]);
          }),
        ),
        scaffold: false,
        textScale: 1,
      );
      await tester.pump(const Duration(seconds: 1));
      final shown = tester.getTopLeft(find.text('Home')).dy;
      set(() => hidden = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.getTopLeft(find.text('Home')).dy, closeTo(shown + 150, 1));
      set(() => hidden = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.getTopLeft(find.text('Home')).dy, closeTo(shown, 1));
    });
  });

  group('routes', () {
    Future<void> pumpHome(WidgetTester tester, LenzPageRoute<void> Function(Widget) make) async {
      await pumpLenz(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: LenzButton(
                label: 'go',
                expand: false,
                onPressed: () => Navigator.of(context).push(
                  make(
                    Scaffold(
                      body: Center(
                        child: Builder(
                          builder: (context) => LenzButton(
                            label: 'back',
                            expand: false,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        scaffold: false,
        textScale: 1,
      );
    }

    for (final (name, make) in <(String, LenzPageRoute<void> Function(Widget))>[
      ('forward', LenzRoutes.forward<void>),
      ('modalUp', LenzRoutes.modalUp<void>),
      ('zoom', LenzRoutes.zoom<void>),
      ('fade', LenzRoutes.fade<void>),
    ]) {
      testWidgets('$name pushes and pops', (tester) async {
        await pumpHome(tester, make);
        await tester.tap(find.text('go'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text('back'), findsOneWidget);
        expect(find.text('go'), findsNothing); // old route is offstage once covered
        await tester.tap(find.text('back'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text('back'), findsNothing);
        expect(find.text('go'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('forward durations match the prototype', (tester) async {
      expect(LenzRouteKind.forward.duration, const Duration(milliseconds: 560));
      expect(LenzRouteKind.modalUp.duration, const Duration(milliseconds: 640));
      expect(LenzRouteKind.modalUp.reverseDuration, const Duration(milliseconds: 560));
      expect(LenzRouteKind.zoom.duration, const Duration(milliseconds: 700));
      expect(LenzRouteKind.fade.duration, const Duration(milliseconds: 420));
    });

    testWidgets('swipe from the left edge pops a forward route', (tester) async {
      await pumpHome(
        tester,
        (page) => LenzRoutes.forward<void>(page, swipeBack: true),
      );
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('back'), findsOneWidget);
      await tester.dragFrom(const Offset(4, 300), const Offset(280, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('back'), findsNothing);
      expect(find.text('go'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short swipe snaps back and keeps the route', (tester) async {
      await pumpHome(
        tester,
        (page) => LenzRoutes.forward<void>(page, swipeBack: true),
      );
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 800));
      final g = await tester.startGesture(const Offset(4, 300));
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('back'), findsOneWidget);
    });
  });
}
