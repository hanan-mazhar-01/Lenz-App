import 'package:flutter/material.dart';

import 'lenz_colors.dart';
import 'lenz_motion.dart';
import '../../widgets/ui/lenz_stagger.dart' show LenzEntranceScope;

/// The four screen transitions of the prototype (`transition()` in core.js).
enum LenzRouteKind {
  /// `fwd` / `back`: new page slides in from +44px and fades, the old page
  /// slides -24% (scale .97) and fades. 560ms `cubic-bezier(.2,.85,.2,1)`.
  forward,

  /// `up` / `down`: new page slides up from the bottom (640ms), the old page
  /// scales to .94 and darkens. Closing takes 560ms.
  modalUp,

  /// `zoom`: new page scales 1.12 -> 1 while fading in (700ms), the old page
  /// fades out and shrinks to .94 (600ms).
  zoom,

  /// default: cross fade, new page starts at scale .985 (420ms).
  fade;

  Duration get duration => switch (this) {
    forward => LenzMotion.routeForward,
    modalUp => LenzMotion.routeModalUp,
    zoom => LenzMotion.routeZoom,
    fade => LenzMotion.routeFade,
  };

  Duration get reverseDuration => switch (this) {
    forward => LenzMotion.routeForward,
    modalUp => LenzMotion.routeModalDown,
    zoom => LenzMotion.routeZoom,
    fade => LenzMotion.routeFade,
  };
}

/// Builds the visual of a [LenzRouteKind] from the route animations. Used by
/// `LenzPageRoute` (see `lib/widgets/ui/lenz_routes.dart`) and by
/// [LenzPageTransitionsBuilder] for plain `MaterialPageRoute`s.
abstract final class LenzTransitions {
  static Widget build({
    required BuildContext context,
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required Widget child,
    LenzRouteKind kind = LenzRouteKind.forward,
    LenzRouteKind nextKind = LenzRouteKind.forward,
    bool isFirst = false,
    bool Function()? gestureInProgress,
  }) {
    final reduce = LenzMotion.reduced(context);
    final built = AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      // Inner "rise" entrances stand down while this transition plays, so the
      // screen animates once, not twice.
      child: LenzEntranceScope(animation: animation, child: child),
      builder: (context, child) {
        final linear = gestureInProgress?.call() ?? false;
        final e = _progress(animation, linear);
        final x = _progress(secondaryAnimation, linear);
        var w = child!;
        w = _exit(nextKind, x, w, reduce);
        w = _enter(kind, e, w, reduce);
        return w;
      },
    );
    if (!isFirst) return built;
    // The first route has nothing underneath it: give the cross fade an
    // ivory base like the prototype's `#phone` background.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        const Positioned.fill(child: ColoredBox(color: LenzColors.ivory)),
        built,
      ],
    );
  }

  /// Eased progress; reverse runs use the flipped curve so the motion keeps
  /// the "fast start, soft landing" feel of the prototype's `back` direction.
  static double _progress(Animation<double> a, bool linear) {
    final t = a.value;
    if (linear || t <= 0 || t >= 1) return t.clamp(0.0, 1.0);
    if (a.status == AnimationStatus.reverse) {
      return 1 - LenzMotion.route.transform(1 - t);
    }
    return LenzMotion.route.transform(t);
  }

  static Widget _opacity(double o, Widget child) =>
      o >= 1 ? child : Opacity(opacity: o.clamp(0.0, 1.0), child: child);

  static Widget _scale(double s, Widget child) =>
      s == 1 ? child : Transform.scale(scale: s, child: child);

  // Effect on the page that is being covered / uncovered.
  static Widget _exit(LenzRouteKind next, double x, Widget w, bool reduce) {
    if (x <= 0) return w;
    switch (next) {
      case LenzRouteKind.forward:
        if (reduce) return _opacity(1 - x, w);
        return _opacity(
          1 - x,
          _scale(1 - .03 * x, FractionalTranslation(translation: Offset(-.24 * x, 0), child: w)),
        );
      case LenzRouteKind.modalUp:
        return _scale(
          1 - .06 * x,
          ColorFiltered(
            colorFilter: ColorFilter.mode(Color.fromRGBO(0, 0, 0, .3 * x), BlendMode.srcOver),
            child: w,
          ),
        );
      case LenzRouteKind.zoom:
        final z = (x / (600 / 700)).clamp(0.0, 1.0);
        return _opacity(1 - z, _scale(1 - .06 * z, w));
      case LenzRouteKind.fade:
        return _opacity(1 - x, w);
    }
  }

  // Effect on the page that is entering / leaving.
  static Widget _enter(LenzRouteKind kind, double e, Widget w, bool reduce) {
    if (e >= 1) return w;
    switch (kind) {
      case LenzRouteKind.forward:
        if (reduce) return _opacity(e, w);
        return _opacity(e, Transform.translate(offset: Offset(44 * (1 - e), 0), child: w));
      case LenzRouteKind.modalUp:
        return FractionalTranslation(translation: Offset(0, 1 - e), child: w);
      case LenzRouteKind.zoom:
        return _opacity(e, _scale(1 + .12 * (1 - e), w));
      case LenzRouteKind.fade:
        return _opacity(e, _scale(.985 + .015 * e, w));
    }
  }
}

/// Theme-level transition so every `MaterialPageRoute` (including screens that
/// have not been migrated to `LenzRoutes` yet) gets the prototype's forward
/// slide + fade.
class LenzPageTransitionsBuilder extends PageTransitionsBuilder {
  const LenzPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return LenzTransitions.build(
      context: context,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      isFirst: route.isFirst,
      gestureInProgress: () => route.navigator?.userGestureInProgress ?? false,
      child: child,
    );
  }
}
