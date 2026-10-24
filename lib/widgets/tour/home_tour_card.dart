import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../services/haptics.dart';
import '../lenz/lenz.dart';
import '../ui/ui.dart';

/// Spotlight look shared by every Home-tour step (prototype `.tour`):
/// dim overlay `rgba(10,22,16,.68)`.
abstract final class HomeTourStyle {
  static const Color overlayColor = Color(0xFF0A1610);
  static const double overlayOpacity = .68;
  static const double holeRadius = 26;
  static const EdgeInsets holePadding = EdgeInsets.all(6);
}

/// The tooltip content shown by each step of the Home-screen coach-mark
/// tour, styled like the prototype's `.tcard`: white r26 card with Lenz
/// peeking on the left, title + description, "n of N" and Skip / Next chips.
/// Pops in with a spring on every step.
class HomeTourCard extends StatelessWidget {
  final String title;
  final String description;
  final int stepIndex; // 0-based
  final int totalSteps;

  /// Lenz's expression for this step (defaults to a per-step mood).
  final LenzMood? mood;

  const HomeTourCard({
    super.key,
    required this.title,
    required this.description,
    required this.stepIndex,
    required this.totalSteps,
    this.mood,
  });

  bool get _isLastStep => stepIndex == totalSteps - 1;

  static const _stepMoods = [
    LenzMood.hello,
    LenzMood.inspect,
    LenzMood.pleased,
    LenzMood.happy,
    LenzMood.joy,
  ];

  LenzMood get _mood => mood ?? _stepMoods[stepIndex.clamp(0, _stepMoods.length - 1)];

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final width = (screenW - 36).clamp(240.0, 420.0);
    final reduce = LenzMotion.reduced(context);
    final card = Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LenzColors.paper,
        borderRadius: BorderRadius.circular(26),
        boxShadow: LenzShadows.sh2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SizedBox(
              width: screenW < 360 ? 60 : 74,
              child: LenzCharacter(
                mood: _mood,
                view: LenzView.peek,
                fx: false,
                interactive: false,
                wake: false,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: LenzText.item.copyWith(fontSize: 16.5)),
                const SizedBox(height: 2),
                Text(description, style: LenzText.sub.copyWith(fontSize: 13)),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _StepDots(index: stepIndex, total: totalSteps),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TourChip(
                      label: 'Skip',
                      semantic: 'Skip tour',
                      onTap: () {
                        Haptics.lightImpact();
                        ShowcaseView.get().dismiss();
                      },
                    ),
                    const SizedBox(width: 8),
                    _TourChip(
                      label: _isLastStep ? 'Done' : 'Next',
                      on: true,
                      onTap: () => ShowcaseView.get().next(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (reduce) return card;
    // `.tcard` animation: pop .5s spring (scale .6 -> 1.06 -> 1, fade in).
    return TweenAnimationBuilder<double>(
      key: ValueKey(stepIndex),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      builder: (context, t, child) => Opacity(
        opacity: LenzPopCurve.opacity(t),
        child: Transform.scale(scale: LenzPopCurve.scale(t), child: child),
      ),
      child: card,
    );
  }
}

/// "1 of 5" caption plus step dots.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.index, required this.total});
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${index + 1} of $total',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${index + 1} of $total',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: LenzText.cap,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < total; i++)
                  AnimatedContainer(
                    duration: LenzMotion.chip,
                    curve: LenzMotion.ease,
                    margin: const EdgeInsets.only(right: 4),
                    width: i == index ? 12 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: i == index ? LenzColors.forest : LenzColors.dotBorder,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 32px tall `.chip` used for Skip / Next.
class _TourChip extends StatelessWidget {
  const _TourChip({required this.label, required this.onTap, this.on = false, this.semantic});
  final String label;
  final VoidCallback onTap;
  final bool on;
  final String? semantic;

  @override
  Widget build(BuildContext context) {
    return LenzPressable(
      onTap: onTap,
      pressedScale: .94,
      semanticLabel: semantic ?? label,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? LenzColors.forest : LenzColors.paper,
          borderRadius: BorderRadius.circular(LenzRadii.pill),
          border: Border.all(color: on ? const Color(0x00000000) : LenzColors.line),
        ),
        child: Text(
          label,
          style: LenzText.chip.copyWith(color: on ? LenzColors.paper : LenzColors.ink),
        ),
      ),
    );
  }
}

/// The prototype's spotlight border (`.tour .hole`: 2px white @ 80%) drawn
/// around a tour target while its step is showing. The hole itself is cut
/// by showcaseview; this paints the ring just inside its edge.
class HomeTourRing extends StatelessWidget {
  const HomeTourRing({
    super.key,
    required this.target,
    required this.active,
    required this.child,
    this.radius = HomeTourStyle.holeRadius,
    this.outset = HomeTourStyle.holePadding,
    this.circle = false,
  });

  final GlobalKey target;
  final ValueListenable<GlobalKey?>? active;
  final Widget child;
  final double radius;

  /// How far the ring sits outside the child (negative = inside); match the
  /// showcase's `targetPadding`.
  final EdgeInsets outset;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final listenable = active;
    if (listenable == null) return child;
    return ValueListenableBuilder<GlobalKey?>(
      valueListenable: listenable,
      child: child,
      builder: (context, key, child) => Stack(
        clipBehavior: Clip.none,
        children: [
          child!,
          if (key == target)
            Positioned(
              left: -outset.left,
              top: -outset.top,
              right: -outset.right,
              bottom: -outset.bottom,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: circle ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: circle ? null : BorderRadius.circular(radius),
                    border: Border.all(color: const Color(0xCCFFFFFF), width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
