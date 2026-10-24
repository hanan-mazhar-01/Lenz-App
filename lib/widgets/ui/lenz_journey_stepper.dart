import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import '../../core/theme/lenz_text.dart';
import 'lenz_animated_value.dart';

/// The scan journey's 5-step progress track (prototype `journey()`): a track
/// with gradient fill, dots, a label row, and Lenz's head riding the line.
///
/// [rider] is the content of the 44px circle (white border, mint background):
/// pass the character's `peek` view; it receives a 56px wide box that is
/// offset (-6, -6) inside the circle, exactly like the prototype. The fill
/// grows in 900ms (ease) and the rider springs along the line in 900ms,
/// both starting 250ms after the first build.
class LenzJourneyStepper extends StatelessWidget {
  const LenzJourneyStepper({
    super.key,
    required this.step,
    this.rider,
    this.dark = false,
    this.labels = defaultLabels,
    this.bottomMargin = 14,
  });

  static const List<String> defaultLabels = [
    'Photo',
    'Identify',
    'Evidence',
    'Analyze',
    'Result',
  ];

  /// Current step, 0-based (Photo = 0 ... Result = 4).
  final int step;
  final Widget? rider;
  final bool dark;
  final List<String> labels;

  /// Space under the label row (prototype: 14).
  final double bottomMargin;

  @override
  Widget build(BuildContext context) {
    assert(labels.length >= 2, 'A journey needs at least two steps');
    final n = labels.length;
    final activeLabel = dark ? Colors.white : LenzColors.forest;
    final idleLabel = dark ? LenzColors.onDarkMuted : LenzColors.muted;
    final spring =
        LenzMotion.reduced(context) ? Curves.easeOut : LenzMotion.spring;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox(
            height: 44,
            child: LayoutBuilder(
              builder: (context, c) {
                final inner = (c.maxWidth - 28).clamp(0.0, double.infinity);
                final target = step.clamp(0, n - 1) / (n - 1);
                return LenzAnimatedDouble(
                  value: target,
                  initialValue: 0,
                  duration: LenzMotion.journey,
                  delay: LenzMotion.journeyDelay,
                  curve: LenzMotion.ease,
                  builder: (context, fill) => LenzAnimatedDouble(
                    value: target,
                    initialValue: 0,
                    duration: LenzMotion.journey,
                    delay: LenzMotion.journeyDelay,
                    curve: spring,
                    builder: (context, ride) => _track(
                      inner: inner,
                      fill: fill,
                      ride: ride,
                      n: n,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < n; i++)
                Text(
                  labels[i],
                  maxLines: 1,
                  softWrap: false,
                  style: LenzText.journeyLabel.copyWith(
                    color: i == step ? activeLabel : idleLabel,
                    fontWeight: i == step ? FontWeight.w900 : FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: bottomMargin),
      ],
    );
  }

  Widget _track({
    required double inner,
    required double fill,
    required double ride,
    required int n,
  }) {
    final riderBorder = dark ? const Color(0xFF0F1C16) : Colors.white;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // track
        Positioned(
          left: 14,
          right: 14,
          top: 21,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark
                  ? const Color.fromRGBO(255, 255, 255, .2)
                  : LenzColors.trackTint,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        // fill
        Positioned(
          left: 14,
          top: 21,
          height: 4,
          width: (inner * fill).clamp(0.0, inner),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LenzGradients.journeyFill,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        // dots
        for (var i = 0; i < n; i++)
          Positioned(
            left: 14 + inner * (i / (n - 1)) - 10,
            top: 13,
            width: 20,
            height: 20,
            child: _Dot(done: i < step && !dark, dark: dark),
          ),
        // rider
        Positioned(
          left: 14 + inner * ride - 22,
          top: 0,
          width: 44,
          height: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LenzColors.mint,
              border: Border.all(color: riderBorder, width: 3),
              boxShadow: LenzShadows.rider,
            ),
            // 3px border -> 38px content circle, like the CSS padding box.
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: ClipOval(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (rider != null)
                      Positioned(
                        left: -6,
                        top: -6,
                        width: 56,
                        child: rider!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.done, required this.dark});
  final bool done;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final bg = done
        ? LenzColors.leaf
        : dark
            ? const Color(0xFF0F1C16)
            : LenzColors.paper;
    final border = done
        ? LenzColors.leaf
        : dark
            ? const Color.fromRGBO(255, 255, 255, .25)
            : LenzColors.dotBorder;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: LenzMotion.ease,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: border, width: 3),
      ),
    );
  }
}
