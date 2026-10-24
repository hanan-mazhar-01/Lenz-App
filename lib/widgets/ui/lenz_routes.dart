import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_page_transitions.dart';

export '../../core/theme/lenz_page_transitions.dart' show LenzRouteKind;

/// Route factories for the prototype's screen transitions
/// (`transition()` in core.js).
///
/// ```dart
/// Navigator.push(context, LenzRoutes.forward(const ReportScreen()));
/// Navigator.push(context, LenzRoutes.modalUp(const CameraScreen()));
/// Navigator.pushReplacement(context, LenzRoutes.zoom(const AnalyzingScreen()));
/// ```
abstract final class LenzRoutes {
  /// New page slides in from +44px and fades while the old one slides -24%
  /// (scale .97) and fades; 560ms. Supports the iOS swipe-back gesture.
  static LenzPageRoute<T> forward<T>(
    Widget page, {
    RouteSettings? settings,
    bool? swipeBack,
  }) =>
      LenzPageRoute<T>(
        builder: (_) => page,
        kind: LenzRouteKind.forward,
        settings: settings,
        swipeBack: swipeBack,
      );

  /// Same as [forward] with a builder (use when you need the route context).
  static LenzPageRoute<T> forwardBuilder<T>(
    WidgetBuilder builder, {
    RouteSettings? settings,
    bool? swipeBack,
  }) =>
      LenzPageRoute<T>(
        builder: builder,
        kind: LenzRouteKind.forward,
        settings: settings,
        swipeBack: swipeBack,
      );

  /// New page slides up from the bottom (640ms) while the old one scales to
  /// .94 and darkens; closing takes 560ms. Used for camera / capture.
  static LenzPageRoute<T> modalUp<T>(Widget page, {RouteSettings? settings}) =>
      LenzPageRoute<T>(
        builder: (_) => page,
        kind: LenzRouteKind.modalUp,
        settings: settings,
        fullscreenDialog: true,
      );

  /// New page scales 1.12 -> 1 while fading in (700ms), the old one fades and
  /// shrinks. Used for onboarding, analysis and reveals.
  static LenzPageRoute<T> zoom<T>(Widget page, {RouteSettings? settings}) =>
      LenzPageRoute<T>(
        builder: (_) => page,
        kind: LenzRouteKind.zoom,
        settings: settings,
      );

  /// Cross fade (420ms, new page starts at scale .985).
  static LenzPageRoute<T> fade<T>(Widget page, {RouteSettings? settings}) =>
      LenzPageRoute<T>(
        builder: (_) => page,
        kind: LenzRouteKind.fade,
        settings: settings,
      );
}

/// `MaterialApp.builder` that puts the ivory canvas behind every route so
/// cross-fades never expose the window background:
/// `MaterialApp(builder: lenzAppBuilder, ...)`.
Widget lenzAppBuilder(BuildContext context, Widget? child) =>
    ColoredBox(color: LenzColors.ivory, child: child);

/// A [PageRoute] that plays one of the [LenzRouteKind] transitions and, for
/// `forward` routes on iOS, supports the edge swipe-back gesture.
class LenzPageRoute<T> extends PageRoute<T> {
  LenzPageRoute({
    required this.builder,
    this.kind = LenzRouteKind.forward,
    super.settings,
    this.maintainState = true,
    super.fullscreenDialog,
    bool? swipeBack,
  }) : swipeBack = swipeBack ??
            (kind == LenzRouteKind.forward &&
                !fullscreenDialog &&
                defaultTargetPlatform == TargetPlatform.iOS);

  final WidgetBuilder builder;
  final LenzRouteKind kind;

  /// Enables the left-edge swipe-back gesture.
  final bool swipeBack;

  LenzRouteKind _nextKind = LenzRouteKind.forward;

  @override
  final bool maintainState;

  @override
  Duration get transitionDuration => kind.duration;

  @override
  Duration get reverseTransitionDuration => kind.reverseDuration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    _nextKind = nextRoute is LenzPageRoute
        ? nextRoute.kind
        : LenzRouteKind.forward;
  }

  @override
  void didPopNext(Route<dynamic> nextRoute) {
    super.didPopNext(nextRoute);
    if (nextRoute is LenzPageRoute) _nextKind = nextRoute.kind;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: builder(context),
    );
  }

  /// The route's transition controller (used by the swipe-back gesture).
  AnimationController get gestureController => controller!;

  bool get _gestureEnabled {
    if (!swipeBack) return false;
    if (isFirst || !isCurrent) return false;
    if (navigator == null || navigator!.userGestureInProgress) return false;
    if (controller == null || controller!.status != AnimationStatus.completed) {
      return false;
    }
    if (secondaryAnimation?.status != AnimationStatus.dismissed) return false;
    return popDisposition != RoutePopDisposition.doNotPop;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    var page = child;
    if (swipeBack) {
      page = _LenzSwipeBack(
        enabledGetter: () => _gestureEnabled,
        route: this,
        child: child,
      );
    }
    return LenzTransitions.build(
      context: context,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      kind: kind,
      nextKind: _nextKind,
      isFirst: isFirst,
      gestureInProgress: () => navigator?.userGestureInProgress ?? false,
      child: page,
    );
  }
}

// ---------------------------------------------------------------------------
// iOS style edge swipe back for LenzPageRoute (same mechanics as
// CupertinoPageRoute, driven by the route's own animation controller).
// ---------------------------------------------------------------------------

const double _kBackGestureWidth = 24;
const double _kMinFlingVelocity = 1; // screen widths per second
const int _kMaxDroppedSwipePageForwardAnimationTime = 800; // ms
const int _kMaxPageBackAnimationTime = 300; // ms

class _LenzSwipeBack<T> extends StatefulWidget {
  const _LenzSwipeBack({
    required this.enabledGetter,
    required this.route,
    required this.child,
  });

  final bool Function() enabledGetter;
  final LenzPageRoute<T> route;
  final Widget child;

  @override
  State<_LenzSwipeBack<T>> createState() => _LenzSwipeBackState<T>();
}

class _LenzSwipeBackState<T> extends State<_LenzSwipeBack<T>> {
  _BackGesture<T>? _gesture;
  late final HorizontalDragGestureRecognizer _recognizer =
      HorizontalDragGestureRecognizer(debugOwner: this)
        ..onStart = _onStart
        ..onUpdate = _onUpdate
        ..onEnd = _onEnd
        ..onCancel = _onCancel;

  @override
  void dispose() {
    _recognizer.dispose();
    _gesture?.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails d) {
    _gesture = _BackGesture<T>(
      route: widget.route,
      onEnded: () => _gesture = null,
    );
  }

  void _onUpdate(DragUpdateDetails d) {
    final w = context.size!.width;
    _gesture?.update(_convert(d.primaryDelta! / w));
  }

  void _onEnd(DragEndDetails d) {
    final w = context.size!.width;
    _gesture?.end(_convert(d.velocity.pixelsPerSecond.dx / w));
    _gesture = null;
  }

  void _onCancel() {
    _gesture?.end(0);
    _gesture = null;
  }

  double _convert(double v) =>
      Directionality.of(context) == TextDirection.rtl ? -v : v;

  void _down(PointerDownEvent e) {
    if (widget.enabledGetter()) _recognizer.addPointer(e);
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).left;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: 0,
          width: math.max(_kBackGestureWidth, inset),
          top: 0,
          bottom: 0,
          child: Listener(
            onPointerDown: _down,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}

class _BackGesture<T> {
  _BackGesture({required this.route, required this.onEnded}) {
    navigator = route.navigator!;
    controller = route.gestureController;
    navigator.didStartUserGesture();
  }

  final LenzPageRoute<T> route;
  final VoidCallback onEnded;
  late final NavigatorState navigator;
  late final AnimationController controller;
  bool _done = false;

  void update(double delta) {
    controller.value -= delta;
  }

  void end(double velocity) {
    if (_done) return;
    _done = true;
    const curve = Curves.fastLinearToSlowEaseIn;
    final bool animateForward;
    if (velocity.abs() >= _kMinFlingVelocity) {
      animateForward = velocity <= 0;
    } else {
      animateForward = controller.value > .5;
    }
    if (animateForward) {
      final ms = math.min(
        (_kMaxDroppedSwipePageForwardAnimationTime * (1 - controller.value))
            .floor(),
        _kMaxPageBackAnimationTime,
      );
      controller.animateTo(
        1,
        duration: Duration(milliseconds: ms),
        curve: curve,
      );
    } else {
      if (navigator.canPop()) navigator.pop();
      if (controller.isAnimating) {
        final ms = math.min(
          (_kMaxDroppedSwipePageForwardAnimationTime * controller.value)
              .floor(),
          _kMaxPageBackAnimationTime,
        );
        controller.animateBack(
          0,
          duration: Duration(milliseconds: ms),
          curve: curve,
        );
      }
    }
    if (controller.isAnimating) {
      late AnimationStatusListener listener;
      listener = (status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(listener);
      };
      controller.addStatusListener(listener);
    } else {
      navigator.didStopUserGesture();
    }
    onEnded();
  }

  void dispose() {
    if (!_done) {
      _done = true;
      navigator.didStopUserGesture();
    }
  }
}
