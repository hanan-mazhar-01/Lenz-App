// Every component is pumped in the Lenz light theme on a 320pt wide phone
// (iPhone SE) with text scale 1.3 and must lay out without overflow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/widgets/ui/ui.dart';
import 'package:replica_detector/widgets/ui/ui_gallery_screen.dart';

import 'ui_test_utils.dart';

void _noop() {}

Widget _row(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in children) ...[c, const SizedBox(height: 10)],
      ],
    );

final Map<String, Widget Function()> _cases = {
  'LenzButton variants': () => _row([
        LenzButton(label: 'Primary', icon: LenzIcons.camera, onPressed: () {}),
        LenzButton(
          label: 'A rather long button label that must not overflow',
          icon: LenzIcons.sparkles,
          pulse: true,
          onPressed: () {},
        ),
        LenzButton(
          label: 'Ghost',
          variant: LenzButtonVariant.ghost,
          onPressed: () {},
        ),
        LenzButton(
          label: 'Soft',
          variant: LenzButtonVariant.soft,
          onPressed: () {},
        ),
        LenzButton(
          label: 'Upgrade to Lenz Pro',
          variant: LenzButtonVariant.gold,
          icon: LenzIcons.crown,
          onPressed: () {},
        ),
        LenzButton(
          label: 'Danger',
          variant: LenzButtonVariant.danger,
          onPressed: () {},
        ),
        LenzButton(
          label: 'Small',
          size: LenzButtonSize.sm,
          onPressed: () {},
        ),
        const LenzButton(label: 'Loading', loading: true, onPressed: _noop),
        const LenzButton(label: 'Disabled', onPressed: null),
        Align(
          alignment: Alignment.centerLeft,
          child: LenzButton(
            label: 'Scan an item',
            icon: LenzIcons.camera,
            variant: LenzButtonVariant.light,
            expand: false,
            onPressed: () {},
          ),
        ),
        Row(children: [
          Expanded(
            child: LenzSocialButton(
              label: 'Apple',
              icon: LenzIcons.apple,
              onPressed: () {},
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LenzSocialButton(
              label: 'Google',
              icon: LenzIcons.gicon,
              iconStrokeWidth: 0,
              onPressed: () {},
            ),
          ),
        ]),
      ]),
  'LenzIconButton': () => Row(children: [
        LenzIconButton(icon: LenzIcons.chevL, onTap: () {}),
        const SizedBox(width: 8),
        LenzIconButton(icon: LenzIcons.x, dark: true, onTap: () {}),
      ]),
  'LenzChip + LenzPill': () => Wrap(spacing: 8, runSpacing: 8, children: [
        const LenzChip(label: 'Guided photos', icon: LenzIcons.camera, selected: true),
        const LenzChip(label: 'Point by point', icon: LenzIcons.layers),
        const LenzChip(label: 'About 30 seconds and then some more words', icon: LenzIcons.bolt),
        LenzPill.verdict(Verdict.likelyAuthentic),
        LenzPill.verdict(Verdict.likelyReplica, short: false),
        LenzPill.verdict(Verdict.inconclusive, short: false),
        const LenzPill(label: 'PRO', variant: LenzPillVariant.gold),
        const LenzPill(label: 'Free plan', icon: LenzIcons.sparkles),
      ]),
  'LenzCard + header + divider': () => Column(children: const [
        LenzCard(child: Text('Card content that wraps over several lines to be sure it works')),
        LenzSectionHeader('Your recent checks and more words', actionLabel: 'See all'),
        LenzDivider(label: 'or continue with'),
        LenzDivider(),
      ]),
  'LenzTopBar': () => Column(children: [
        const LenzTopBar(title: 'A really long top bar title that has to ellipsize'),
        LenzTopBar(
          title: 'Report',
          actions: [
            LenzIconButton(icon: LenzIcons.heart, onTap: () {}),
            LenzIconButton(icon: LenzIcons.share, onTap: () {}),
          ],
        ),
        const LenzTopBar(title: 'Scan', dark: true, noBack: true),
      ]),
  'LenzField': () => Column(children: const [
        LenzField(hint: 'Email address', icon: LenzIcons.mail),
        SizedBox(height: 10),
        LenzField(hint: 'Password', icon: LenzIcons.lock, obscure: true),
        SizedBox(height: 10),
        LenzField(
          hint: 'Email address',
          icon: LenzIcons.mail,
          errorText: 'Enter a valid email address that includes an @ sign',
        ),
      ]),
  'LenzSegmented': () => LenzSegmented(
        labels: const ['Sign in', 'Create account'],
        index: 1,
        onChanged: (_) {},
      ),
  'LenzSwitch + LenzCheck': () => Row(children: [
        LenzSwitch(value: true, onChanged: (_) {}),
        const SizedBox(width: 12),
        LenzSwitch(value: false, onChanged: (_) {}),
        const SizedBox(width: 12),
        LenzCheck(value: true, onChanged: (_) {}),
        const SizedBox(width: 12),
        const LenzCheck(value: false),
      ]),
  'LenzSettingGroup': () => LenzSettingGroup(children: [
        LenzSettingRow(
          icon: LenzIcons.clock,
          title: 'Scan history with a long title',
          subtitle: 'View your past scans and everything about them',
          onTap: () {},
        ),
        LenzSettingRow(
          icon: LenzIcons.face,
          title: 'Face ID lock',
          subtitle: 'Unlock reports with biometrics on this device',
          trailing: LenzSwitch(value: true, onChanged: (_) {}),
        ),
        LenzSettingRow(
          icon: LenzIcons.logout,
          title: 'Log out',
          destructive: true,
          onTap: () {},
        ),
      ]),
  'LenzRing + LenzMeter + AnimatedCount': () => const Column(children: [
        Row(children: [
          LenzRing(
            value: .94,
            child: AnimatedCount(to: 94, suffix: '%', style: LenzText.title),
          ),
          SizedBox(width: 12),
          LenzRing(value: .4, size: 72, strokeWidth: 8, color: LenzColors.warn),
        ]),
        SizedBox(height: 12),
        LenzMeter(value: .9),
        SizedBox(height: 12),
        LenzMeter.warn(value: .3),
      ]),
  'LenzStagger': () => const LenzStagger(
        spacing: 8,
        children: [Text('One'), Text('Two'), Text('Three')],
      ),
  'LenzJourneyStepper': () => Column(children: [
        LenzJourneyStepper(step: 2, rider: const ColoredBox(color: LenzColors.leaf)),
        Container(
          color: LenzColors.camera,
          padding: const EdgeInsets.all(8),
          child: LenzJourneyStepper(step: 4, dark: true, rider: const SizedBox(height: 56)),
        ),
        const LenzJourneyStepper(step: 0),
      ]),
  'LenzToast': () => const LenzToast(message: 'A long toast message that needs to wrap on a small phone'),
  'LenzConfirmContent': () => const LenzConfirmContent(
        title: 'Delete your account?',
        text: 'This permanently removes your data and cannot be undone.',
        okLabel: 'Delete account',
        danger: true,
      ),
};

void main() {
  setUpAll(loadNunito);

  for (final e in _cases.entries) {
    testWidgets('${e.key} fits 320pt @ text scale 1.3', (tester) async {
      await pumpLenz(tester, e.value());
      await tester.pump(const Duration(milliseconds: 1600));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('LenzBlob + LenzMoodBackground paint', (tester) async {
    await pumpLenz(
      tester,
      const LenzMoodBackground(
        mood: Color(0xFFF8D6CF),
        child: Center(child: Text('Hi')),
      ),
      scaffold: false,
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
  });

  testWidgets('LenzTabBar fits 320pt @ text scale 1.3', (tester) async {
    await pumpLenz(
      tester,
      Scaffold(
        body: Stack(children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LenzTabBar(currentIndex: 3, onTab: (_) {}, onScan: () {}),
          ),
        ]),
      ),
      scaffold: false,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('UiGalleryScreen renders every component', (tester) async {
    await pumpLenz(tester, const UiGalleryScreen(), scaffold: false, height: 900);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    // scroll through the whole gallery to build every sliver child
    final list = find.byType(ListView).first;
    for (var i = 0; i < 24; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('showLenzSheet / showLenzConfirm fit 320pt @ 1.3', (tester) async {
    await pumpLenz(tester, Builder(builder: (context) {
      return Column(children: [
        LenzButton(
          label: 'sheet',
          onPressed: () => showLenzSheet<void>(
            context,
            builder: (_) => Column(children: [
              const Text('Reset your password', style: LenzText.title),
              const SizedBox(height: 12),
              const LenzField(hint: 'Email address', icon: LenzIcons.mail),
              const SizedBox(height: 12),
              LenzButton(label: 'Send reset link', onPressed: () {}),
            ]),
          ),
        ),
        LenzButton(
          label: 'confirm',
          onPressed: () => showLenzConfirm(
            context,
            title: 'Delete your account?',
            text: 'This permanently removes your data and cannot be undone.',
            okLabel: 'Delete account',
            danger: true,
            character: (_) => const SizedBox(height: 120),
          ),
        ),
      ]);
    }));
    await tester.tap(find.text('sheet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Reset your password'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(160, 20)); // scrim
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('confirm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion renders final states immediately', (tester) async {
    await pumpLenz(
      tester,
      const Column(children: [
        LenzRing(value: .5, child: AnimatedCount(to: 50)),
        LenzMeter(value: .5),
        LenzStagger(children: [Text('A')]),
      ]),
      disableAnimations: true,
    );
    await tester.pump();
    expect(find.text('50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
