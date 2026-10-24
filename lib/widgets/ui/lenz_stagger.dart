import 'package:flutter/material.dart';

import '../../core/theme/lenz_motion.dart';

/// Marks a subtree whose entrance is already animated by something else (a
/// page / layer / tab transition), so inner [LenzRise] entrances do not play a
/// second animation on top of it.
///
/// * [animation]: the entrance transition; while it has not completed, rises
///   mounted underneath are skipped (they appear with the transition).
/// * [always]: for screens that live permanently inside a host (e.g. tabs in an
///   IndexedStack) and are revealed by the host's own transition.
class LenzEntranceScope extends InheritedWidget {
  const LenzEntranceScope({super.key, this.animation, this.always = false, required super.child});

  final Animation<double>? animation;
  final bool always;

  /// True when an enclosing transition already animates this subtree's entrance.
  static bool covers(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<LenzEntranceScope>();
    if (scope == null) return false;
    if (scope.always) return true;
    final a = scope.animation;
    return a != null && a.status != AnimationStatus.completed;
  }

  @override
  bool updateShouldNotify(LenzEntranceScope old) => false;
}

/// The prototype's `.stagger>*` + `@keyframes rise`: on mount the child fades
/// in while moving up 22px and scaling .98 -> 1 over 700ms
/// `cubic-bezier(.2,.8,.2,1)`, started `120ms + index * 55ms` after mount.
///
/// Use it per item (lists, grids) with [index], or wrap a column of children
/// with [LenzStagger].
class LenzRise extends StatefulWidget {
  const LenzRise({
    super.key,
    required this.child,
    this.index = 0,
    this.step = LenzMotion.riseStep,
    this.delay = LenzMotion.riseDelay,
    this.duration = LenzMotion.rise,
    this.offset = 22,
    this.animate = true,
  });

  final Widget child;

  /// Position in the stagger sequence (0-based).
  final int index;

  /// Extra delay per index (default 55ms).
  final Duration step;

  /// Base delay before the first item (default 120ms).
  final Duration delay;
  final Duration duration;

  /// Vertical travel in logical pixels (default 22).
  final double offset;
  final bool animate;

  @override
  State<LenzRise> createState() => _LenzRiseState();
}

class _LenzRiseState extends State<LenzRise> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late Duration _lead;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _lead = widget.delay + widget.step * widget.index;
    _c = AnimationController(vsync: this, duration: _lead + widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.animate || LenzMotion.reduced(context) || LenzEntranceScope.covers(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = (_lead + widget.duration).inMicroseconds;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        if (_c.value >= 1) return child!;
        final elapsed = _c.value * total;
        final t = ((elapsed - _lead.inMicroseconds) / widget.duration.inMicroseconds).clamp(
          0.0,
          1.0,
        );
        final e = LenzMotion.ease.transform(t);
        return Opacity(
          opacity: e.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - e)),
            child: Transform.scale(scale: .98 + .02 * e, child: child),
          ),
        );
      },
    );
  }
}

/// A [Column] whose children rise in one after another (`.stagger`).
class LenzStagger extends StatelessWidget {
  const LenzStagger({
    super.key,
    required this.children,
    this.spacing = 0,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.mainAxisSize = MainAxisSize.min,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.startIndex = 0,
    this.step = LenzMotion.riseStep,
    this.delay = LenzMotion.riseDelay,
    this.animate = true,
  });

  final List<Widget> children;

  /// Gap between children (not animated, not counted in the sequence).
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;
  final MainAxisAlignment mainAxisAlignment;

  /// Index of the first child within a larger sequence.
  final int startIndex;
  final Duration step;
  final Duration delay;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      mainAxisAlignment: mainAxisAlignment,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0 && spacing > 0) SizedBox(height: spacing),
          LenzRise(
            index: startIndex + i,
            step: step,
            delay: delay,
            animate: animate,
            child: children[i],
          ),
        ],
      ],
    );
  }
}
