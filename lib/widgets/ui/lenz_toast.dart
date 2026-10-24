import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import '../../core/theme/lenz_text.dart';

/// The visual of the prototype's `.toast`: forest pill, white 13.5/800 text,
/// `sh2`. Use [showLenzToast] to display one.
class LenzToast extends StatelessWidget {
  const LenzToast({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width - 32;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LenzColors.forest,
          borderRadius: BorderRadius.circular(LenzRadii.pill),
          boxShadow: LenzShadows.sh2,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LenzText.toast,
          ),
        ),
      ),
    );
  }
}

OverlayEntry? _currentToast;

/// Shows a toast at the top of the screen (prototype `toast()`): it drops in
/// with a small scale, stays, then fades out over 2.6s in total. Showing a new
/// toast replaces the current one.
void showLenzToast(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _currentToast?.remove();
  _currentToast = null;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _ToastHost(
      message: message,
      onDone: () {
        if (_currentToast == entry) _currentToast = null;
        entry.remove();
      },
    ),
  );
  _currentToast = entry;
  overlay.insert(entry);
}

class _ToastHost extends StatefulWidget {
  const _ToastHost({required this.message, required this.onDone});
  final String message;
  final VoidCallback onDone;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: LenzMotion.toast,
  )
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Keyframes `0% / 12%,85% / 100%` with `--ease` between them.
  static (double opacity, double dy, double scale) _at(double t) {
    if (t < .12) {
      final p = LenzMotion.ease.transform(t / .12);
      return (p, -16 + 16 * p, .9 + .1 * p);
    }
    if (t < .85) return (1, 0, 1);
    final p = LenzMotion.ease.transform((t - .85) / .15);
    return (1 - p, -10 * p, 1);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final reduced = LenzMotion.reduced(context);
    return Positioned(
      left: 0,
      right: 0,
      top: (top < 20 ? 20 : top) + 10,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final (o, dy, s) = _at(_c.value);
              return Opacity(
                opacity: o.clamp(0.0, 1.0),
                child: reduced
                    ? child
                    : Transform.translate(
                        offset: Offset(0, dy),
                        child: Transform.scale(scale: s, child: child),
                      ),
              );
            },
            child: Semantics(
              liveRegion: true,
              child: Material(
                type: MaterialType.transparency,
                child: LenzToast(message: widget.message),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
