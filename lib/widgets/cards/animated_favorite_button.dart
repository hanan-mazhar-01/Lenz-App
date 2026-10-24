import 'package:flutter/widgets.dart';

import '../../core/theme/lenz_tokens.dart';
import '../../services/haptics.dart';
import '../ui/lenz_icons.dart';

/// Heart toggle with the prototype's spring pop: a filled rose heart when
/// favourited, ink outline otherwise.
class AnimatedFavoriteButton extends StatefulWidget {
  final bool isFavorite;
  final VoidCallback onToggle;
  final double size;

  const AnimatedFavoriteButton({
    super.key,
    required this.isFavorite,
    required this.onToggle,
    this.size = 22,
  });

  /// The prototype's heart colour (`#D6455D`).
  static const Color heartColor = Color(0xFFD6455D);

  @override
  State<AnimatedFavoriteButton> createState() => _AnimatedFavoriteButtonState();
}

class _AnimatedFavoriteButtonState extends State<AnimatedFavoriteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    // pop: .6 -> 1.06 -> 1 (cubic-bezier(.34,1.56,.64,1) feel).
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 30),
      TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: LenzMotion.spring)),
        weight: 70,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant AnimatedFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFavorite != widget.isFavorite && !LenzMotion.reduced(context)) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    Haptics.mediumImpact();
    if (!LenzMotion.reduced(context)) _controller.forward(from: 0.0);
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: widget.isFavorite,
      label: widget.isFavorite ? 'Remove from favorites' : 'Add to favorites',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: ScaleTransition(
          scale: _scale,
          // Saved: solid rose heart. Not saved: ink outline.
          child: LenzIcon(
            LenzIcons.heart,
            size: widget.size,
            filled: widget.isFavorite,
            strokeWidth: widget.isFavorite ? 2.2 : 2,
            color: widget.isFavorite ? AnimatedFavoriteButton.heartColor : LenzColors.ink,
          ),
        ),
      ),
    );
  }
}
