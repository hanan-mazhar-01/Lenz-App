import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import '../../core/theme/lenz_text.dart';
import '../../services/haptics.dart';
import '../ui/lenz_animated_value.dart';
import '../ui/lenz_icons.dart';
import '../ui/lenz_pressable.dart';

/// The docked "notch bar" (mock-up variation B): a white bar with 30px rounded
/// top corners and a round cradle cut out for the raised green scan button, and
/// always-visible labels.
/// The scan button has no caption of its own.
///
/// Tabs are indexed `0..3` = Home, History, Favorites ("Saved"), Profile.
/// Place it at the bottom of a screen-filling [Stack]; the widget adds the
/// bottom safe area itself.
///
/// ```dart
/// Stack(children: [
///   page,
///   Positioned(left: 0, right: 0, bottom: 0,
///     child: LenzTabBar(
///       currentIndex: index,
///       hidden: !showBar,
///       onTab: (i) => setState(() => index = i),
///       onScan: openCamera,
///     )),
/// ])
/// ```
class LenzTabBar extends StatelessWidget {
  const LenzTabBar({
    super.key,
    required this.currentIndex,
    required this.onTab,
    required this.onScan,
    this.hidden = false,
  });

  /// Selected tab 0..3, or -1 for none (e.g. while on a sub screen).
  final int currentIndex;

  /// Called with 0..3 (Home, History, Favorites, Profile); also called when
  /// the active tab is tapped again (e.g. to scroll to top).
  final ValueChanged<int> onTab;
  final VoidCallback onScan;

  /// Slides the bar away (`translateY(130)` + fade, 500ms).
  final bool hidden;

  /// Height of the white bar above the safe area.
  static const double barHeight = 82;

  /// The bar is docked to the screen edges.
  static const double margin = 0;

  /// Extra room above the bar taken by the raised scan button.
  static const double _fabRoom = 30;

  /// Width reserved for the scan button's cradle.
  static const double _cradle = 104;

  /// Bottom space a scrollable page should reserve so content is not hidden
  /// behind the bar.
  static double contentPadding(BuildContext context) => 118 + MediaQuery.paddingOf(context).bottom;

  static const _tabs = <(String, String)>[
    (LenzIcons.home, 'Home'),
    (LenzIcons.clock, 'History'),
    (LenzIcons.heart, 'Saved'),
    (LenzIcons.user, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return LenzAnimatedDouble(
      value: hidden ? 150 : 0,
      duration: LenzMotion.tabBarToggle,
      curve: LenzMotion.ease,
      builder: (context, dy) => AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        curve: Curves.ease,
        opacity: hidden ? 0 : 1,
        child: Transform.translate(
          offset: Offset(0, dy),
          child: IgnorePointer(
            ignoring: hidden,
            child: ExcludeSemantics(
              excluding: hidden,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.15,
                child: SizedBox(
                  height: barHeight + _fabRoom + safeBottom,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      const pad = 6.0;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: barHeight + safeBottom,
                            child: CustomPaint(
                              painter: const _NotchBarPainter(),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(pad, 0, pad, 16 + safeBottom),
                                child: Row(
                                  children: [
                                    for (var i = 0; i < 2; i++) _tab(i),
                                    const SizedBox(width: _cradle),
                                    for (var i = 2; i < 4; i++) _tab(i),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // raised scan button sitting in the cradle
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 2,
                            child: Center(
                              child: _Fab(
                                onTap: () {
                                  Haptics.mediumImpact();
                                  onScan();
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(int i) => Expanded(
    child: _TabItem(
      icon: _tabs[i].$1,
      label: _tabs[i].$2,
      active: currentIndex == i,
      onTap: () {
        Haptics.selectionClick();
        onTab(i);
      },
    ),
  );
}

/// The white bar: rounded top corners with a circular cradle cut at the top
/// centre (radius 43, centre 6px below the top edge) and a soft upward shadow.
class _NotchBarPainter extends CustomPainter {
  const _NotchBarPainter();

  static const double _notchRadius = 43;
  static const double _notchCenterY = 6;

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(LenzRadii.tabBar);
    final bar = Path()
      ..addRRect(RRect.fromRectAndCorners(Offset.zero & size, topLeft: r, topRight: r));
    final notch = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(size.width / 2, _notchCenterY), radius: _notchRadius),
      );
    final path = Path.combine(PathOperation.difference, bar, notch);
    canvas.drawPath(
      path.shift(const Offset(0, -10)),
      Paint()
        ..color = const Color.fromRGBO(18, 47, 36, .13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_NotchBarPainter old) => false;
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: LenzMotion.tabPop,
    value: widget.active ? 1 : 0,
  );

  @override
  void didUpdateWidget(_TabItem old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      if (LenzMotion.reduced(context)) {
        _pop.value = 1;
      } else {
        _pop.forward(from: 0);
      }
    } else if (!widget.active && old.active) {
      _pop.value = 0;
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final color = active ? LenzColors.forest : LenzColors.subtle;
    final reduced = LenzMotion.reduced(context);

    return Semantics(
      button: true,
      selected: active,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            LenzAnimatedDouble(
              value: active ? 1 : 0,
              duration: LenzMotion.tabIcon,
              curve: reduced ? Curves.easeOut : LenzMotion.spring,
              builder: (context, v) => Transform.translate(
                offset: Offset(0, -2 * v),
                child: Transform.scale(
                  scale: 1 + .06 * v,
                  child: SizedBox(
                    width: 52,
                    height: 32,
                    child: Center(
                      child: TweenAnimationBuilder<Color?>(
                        tween: ColorTween(end: active ? LenzColors.forest2 : color),
                        duration: const Duration(milliseconds: 250),
                        builder: (context, c, _) =>
                            LenzIcon(widget.icon, size: 24, color: c ?? color),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: LenzText.tab.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w800,
                ),
                child: Text(widget.label, maxLines: 1),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _Fab extends StatelessWidget {
  const _Fab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Scan',
      excludeSemantics: true,
      onTap: onTap,
      child: LenzPressable(
        onTap: onTap,
        pressedScale: .9,
        duration: const Duration(milliseconds: 300),
        haptic: false,
        isButton: false,
        child: const SizedBox(
          width: 68,
          height: 68,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment(-.5, -1),
                end: Alignment(.5, 1),
                colors: [Color(0xFF3FBF68), Color(0xFF1F8A4C), Color(0xFF146A39)],
                stops: [0, .55, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color.fromRGBO(31, 138, 76, .8),
                  offset: Offset(0, 14),
                  blurRadius: 26,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: Center(
              child: LenzIcon(LenzIcons.camera, size: 28, strokeWidth: 2.2, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
