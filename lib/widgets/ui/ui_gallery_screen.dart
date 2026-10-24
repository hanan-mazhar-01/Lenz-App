import 'package:flutter/material.dart';

import '../../models/authentication_result.dart';
import 'ui.dart';

/// Debug screen that shows every Lenz UI-kit component in all its states.
/// Not wired to any route; push it manually while developing:
///
/// ```dart
/// Navigator.push(context, MaterialPageRoute(builder: (_) => const UiGalleryScreen()));
/// ```
class UiGalleryScreen extends StatefulWidget {
  const UiGalleryScreen({super.key});

  @override
  State<UiGalleryScreen> createState() => _UiGalleryScreenState();
}

class _UiGalleryScreenState extends State<UiGalleryScreen> {
  int _seg = 0;
  bool _switch = true;
  bool _check = true;
  int _step = 1;
  int _tab = 0;
  bool _barHidden = false;
  int _replay = 0;
  final Set<int> _chips = {0};
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Widget _h(String t) => LenzSectionHeader(t);

  Widget _riderPlaceholder() => const SizedBox(
        width: 56,
        height: 56,
        child: ColoredBox(color: LenzColors.leaf),
      );

  void _pushDemo(LenzPageRoute<void> Function(Widget) make) {
    Navigator.of(context).push(make(const _DemoPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LenzBlob(),
          ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.paddingOf(context).top + 14,
              20,
              LenzTabBar.contentPadding(context),
            ),
            children: [
              LenzTopBar(title: 'Lenz UI kit', actions: [
                LenzIconButton(
                  icon: LenzIcons.refresh,
                  semanticLabel: 'Replay animations',
                  onTap: () => setState(() => _replay++),
                ),
              ]),
              KeyedSubtree(
                key: ValueKey(_replay),
                child: LenzStagger(
                  spacing: 0,
                  children: [
                    _h('Colours'),
                    _colors(),
                    _h('Type scale'),
                    _types(),
                    _h('Buttons'),
                    _buttons(),
                    _h('Icon buttons, chips, pills'),
                    _smallThings(),
                    _h('Cards, section header, divider'),
                    _cards(),
                    _h('Fields'),
                    _fields(),
                    _h('Segmented, switch, check'),
                    _controls(),
                    _h('Settings group'),
                    _settings(),
                    _h('Ring, meter, count-up'),
                    _progress(),
                    _h('Journey stepper'),
                    _journey(),
                    _h('Sheets, toast, routes'),
                    _overlays(),
                    _h('Icons'),
                    _icons(),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LenzTabBar(
              currentIndex: _tab,
              hidden: _barHidden,
              onTab: (i) => setState(() => _tab = i),
              onScan: () => showLenzToast(context, 'Scan pressed'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colors() {
    const swatches = <(String, Color)>[
      ('ivory', LenzColors.ivory),
      ('paper', LenzColors.paper),
      ('ink', LenzColors.ink),
      ('forest', LenzColors.forest),
      ('forest2', LenzColors.forest2),
      ('mint', LenzColors.mint),
      ('mint2', LenzColors.mint2),
      ('leaf', LenzColors.leaf),
      ('gold', LenzColors.gold),
      ('gold2', LenzColors.gold2),
      ('muted', LenzColors.muted),
      ('ok', LenzColors.ok),
      ('okSoft', LenzColors.okSoft),
      ('bad', LenzColors.bad),
      ('badSoft', LenzColors.badSoft),
      ('warn', LenzColors.warn),
      ('warnSoft', LenzColors.warnSoft),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (n, c) in swatches)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 40,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: LenzColors.line),
                ),
              ),
              const SizedBox(height: 4),
              Text(n, style: LenzText.tiny),
            ],
          ),
      ],
    );
  }

  Widget _types() {
    return LenzCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Display 32', style: LenzText.display),
          const SizedBox(height: 6),
          const Text('Title 22', style: LenzText.title),
          const SizedBox(height: 6),
          const Text('Section 19', style: LenzText.section),
          const SizedBox(height: 6),
          const Text('Sub 14.5 muted text that can wrap onto lines.',
              style: LenzText.sub),
          const SizedBox(height: 6),
          const Text('Cap 12.5', style: LenzText.cap),
          const Text('Tiny 11.5', style: LenzText.tiny),
        ],
      ),
    );
  }

  Widget _buttons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LenzButton(label: 'Primary', icon: LenzIcons.camera, onPressed: () {}),
        const SizedBox(height: 10),
        LenzButton(
          label: 'Analyze now (3 of 5)',
          icon: LenzIcons.sparkles,
          pulse: true,
          onPressed: () {},
        ),
        const SizedBox(height: 10),
        LenzButton(
          label: 'Ghost',
          variant: LenzButtonVariant.ghost,
          onPressed: () {},
        ),
        const SizedBox(height: 10),
        LenzButton(
          label: 'Soft',
          variant: LenzButtonVariant.soft,
          onPressed: () {},
        ),
        const SizedBox(height: 10),
        LenzButton(
          label: 'Upgrade to Lenz Pro',
          variant: LenzButtonVariant.gold,
          icon: LenzIcons.crown,
          onPressed: () {},
        ),
        const SizedBox(height: 10),
        LenzButton(
          label: 'Delete account',
          variant: LenzButtonVariant.danger,
          onPressed: () {},
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: LenzButton(
                label: 'Small',
                size: LenzButtonSize.sm,
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LenzButton(
                label: 'Small ghost',
                size: LenzButtonSize.sm,
                variant: LenzButtonVariant.ghost,
                onPressed: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
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
          ],
        ),
        const SizedBox(height: 10),
        const LenzButton(label: 'Loading', loading: true, onPressed: _noop),
        const SizedBox(height: 10),
        const LenzButton(label: 'Disabled', onPressed: null),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LenzGradients.hero,
            borderRadius: BorderRadius.circular(LenzRadii.hero),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: LenzButton(
                label: 'Scan an item',
                icon: LenzIcons.camera,
                variant: LenzButtonVariant.light,
                expand: false,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallThings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            LenzIconButton(icon: LenzIcons.chevL, onTap: () {}),
            const SizedBox(width: 8),
            LenzIconButton(icon: LenzIcons.help, iconSize: 21, onTap: () {}),
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: LenzColors.camera,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LenzIconButton(icon: LenzIcons.x, dark: true, onTap: () {}),
                    const SizedBox(width: 8),
                    LenzIconButton(
                      icon: LenzIcons.bolt,
                      dark: true,
                      iconSize: 21,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 3; i++)
              LenzChip(
                label: ['Guided photos', 'Point by point', 'About 30 seconds'][i],
                icon: [LenzIcons.camera, LenzIcons.layers, LenzIcons.bolt][i],
                selected: _chips.contains(i),
                onTap: () => setState(() {
                  _chips.contains(i) ? _chips.remove(i) : _chips.add(i);
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            LenzPill.verdict(Verdict.likelyAuthentic),
            LenzPill.verdict(Verdict.likelyReplica),
            LenzPill.verdict(Verdict.inconclusive),
            const LenzPill(label: 'Free plan', icon: LenzIcons.sparkles),
            const LenzPill(
              label: 'PRO',
              variant: LenzPillVariant.gold,
              icon: LenzIcons.crown,
            ),
            const LenzPill(label: 'Done', variant: LenzPillVariant.auth),
          ],
        ),
      ],
    );
  }

  Widget _cards() {
    return Column(
      children: [
        LenzCard(
          onTap: () {},
          child: const Row(
            children: [
              Expanded(child: Text('Tap me (press scale .97)', style: LenzText.item)),
              LenzIcon(LenzIcons.chevR, size: 18),
            ],
          ),
        ),
        const LenzSectionHeader('Your recent checks', actionLabel: 'See all'),
        const LenzDivider(label: 'or continue with'),
        const SizedBox(height: 8),
        const LenzDivider(),
      ],
    );
  }

  Widget _fields() {
    return Column(
      children: [
        LenzField(
          controller: _email,
          hint: 'Email address',
          icon: LenzIcons.mail,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        const LenzField(hint: 'Password', icon: LenzIcons.lock, obscure: true),
        const SizedBox(height: 12),
        const LenzField(
          hint: 'Email address',
          icon: LenzIcons.mail,
          errorText: 'Enter a valid email address',
        ),
      ],
    );
  }

  Widget _controls() {
    return Column(
      children: [
        LenzSegmented(
          labels: const ['Sign in', 'Create account'],
          index: _seg,
          onChanged: (i) => setState(() => _seg = i),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            LenzSwitch(value: _switch, onChanged: (v) => setState(() => _switch = v)),
            const SizedBox(width: 20),
            LenzCheck(value: _check, onChanged: (v) => setState(() => _check = v)),
          ],
        ),
      ],
    );
  }

  Widget _settings() {
    return LenzSettingGroup(
      children: [
        LenzSettingRow(
          icon: LenzIcons.clock,
          title: 'Scan history',
          subtitle: 'View your past scans',
          onTap: () {},
        ),
        LenzSettingRow(
          icon: LenzIcons.face,
          title: 'Face ID lock',
          subtitle: 'Unlock reports with biometrics',
          trailing: LenzSwitch(value: _switch, onChanged: (v) => setState(() => _switch = v)),
        ),
        LenzSettingRow(
          icon: LenzIcons.logout,
          title: 'Log out',
          destructive: true,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _progress() {
    return LenzCard(
      child: Column(
        children: [
          Row(
            children: [
              const LenzRing(
                value: .94,
                size: 92,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedCount(
                      to: 94,
                      suffix: '%',
                      style: TextStyle(
                        fontFamily: LenzText.family,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: LenzColors.ink,
                      ),
                    ),
                    Text('strength', style: LenzText.tiny),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              LenzRing(
                value: .38,
                size: 56,
                strokeWidth: 7,
                color: LenzColors.warn,
                child: const AnimatedCount(to: 38, style: LenzText.item),
              ),
              const SizedBox(width: 10),
              const LenzRing(
                value: .6,
                size: 56,
                strokeWidth: 7,
                color: LenzColors.bad,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const LenzMeter(value: .92),
          const SizedBox(height: 10),
          const LenzMeter.warn(value: .38),
        ],
      ),
    );
  }

  Widget _journey() {
    return Column(
      children: [
        LenzJourneyStepper(step: _step, rider: _riderPlaceholder()),
        DecoratedBox(
          decoration: BoxDecoration(
            color: LenzColors.camera,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
            child: LenzJourneyStepper(
              step: _step,
              dark: true,
              rider: _riderPlaceholder(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: LenzButton(
                label: 'Back',
                size: LenzButtonSize.sm,
                variant: LenzButtonVariant.ghost,
                onPressed: () => setState(() => _step = (_step - 1).clamp(0, 4)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LenzButton(
                label: 'Next step',
                size: LenzButtonSize.sm,
                onPressed: () => setState(() => _step = (_step + 1).clamp(0, 4)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _overlays() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LenzButton(
          label: 'Open sheet',
          size: LenzButtonSize.sm,
          variant: LenzButtonVariant.soft,
          onPressed: () => showLenzSheet<void>(
            context,
            builder: (context) => Column(
              children: [
                const SizedBox(height: 8),
                const Text('Reset your password',
                    style: LenzText.title, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                const Text('We will email you a reset link.',
                    style: LenzText.sub),
                const SizedBox(height: 14),
                const LenzField(hint: 'Email address', icon: LenzIcons.mail),
                const SizedBox(height: 14),
                LenzButton(
                  label: 'Send reset link',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        LenzButton(
          label: 'Confirm sheet (danger)',
          size: LenzButtonSize.sm,
          variant: LenzButtonVariant.soft,
          onPressed: () => showLenzConfirm(
            context,
            title: 'Delete your account?',
            text: 'This permanently removes your data and cannot be undone.',
            okLabel: 'Delete account',
            danger: true,
            character: (_) => const SizedBox(
              height: 140,
              child: Center(child: Text('Lenz character slot', style: LenzText.cap)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        LenzButton(
          label: 'Toast',
          size: LenzButtonSize.sm,
          variant: LenzButtonVariant.soft,
          onPressed: () => showLenzToast(context, 'Saved to favorites'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (label, make) in <(String, LenzPageRoute<void> Function(Widget))>[
              ('Forward', LenzRoutes.forward<void>),
              ('Modal up', LenzRoutes.modalUp<void>),
              ('Zoom', LenzRoutes.zoom<void>),
              ('Fade', LenzRoutes.fade<void>),
            ]) ...[
              Expanded(
                child: LenzButton(
                  label: label,
                  size: LenzButtonSize.sm,
                  variant: LenzButtonVariant.ghost,
                  onPressed: () => _pushDemo(make),
                ),
              ),
              if (label != 'Fade') const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 8),
        LenzButton(
          label: _barHidden ? 'Show tab bar' : 'Hide tab bar',
          size: LenzButtonSize.sm,
          variant: LenzButtonVariant.soft,
          onPressed: () => setState(() => _barHidden = !_barHidden),
        ),
      ],
    );
  }

  Widget _icons() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final n in LenzIcons.all)
          SizedBox(
            width: 62,
            child: Column(
              children: [
                LenzIcon(n, size: 26),
                const SizedBox(height: 4),
                Text(n,
                    style: LenzText.tiny.copyWith(fontSize: 9.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
      ],
    );
  }
}

void _noop() {}

class _DemoPage extends StatelessWidget {
  const _DemoPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const LenzTopBar(title: 'Demo page'),
              const Spacer(),
              const Text('Swipe from the left edge (iOS) or press back',
                  style: LenzText.sub, textAlign: TextAlign.center),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
