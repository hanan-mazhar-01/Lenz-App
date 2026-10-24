import 'package:flutter/widgets.dart';

import '../../core/theme/lenz_motion.dart';

/// Animates a double towards [value] (like a CSS `transition`), optionally
/// starting from [initialValue] after a [delay] (like the prototype's
/// "set the width 350ms after mount").
///
/// Unlike `TweenAnimationBuilder` it supports an initial delay, retargets from
/// the *current* value when [value] changes, and snaps instantly when the
/// platform asks to reduce motion (or [animate] is false). Overshooting curves
/// such as `LenzMotion.spring` are supported.
class LenzAnimatedDouble extends StatefulWidget {
  const LenzAnimatedDouble({
    super.key,
    required this.value,
    required this.builder,
    this.initialValue,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.linear,
    this.delay = Duration.zero,
    this.delayOnUpdate = false,
    this.animate = true,
  });

  final double value;
  final double? initialValue;
  final Duration duration;
  final Curve curve;
  final Duration delay;

  /// Whether [delay] also applies when [value] changes after the first build.
  final bool delayOnUpdate;
  final bool animate;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<LenzAnimatedDouble> createState() => _LenzAnimatedDoubleState();
}

class _LenzAnimatedDoubleState extends State<LenzAnimatedDouble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  late double _from;
  late double _to;
  Duration _delay = Duration.zero;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _to = widget.value;
    _from = widget.initialValue ?? widget.value;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (_from != _to && widget.animate && !LenzMotion.reduced(context)) {
        _run(widget.delay);
      } else {
        _from = _to;
      }
    }
  }

  @override
  void didUpdateWidget(LenzAnimatedDouble old) {
    super.didUpdateWidget(old);
    if (widget.value != _to) {
      final current = _current;
      _to = widget.value;
      if (!widget.animate || LenzMotion.reduced(context)) {
        _c.stop();
        _from = _to;
      } else {
        _from = current;
        _run(widget.delayOnUpdate ? widget.delay : Duration.zero);
      }
    }
  }

  void _run(Duration delay) {
    _delay = delay;
    _c.duration = delay + widget.duration;
    _c.forward(from: 0);
  }

  double get _current {
    if (_from == _to) return _to;
    final total = _c.duration?.inMicroseconds ?? 0;
    if (total == 0) return _to;
    final elapsed = _c.value * total;
    final span = widget.duration.inMicroseconds;
    if (span == 0) return _to;
    final t = ((elapsed - _delay.inMicroseconds) / span).clamp(0.0, 1.0);
    return _from + (_to - _from) * widget.curve.transform(t);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => widget.builder(context, _current),
    );
  }
}
