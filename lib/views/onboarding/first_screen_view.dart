import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/haptics.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// One onboarding page (prototype `OB`).
class _ObPage {
  const _ObPage({
    required this.mood,
    required this.moodColor,
    required this.bubble,
    required this.title,
    required this.text,
    required this.features,
  });

  final LenzMood mood;
  final Color moodColor;
  final String bubble;
  final String title;
  final String text;
  final List<(String, String)> features;
}

const List<_ObPage> _pages = [
  _ObPage(
    mood: LenzMood.hello,
    moodColor: Color(0xFFD9ECDF),
    bubble: "Hi, I'm Lenz!",
    title: 'Meet Lenz, your pocket detective',
    text: 'Snap a few photos and I study the stitching, hardware and details that luxury fakes get wrong.',
    features: [
      (LenzIcons.camera, 'Guided photos'),
      (LenzIcons.layers, 'Point by point'),
      (LenzIcons.bolt, 'About 30 seconds'),
    ],
  ),
  _ObPage(
    mood: LenzMood.inspect,
    moodColor: Color(0xFFD9E4F6),
    bubble: 'Let me take a closer look…',
    title: 'I tell you exactly what to capture',
    text: 'Every angle comes with a framing guide, and I check each photo before we move on.',
    features: [
      (LenzIcons.scan, 'Framing guides'),
      (LenzIcons.shieldOk, 'Quality checks'),
      (LenzIcons.image, 'Gallery uploads'),
    ],
  ),
  _ObPage(
    mood: LenzMood.happy,
    moodColor: Color(0xFFCFEED6),
    bubble: 'Ready when you are!',
    title: 'A verdict in plain language',
    text: 'You get an AI-assisted opinion with a breakdown. It is advice, not an official brand certificate.',
    features: [
      (LenzIcons.sparkles, 'Clear verdict'),
      (LenzIcons.heart, 'Saved reports'),
      (LenzIcons.lock, 'Private by default'),
    ],
  ),
];

/// Onboarding carousel (prototype `SCREENS.onboard`): three swipeable pages
/// with Lenz changing mood (hello / inspect / happy), a typewriter bubble per
/// page, feature pills, page dots with a growing active pill + "1 of 3",
/// Next / Get started, "I already have an account" and Skip.
///
/// [onGetStarted] fires from the last page's "Get started"; [onSkip] from
/// "Skip" and "I already have an account".
class FirstScreenView extends StatefulWidget {
  final VoidCallback? onGetStarted;
  final VoidCallback? onSkip;
  final VoidCallback? onBack;

  /// Initial page (0..2), for previews/tests.
  final int initialPage;

  const FirstScreenView({
    super.key,
    this.onGetStarted,
    this.onSkip,
    this.onBack,
    this.initialPage = 0,
  });

  @override
  State<FirstScreenView> createState() => _FirstScreenViewState();
}

class _FirstScreenViewState extends State<FirstScreenView>
    with TickerProviderStateMixin {
  final LenzController _lenz = LenzController();
  late int _index = widget.initialPage.clamp(0, _pages.length - 1);
  late int _shown = _index;
  int _dir = 1;
  double _dragDx = 0;

  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  @override
  void dispose() {
    _out.dispose();
    _in.dispose();
    super.dispose();
  }

  void _setPage(int n, int dir) {
    if (n == _index || n < 0 || n >= _pages.length) return;
    Haptics.selectionClick();
    setState(() {
      _index = n;
      _dir = dir;
    });
    _lenz.hop();
    if (LenzMotion.reduced(context)) {
      setState(() => _shown = n);
      return;
    }
    _in.stop();
    _out.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() => _shown = _index);
      _out.value = 0;
      _in.forward(from: 0);
    });
  }

  void _next() {
    if (_index < _pages.length - 1) {
      _setPage(_index + 1, 1);
    } else {
      widget.onGetStarted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_index];
    final mq = MediaQuery.of(context);
    final topInset = mq.padding.top;

    return Material(
      color: LenzColors.ivory,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LenzBlob(color: page.moodColor, height: 560),
          Column(
            children: [
              // Hero: Lenz + bubble, swipeable.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) => _dragDx = 0,
                  onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
                  onHorizontalDragEnd: (_) {
                    if (_dragDx.abs() > 50) {
                      if (_dragDx < 0) {
                        _setPage(_index + 1, 1);
                      } else {
                        _setPage(_index - 1, -1);
                      }
                    }
                    _dragDx = 0;
                  },
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: math.max(64.0, topInset + 20),
                    ),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final w = math.min(
                          266.0,
                          math.max(0.0, c.maxHeight - 8) *
                              LenzView.full.aspectRatio,
                        );
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Align(
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: w,
                                child: LenzCharacter(
                                  mood: page.mood,
                                  view: LenzView.full,
                                  shadow: true,
                                  controller: _lenz,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 22,
                              top: 26,
                              child: LenzBubble(
                                key: ValueKey('ob-bubble-$_index'),
                                text: page.bubble,
                                maxWidth: 190,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                // Keep at least ~38% of the height for Lenz on small phones /
                // large text; the copy scrolls inside the panel instead.
                constraints: BoxConstraints(maxHeight: mq.size.height * 0.62),
                child: _buildPanel(context, mq.padding.bottom),
              ),
            ],
          ),
          // Skip chip.
          Positioned(
            top: math.max(56.0, topInset + 12),
            right: 20,
            child: LenzChip(label: 'Skip', onTap: widget.onSkip),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context, double bottomInset) {
    final shown = _pages[_shown];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 22, 24, 22 + bottomInset),
      decoration: const BoxDecoration(
        color: LenzColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(18, 47, 36, .28),
            offset: Offset(0, -24),
            blurRadius: 60,
            spreadRadius: -20,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: AnimatedBuilder(
                animation: Listenable.merge([_out, _in]),
                builder: (context, child) {
                  final outV = _out.value;
                  final inV = LenzMotion.ease.transform(_in.value);
                  final double opacity;
                  final double dx;
                  if (outV > 0) {
                    opacity = 1 - outV;
                    dx = -30.0 * _dir * outV;
                  } else {
                    opacity = inV;
                    dx = 30.0 * _dir * (1 - inV);
                  }
                  return Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(dx, 0),
                      child: child,
                    ),
                  );
                },
                child: _PageText(key: ValueKey(_shown), page: shown),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var k = 0; k < _pages.length; k++) ...[
                if (k > 0) const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: LenzMotion.spring,
                  height: 8,
                  width: k == _index ? 26 : 8,
                  decoration: BoxDecoration(
                    color: k == _index
                        ? LenzColors.forest
                        : const Color.fromRGBO(18, 47, 36, .18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
              const Spacer(),
              Text('${_index + 1} of ${_pages.length}', style: LenzText.tiny),
            ],
          ),
          const SizedBox(height: 14),
          LenzButton(
            label: _index == _pages.length - 1 ? 'Get started' : 'Next',
            pulse: true,
            onPressed: _next,
          ),
          const SizedBox(height: 6),
          LenzPressable(
            onTap: widget.onSkip,
            child: SizedBox(
              height: 40,
              child: Center(
                child: Text(
                  'I already have an account',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LenzText.buttonSm.copyWith(color: LenzColors.muted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageText extends StatelessWidget {
  const _PageText({super.key, required this.page});

  final _ObPage page;

  @override
  Widget build(BuildContext context) {
    // Slightly smaller headline on iPhone SE-class widths.
    final ts = MediaQuery.sizeOf(context).width < 360 ? 24.0 : 27.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          page.title,
          style: LenzText.display.copyWith(
            fontSize: ts,
            letterSpacing: -.035 * ts,
          ),
        ),
        const SizedBox(height: 8),
        Text(page.text, style: LenzText.sub.copyWith(fontSize: 14)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in page.features)
              _FeaturePill(icon: f.$1, label: f.$2),
          ],
        ),
      ],
    );
  }
}

/// `.pill.mint` at h32 / 12px padding / 12.5 type with a 15px icon.
class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: LenzColors.mint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LenzIcon(icon, size: 15, strokeWidth: 2.3, color: LenzColors.forest),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: LenzText.pill.copyWith(
                fontSize: 12.5,
                color: LenzColors.forest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
