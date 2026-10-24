import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import '../../core/theme/lenz_text.dart';
import '../lenz/lenz.dart';

/// The prototype's `.bubble`: a white speech bubble that pops in (500ms,
/// spring, after a 500ms delay) and types its text out character by character
/// (starts at 520ms, 22-42ms per character, blinking 2px caret while typing).
///
/// The bubble sizes itself to the text typed so far, like the prototype
/// (`width: max-content; max-width: 210px`).
///
/// * [right] mirrors the corner radius (`.bubble.r` / `.coach.rev .bubble`).
/// * [dark] is the frosted variant for dark screens (`.bubble.dark`).
/// * Respects reduced motion: no pop, the full text shows immediately.
class LenzBubble extends StatefulWidget {
  const LenzBubble({
    super.key,
    required this.text,
    this.dark = false,
    this.right = false,
    this.maxWidth = 210,
    this.typewriter = true,
    this.popDelay = const Duration(milliseconds: 500),
    this.typeDelay = const Duration(milliseconds: 520),
    this.style,
  });

  final String text;
  final bool dark;
  final bool right;
  final double maxWidth;
  final bool typewriter;
  final Duration popDelay;
  final Duration typeDelay;
  final TextStyle? style;

  @override
  State<LenzBubble> createState() => _LenzBubbleState();
}

class _LenzBubbleState extends State<LenzBubble>
    with SingleTickerProviderStateMixin {
  static const Duration _popDuration = Duration(milliseconds: 500);
  static final math.Random _rng = math.Random();

  late final AnimationController _pop;
  Timer? _typeTimer;
  Timer? _caretTimer;
  int _visible = 0;
  bool _caretOn = true;
  bool _started = false;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: widget.popDelay + _popDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = LenzMotion.reduced(context);
    if (_started) return;
    _started = true;
    if (_reduced) {
      _pop.value = 1;
      _visible = widget.text.length;
    } else {
      _pop.forward();
      if (widget.typewriter) {
        _startTyping(widget.typeDelay);
      } else {
        _visible = widget.text.length;
      }
    }
  }

  @override
  void didUpdateWidget(covariant LenzBubble old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      if (_reduced || !widget.typewriter) {
        setState(() => _visible = widget.text.length);
      } else {
        // New line of speech: retype from scratch, no extra delay.
        _startTyping(const Duration(milliseconds: 120));
      }
    }
  }

  void _startTyping(Duration lead) {
    _typeTimer?.cancel();
    _caretTimer?.cancel();
    setState(() {
      _visible = 0;
      _caretOn = true;
    });
    _caretTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _caretOn = !_caretOn);
    });
    void tick() {
      if (!mounted) return;
      setState(() => _visible = math.min(_visible + 1, widget.text.length));
      if (_visible < widget.text.length) {
        _typeTimer = Timer(
          Duration(milliseconds: 22 + _rng.nextInt(20)),
          tick,
        );
      } else {
        _caretTimer?.cancel();
      }
    }

    _typeTimer = Timer(lead, tick);
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _caretTimer?.cancel();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final base = (widget.style ?? LenzText.bubble).copyWith(
      color: dark ? Colors.white : LenzColors.ink,
    );
    final typing = _visible < widget.text.length;
    final shown = widget.text.substring(0, _visible.clamp(0, widget.text.length));

    final radius = widget.right
        ? const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(6),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(20),
          );

    Widget bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color.fromRGBO(255, 255, 255, .14) : Colors.white,
        borderRadius: radius,
        border: Border.all(
          color: dark ? const Color.fromRGBO(255, 255, 255, .22) : LenzColors.line,
        ),
        boxShadow: dark ? null : LenzShadows.sh2,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              style: base,
              children: [
                TextSpan(text: shown),
                if (typing && widget.typewriter)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Opacity(
                        opacity: _caretOn ? 1 : 0,
                        child: Container(
                          width: 2,
                          height: (base.fontSize ?? 13.5) * 1.05,
                          color: base.color,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (dark) {
      bubble = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: bubble,
        ),
      );
    }

    return Semantics(
      container: true,
      label: widget.text,
      child: AnimatedBuilder(
        animation: _pop,
        builder: (context, child) {
          final total = widget.popDelay + _popDuration;
          final ms = _pop.value * total.inMilliseconds;
          final t = ((ms - widget.popDelay.inMilliseconds) /
                  _popDuration.inMilliseconds)
              .clamp(0.0, 1.0);
          return Opacity(
            opacity: LenzPopCurve.opacity(t),
            child: Transform.scale(
              scale: LenzPopCurve.scale(t),
              alignment: widget.right ? Alignment.bottomRight : Alignment.bottomLeft,
              child: child,
            ),
          );
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: bubble,
        ),
      ),
    );
  }
}

/// The prototype's `.coach`: Lenz next to a speech bubble.
///
/// `reverse` puts the character on the right (`.coach.rev`). The character is
/// sized by [width]; the bubble fills the rest (max 210px) and is centred
/// vertically against the character, with a 2px gap.
class LenzCoach extends StatelessWidget {
  const LenzCoach({
    super.key,
    required this.mood,
    required this.text,
    this.view = LenzView.bust,
    this.width = 116,
    this.reverse = false,
    this.dark = false,
    this.fx = true,
    this.interactive = true,
    this.controller,
    this.bubbleMaxWidth = 210,
    this.margin = const EdgeInsets.only(top: 2, bottom: 8),
  });

  final LenzMood mood;
  final String text;
  final LenzView view;
  final double width;
  final bool reverse;
  final bool dark;
  final bool fx;
  final bool interactive;
  final LenzController? controller;
  final double bubbleMaxWidth;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final character = SizedBox(
      width: width,
      child: LenzCharacter(
        mood: mood,
        view: view,
        fx: fx,
        interactive: interactive,
        controller: controller,
      ),
    );
    final bubble = Flexible(
      child: Padding(
        padding: EdgeInsets.only(
          left: reverse ? 0 : 2,
          right: reverse ? 2 : 0,
        ),
        child: Align(
          alignment: reverse ? Alignment.centerRight : Alignment.centerLeft,
          child: LenzBubble(
            text: text,
            dark: dark,
            right: reverse,
            maxWidth: bubbleMaxWidth,
          ),
        ),
      ),
    );
    return Padding(
      padding: margin,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        textDirection: reverse ? TextDirection.rtl : TextDirection.ltr,
        children: [character, bubble],
      ),
    );
  }
}
