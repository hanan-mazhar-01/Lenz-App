// Renders prototype-like frames of the kit to PNG for side-by-side comparison
// with the reference screenshots. Only runs when LENZ_UI_DUMP_DIR is set:
//
//   LENZ_UI_DUMP_DIR=/tmp/lenz_ui_check flutter test test/ui_kit/visual_dump_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/core/theme/app_theme.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/widgets/ui/ui.dart';

import 'ui_test_utils.dart';

final String? _dir = Platform.environment['LENZ_UI_DUMP_DIR'];

Future<void> _dump(WidgetTester tester, String name, Widget screen,
    {int settleMs = 3000, Future<void> Function()? before}) async {
  // flutter_test disables blurred shadows by default; draw them for the dump.
  debugDisableShadows = false;
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: RepaintBoundary(key: key, child: screen),
    ),
  );
  await before?.call();
  for (var i = 0; i < settleMs ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

Widget _screen({
  Color mood = LenzColors.mint,
  Color bg = LenzColors.ivory,
  required Widget body,
  Widget? bottom,
}) =>
    Material(
      color: bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bg == LenzColors.ivory) LenzBlob(color: mood),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 58, 20, 0),
              child: body,
            ),
          ),
          ?bottom,
        ],
      ),
    );

Widget _tabBar(int i) => Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: LenzTabBar(currentIndex: i, onTab: (_) {}, onScan: () {}),
    );

void main() {
  setUpAll(loadNunito);

  testWidgets('profile frame', skip: _dir == null, (tester) async {
    await _dump(
      tester,
      'profile',
      _screen(
        bottom: _tabBar(3),
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            Center(
              child: Container(
                width: 112,
                height: 112,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: LenzColors.mint,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Center(child: Text('Alex Morgan', style: LenzText.title)),
            const SizedBox(height: 4),
            const Center(child: Text('alex@veradostudio.com', style: LenzText.sub)),
            const SizedBox(height: 8),
            const Center(
              child: LenzPill(
                label: 'Free plan',
                icon: LenzIcons.sparkles,
              ),
            ),
            const SizedBox(height: 22),
            LenzCard(
              child: Row(
                children: [
                  LenzRing(
                    size: 76,
                    value: 1,
                    color: LenzColors.ringTrack,
                    child: const AnimatedCount(
                      to: 3,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: LenzColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Scan credits',
                            style: TextStyle(
                                fontFamily: 'Nunito',
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: LenzColors.ink)),
                        Text('3 free scans left this month.',
                            style: LenzText.sub),
                      ],
                    ),
                  ),
                  const LenzIcon(LenzIcons.chevR, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LenzButton(
              label: 'Upgrade to Lenz Pro',
              variant: LenzButtonVariant.gold,
              icon: LenzIcons.crown,
              onPressed: () {},
            ),
            const SizedBox(height: 14),
            LenzSettingGroup(
              children: [
                LenzSettingRow(
                  icon: LenzIcons.clock,
                  title: 'Scan history',
                  subtitle: 'View your past scans',
                  onTap: () {},
                ),
                LenzSettingRow(
                  icon: LenzIcons.heart,
                  title: 'Favorites',
                  subtitle: 'Reports you saved',
                  onTap: () {},
                ),
              ],
            ),
            LenzSettingGroup(
              children: [
                LenzSettingRow(
                  icon: LenzIcons.face,
                  title: 'Face ID lock',
                  subtitle: 'Unlock reports with biometrics',
                  trailing: LenzSwitch(value: true, onChanged: (_) {}),
                ),
                LenzSettingRow(
                  icon: LenzIcons.vibrate,
                  title: 'Haptic feedback',
                  subtitle: 'Gentle taps on actions',
                  trailing: LenzSwitch(value: true, onChanged: (_) {}),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('auth frame', skip: _dir == null, (tester) async {
    await _dump(
      tester,
      'auth',
      _screen(
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 180),
            LenzCard(
              radius: 30,
              child: Column(
                children: [
                  LenzSegmented(
                    labels: const ['Sign in', 'Create account'],
                    index: 0,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 14),
                  const LenzField(hint: 'Email address', icon: LenzIcons.mail),
                  const SizedBox(height: 12),
                  const LenzField(
                    hint: 'Password',
                    icon: LenzIcons.lock,
                    obscure: true,
                  ),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('Forgot password?', style: LenzText.link),
                  ),
                  const SizedBox(height: 10),
                  LenzButton(label: 'Sign in', onPressed: () {}),
                  const SizedBox(height: 14),
                  const LenzDivider(label: 'or continue with'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: LenzSocialButton(
                          label: 'Apple',
                          icon: LenzIcons.apple,
                          onPressed: () {},
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LenzSocialButton(
                          label: 'Google',
                          icon: LenzIcons.gicon,
                          iconStrokeWidth: 0,
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('journey frame', skip: _dir == null, (tester) async {
    await _dump(
      tester,
      'journey',
      _screen(
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            const LenzTopBar(title: 'Evidence'),
            LenzJourneyStepper(
              step: 2,
              rider: const SizedBox(width: 56, height: 56, child: ColoredBox(color: LenzColors.leaf)),
            ),
            const Row(
              children: [
                LenzRing(size: 100, value: .4, child: Text('2/5', style: LenzText.title)),
                SizedBox(width: 12),
                Expanded(child: Text('We need a closer look', style: LenzText.title)),
              ],
            ),
            const SizedBox(height: 16),
            const LenzMeter(value: .92),
            const SizedBox(height: 12),
            const LenzMeter.warn(value: .38),
            const SizedBox(height: 16),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                LenzChip(label: 'Guided photos', icon: LenzIcons.camera, selected: true),
                LenzChip(label: 'Point by point', icon: LenzIcons.layers),
                LenzPill(label: 'Done', variant: LenzPillVariant.auth),
                LenzPill(label: 'Blurry', variant: LenzPillVariant.unsure, icon: LenzIcons.warn),
                LenzPill(label: 'Pro', variant: LenzPillVariant.gold),
                LenzPill(label: 'Replica', variant: LenzPillVariant.fake, icon: LenzIcons.warn),
              ],
            ),
            const SizedBox(height: 16),
            LenzButton(
              label: 'Analyze now (3 of 5)',
              icon: LenzIcons.sparkles,
              pulse: true,
              onPressed: () {},
            ),
            const SizedBox(height: 10),
            LenzButton(label: 'Not this item', variant: LenzButtonVariant.ghost, onPressed: () {}),
            const SizedBox(height: 10),
            LenzButton(label: 'Keep anyway', variant: LenzButtonVariant.soft, onPressed: () {}),
            const SizedBox(height: 10),
            LenzButton(label: 'Delete account', variant: LenzButtonVariant.danger, onPressed: () {}),
            const SizedBox(height: 10),
            const LenzButton(label: 'Disabled', onPressed: null),
          ],
        ),
      ),
    );
  });

  testWidgets('home frame', skip: _dir == null, (tester) async {
    await _dump(
      tester,
      'home',
      _screen(
        bottom: _tabBar(0),
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 380),
            Row(
              children: [
                for (final (n, l) in const [(3, 'Scans left'), (7, 'Checks run'), (4, 'Authentic')]) ...[
                  Expanded(
                    child: LenzCard(
                      radius: LenzRadii.stat,
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedCount(to: n, style: LenzText.stat),
                          Text(l, style: LenzText.statLabel),
                        ],
                      ),
                    ),
                  ),
                  if (l != 'Authentic') const SizedBox(width: 10),
                ],
              ],
            ),
            const LenzSectionHeader('Browse your items'),
            const LenzSectionHeader('Your recent checks', actionLabel: 'See all'),
            LenzCard(
              onTap: () {},
              padding: const EdgeInsets.all(12),
              radius: LenzRadii.item,
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: LenzColors.mint2,
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Neverfull MM', style: LenzText.item),
                        Text('Louis Vuitton · Today, 9:41', style: LenzText.itemSub),
                      ],
                    ),
                  ),
                  LenzPill.verdict(Verdict.likelyAuthentic),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('sheet frame', skip: _dir == null, (tester) async {
    await _dump(
      tester,
      'sheet',
      Material(
        color: const Color(0xFF8C968F),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: LenzSheetFrame(
            child: Column(
              children: [
                const SizedBox(height: 150),
                const Text('Reset your password', style: LenzText.title, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                const Text('We will email you a reset link.', style: LenzText.sub),
                const SizedBox(height: 14),
                const LenzField(hint: 'Email address', icon: LenzIcons.mail),
                const SizedBox(height: 14),
                LenzButton(label: 'Send reset link', onPressed: () {}),
              ],
            ),
          ),
        ),
      ),
    );
  });

  testWidgets('states frame', skip: _dir == null, (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await _dump(
      tester,
      'states',
      _screen(
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 16),
            LenzSegmented(
              labels: const ['Sign in', 'Create account'],
              index: 1,
              onChanged: (_) {},
            ),
            const SizedBox(height: 16),
            LenzField(focusNode: node, hint: 'Full name', icon: LenzIcons.user),
            const SizedBox(height: 16),
            const LenzField(
              hint: 'Email address',
              icon: LenzIcons.mail,
              errorText: 'Enter a valid email address',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                LenzSwitch(value: false, onChanged: (_) {}),
                const SizedBox(width: 12),
                LenzSwitch(value: true, onChanged: (_) {}),
                const SizedBox(width: 24),
                const LenzCheck(value: false),
                const SizedBox(width: 12),
                const LenzCheck(value: true),
              ],
            ),
            const SizedBox(height: 16),
            const Center(child: LenzToast(message: 'Saved to favorites')),
            const SizedBox(height: 16),
            LenzSettingGroup(
              children: [
                LenzSettingRow(
                  icon: LenzIcons.trash,
                  title: 'Delete account',
                  destructive: true,
                  onTap: () {},
                ),
              ],
            ),
            LenzButton(
              label: 'Loading',
              loading: true,
              onPressed: () {},
            ),
          ],
        ),
      ),
      before: () async {
        node.requestFocus();
      },
    );
  });

  testWidgets('dark frame', skip: _dir == null, (tester) async {
    await _dump(
      tester,
      'dark',
      _screen(
        bg: LenzColors.camera,
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            LenzTopBar(
              title: 'Analyzing',
              dark: true,
              right: const SizedBox(width: 44),
            ),
            LenzJourneyStepper(
              step: 3,
              dark: true,
              rider: const SizedBox(width: 56, height: 56, child: ColoredBox(color: LenzColors.leaf)),
            ),
            Row(
              children: [
                LenzIconButton(icon: LenzIcons.x, dark: true, onTap: () {}),
                const SizedBox(width: 12),
                LenzIconButton(icon: LenzIcons.bolt, dark: true, iconSize: 21, onTap: () {}),
              ],
            ),
          ],
        ),
      ),
    );
  });
}
