import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'lenz_assets.dart';
import 'lenz_mood.dart';
import 'lenz_painter.dart';
import 'lenz_spring.dart';

/// App-wide record of the last pointer position (global logical px), fed by a
/// global route on [GestureBinding.pointerRouter]. Installed automatically by
/// the first [LenzCharacter]; nothing needs to be added to the widget tree.
class LenzPointer {
  LenzPointer._();

  static final Stopwatch _clock = Stopwatch()..start();
  static bool _installed = false;
  static Offset _position = Offset.zero;
  static int _lastMs = -1000000;

  /// Last pointer position in global coordinates.
  static Offset get position => _position;

  /// Milliseconds since the last pointer move / down / hover.
  static int get idleMs => _clock.elapsedMilliseconds - _lastMs;

  static void ensureInstalled() {
    if (_installed) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  static void _route(PointerEvent e) {
    if (e is PointerDownEvent || e is PointerMoveEvent || e is PointerHoverEvent) record(e.position);
  }

  /// Records a pointer position manually (tests / custom input sources).
  static void record(Offset globalPosition) {
    _position = globalPosition;
    _lastMs = _clock.elapsedMilliseconds;
  }
}

/// Imperative handle to a [LenzCharacter].
class LenzController {
  _LenzCharacterState? _state;

  bool get isAttached => _state != null;

  /// Current mood of the attached character (null when detached).
  LenzMood? get mood => _state?._rig.mood;

  /// Springs to [mood] with a small hop (like the prototype `setMood`).
  void setMood(LenzMood mood) => _state?._rig.setMood(mood);

  /// A bigger hop (prototype `hop()`).
  void hop() => _state?._rig.hop();

  /// Same bounce as a tap.
  void bounce() => _state?._rig.bounce();
}

/// The animated Lenz mascot: the owner's layered artwork driven by springs,
/// painted by a single [CustomPainter] per instance. Size it with the parent
/// constraints (it keeps the [LenzView.aspectRatio] internally), e.g.
/// `SizedBox(width: 150, child: LenzCharacter(mood: LenzMood.hello, view: LenzView.bust))`.
class LenzCharacter extends StatefulWidget {
  const LenzCharacter({
    super.key,
    this.mood = LenzMood.idle,
    this.view = LenzView.full,
    this.interactive = true,
    this.fx = true,
    this.shadow = false,
    this.wake = true,
    this.controller,
    this.onTap,
    this.reduceMotion,
  });

  final LenzMood mood;
  final LenzView view;

  /// Tap to bounce (and call [onTap]).
  final bool interactive;

  /// Draw the mood FX overlays (sparkles, "!", think bubble, "?", sweat, ping).
  final bool fx;

  /// Ground shadow ellipse under the feet (useful for [LenzView.full]).
  final bool shadow;

  /// Lids start closed and open after ~260 ms.
  final bool wake;
  final LenzController? controller;
  final VoidCallback? onTap;

  /// Overrides `MediaQuery.disableAnimations` when non-null.
  final bool? reduceMotion;

  @override
  State<LenzCharacter> createState() => _LenzCharacterState();
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _LenzCharacterState extends State<LenzCharacter> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final LenzRig _rig;
  final LenzPaintCache _cache = LenzPaintCache();
  final _Repaint _repaint = _Repaint();
  final GlobalKey _paintKey = GlobalKey();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    _rig = LenzRig(mood: widget.mood, wake: widget.wake);
    widget.controller?._state = this;
    _ticker = createTicker(_tick);
    LenzPointer.ensureInstalled();
    WidgetsBinding.instance.addObserver(this);
    final assets = LenzAssets.instance;
    if (assets.isReady) {
      _start();
    } else {
      assets.ensureLoaded().then((_) {
        if (!mounted || !assets.isReady) return;
        _repaint.ping();
        _start();
      });
    }
  }

  void _start() {
    if (_ticker.isActive || !_appActive || !LenzAssets.instance.isReady) return;
    _last = Duration.zero;
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rig.reduceMotion = widget.reduceMotion ?? (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
  }

  @override
  void didUpdateWidget(LenzCharacter old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller!._state = null;
      widget.controller?._state = this;
    }
    if (old.mood != widget.mood) _rig.setMood(widget.mood);
    if (old.reduceMotion != widget.reduceMotion) {
      _rig.reduceMotion = widget.reduceMotion ?? (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    if (_appActive) {
      _start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.001, 0.033);
    _last = elapsed;
    double? ax, ay;
    if (LenzPointer.idleMs < 2600) {
      final box = _paintKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        final vb = widget.view.viewBox, s = box.size;
        final head = box.localToGlobal(
          Offset(s.width * ((700 - vb.left) / vb.width), s.height * ((420 - vb.top) / vb.height)),
        );
        final ptr = LenzPointer.position;
        ax = ((ptr.dx - head.dx) / 260).clamp(-1.0, 1.0);
        ay = ((ptr.dy - head.dy) / 260).clamp(-1.0, 1.0);
      }
    }
    _rig.advance(dt, aimX: ax, aimY: ay);
    _repaint.ping();
  }

  void _handleTap() {
    _rig.bounce();
    widget.onTap?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller?._state == this) widget.controller!._state = null;
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = RepaintBoundary(
      child: CustomPaint(
        key: _paintKey,
        size: Size.infinite,
        painter: LenzPainter(
          rig: _rig,
          cache: _cache,
          view: widget.view,
          fx: widget.fx,
          shadow: widget.shadow,
          repaint: _repaint,
        ),
      ),
    );
    if (widget.interactive) {
      child = GestureDetector(behavior: HitTestBehavior.opaque, onTap: _handleTap, child: child);
    }
    return AspectRatio(aspectRatio: widget.view.aspectRatio, child: child);
  }
}
