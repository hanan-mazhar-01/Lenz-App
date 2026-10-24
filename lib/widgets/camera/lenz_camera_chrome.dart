import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../lenz/lenz.dart';
import '../ui/lenz_svg_path.dart';
import '../ui/ui.dart';

/// Shared chrome of the Lenz scan journey (prototype `.cam`, `.vf`,
/// `.shutter`, `.tipchip`, `.flash`, journey rider). Presentation only: none
/// of these widgets measure or detect anything.

/// Category art used where the prototype shows product art and no real photo
/// is available.
String lenzCategoryArt(ProductCategory category) => switch (category) {
  ProductCategory.sneakers => 'assets/lenz/categories/cat_sneakers.png',
  ProductCategory.bags => 'assets/lenz/categories/cat_bags.png',
  ProductCategory.watches => 'assets/lenz/categories/cat_watches.png',
  ProductCategory.clothing => 'assets/lenz/categories/cat_clothing.png',
  ProductCategory.wallets ||
  ProductCategory.eyewear ||
  ProductCategory.accessories => 'assets/lenz/categories/cat_accessories.png',
};

/// Lenz's head riding the journey stepper (prototype: peek view, idle mood,
/// no fx, no tap, no wake-up).
class LenzJourneyRider extends StatelessWidget {
  const LenzJourneyRider({super.key, this.mood = LenzMood.idle});

  final LenzMood mood;

  @override
  Widget build(BuildContext context) =>
      LenzCharacter(mood: mood, view: LenzView.peek, fx: false, interactive: false, wake: false);
}

/// The dark camera scene behind the live preview (prototype `.feed` +
/// `.bokeh`). Visible while the camera starts, and under a failed camera.
class LenzCameraBackdrop extends StatelessWidget {
  const LenzCameraBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        Widget bokeh(double left, double top, double size, Color color) => Positioned(
          left: left,
          top: top,
          width: size,
          height: size,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: .35),
              ),
            ),
          ),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -.16),
                  radius: .9,
                  colors: [Color(0xFF2E4A3E), Color(0xFF0C1511)],
                  stops: [0, .7],
                ),
              ),
            ),
            bokeh(-w * .1, h * .1, 200, const Color(0xFF3F7A60)),
            bokeh(w * 1.08 - 240, h * .52, 240, const Color(0xFF6A5A2A)),
            bokeh(w * .3, h * .94 - 160, 160, const Color(0xFF2E5E7A)),
          ],
        );
      },
    );
  }
}

/// Viewfinder corner brackets that breathe, with a sweeping scan line
/// (prototype `.vf` + `.scanline`). Decorative: it does not track anything.
class LenzViewfinder extends StatefulWidget {
  const LenzViewfinder({super.key, this.scanLine = true, this.frozen = false});

  final bool scanLine;

  /// The shutter was pressed: stop breathing and sweeping on the spot.
  final bool frozen;

  @override
  State<LenzViewfinder> createState() => _LenzViewfinderState();
}

class _LenzViewfinderState extends State<LenzViewfinder> with TickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant LenzViewfinder old) {
    super.didUpdateWidget(old);
    if (old.frozen != widget.frozen) _sync();
  }

  void _sync() {
    if (LenzMotion.reduced(context)) {
      _breathe.stop();
      _sweep.stop();
      _sweep.value = .25;
    } else if (widget.frozen) {
      _breathe.stop();
      _sweep.stop();
    } else {
      if (!_breathe.isAnimating) _breathe.repeat();
      if (!_sweep.isAnimating) _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_breathe, _sweep]),
        builder: (context, _) {
          // CSS `breathe`: 50% -> scale(1.035), ease.
          final b = Curves.ease.transform(1 - (2 * _breathe.value - 1).abs());
          final s = Curves.easeInOut.transform(1 - (2 * _sweep.value - 1).abs());
          return Transform.scale(
            scale: 1 + .035 * b,
            child: CustomPaint(painter: _ViewfinderPainter(sweep: widget.scanLine ? s : null)),
          );
        },
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({this.sweep});

  final double? sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final arm = math.min(44.0, size.shortestSide * .2);
    const stroke = 4.0;
    const radius = 26.0;
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final rr = math.min(radius, arm - 2);
    final d = stroke / 2;
    for (final (cx, cy, sx, sy) in [
      (r.left + d, r.top + d, 1.0, 1.0),
      (r.right - d, r.top + d, -1.0, 1.0),
      (r.left + d, r.bottom - d, 1.0, -1.0),
      (r.right - d, r.bottom - d, -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(cx, cy + sy * (arm - d))
        ..lineTo(cx, cy + sy * rr)
        ..arcToPoint(Offset(cx + sx * rr, cy), radius: Radius.circular(rr), clockwise: sx * sy > 0)
        ..lineTo(cx + sx * (arm - d), cy);
      canvas.drawPath(path, p);
    }

    final t = sweep;
    if (t != null) {
      final y = r.top + r.height * (.08 + .82 * t);
      final line = Rect.fromLTWH(r.left + r.width * .06, y, r.width * .88, 3);
      const glow = Color(0xFF6BE08F);
      final shader = const LinearGradient(colors: [Color(0x006BE08F), glow, Color(0x006BE08F)])
          .createShader(line);
      canvas.drawRRect(
        RRect.fromRectAndRadius(line.inflate(5), const Radius.circular(8)),
        Paint()
          ..shader = shader
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
          ..color = glow.withValues(alpha: .6),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(line, const Radius.circular(3)),
        Paint()..shader = shader,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter old) => old.sweep != sweep;
}

/// The prototype's `.shutter`: 82px white ring with a 62px white disc;
/// spring press (ring .9, disc .88). Shows a spinner while [busy].
class LenzShutterButton extends StatefulWidget {
  const LenzShutterButton({super.key, required this.onTap, this.busy = false, this.size = 82});

  final VoidCallback? onTap;
  final bool busy;

  /// Outer diameter; the inner disc is 20px smaller (82 / 62 by default,
  /// 78 / 58 on the evidence capture screen).
  final double size;

  @override
  State<LenzShutterButton> createState() => _LenzShutterButtonState();
}

class _LenzShutterButtonState extends State<LenzShutterButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final curve = LenzMotion.reduced(context) ? Curves.easeOut : LenzMotion.spring;
    return Semantics(
      button: true,
      label: 'Capture',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .9 : 1,
          duration: LenzMotion.pressIcon,
          curve: curve,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 5),
            ),
            alignment: Alignment.center,
            child: AnimatedScale(
              scale: _down ? .88 : 1,
              duration: LenzMotion.pressIcon,
              curve: curve,
              child: Container(
                width: widget.size - 20,
                height: widget.size - 20,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                alignment: Alignment.center,
                child: widget.busy
                    ? const CupertinoActivityIndicator(color: LenzColors.forest, radius: 12)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass camera control (prototype `.icon-btn.dark`, 56px, radius 20).
class LenzCameraControl extends StatelessWidget {
  const LenzCameraControl({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final String icon;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => LenzIconButton(
    icon: icon,
    onTap: onTap,
    dark: true,
    size: 56,
    radius: 20,
    iconSize: 24,
    semanticLabel: semanticLabel,
  );
}

/// A frosted text button for the camera bar (prototype "Can't take").
class LenzCameraTextButton extends StatelessWidget {
  const LenzCameraTextButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LenzPressable(
      onTap: onTap,
      semanticLabel: label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LenzRadii.buttonSm),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, .14),
              borderRadius: BorderRadius.circular(LenzRadii.buttonSm),
              border: Border.all(color: const Color.fromRGBO(255, 255, 255, .2)),
            ),
            child: Center(
              widthFactor: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: LenzText.buttonSm.copyWith(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The prototype's `.tipchip`: a frosted pill with an icon. Always neutral:
/// the app does not measure light, centring or focus.
class LenzTipChip extends StatelessWidget {
  const LenzTipChip({super.key, required this.icon, required this.label, this.maxLines = 1});

  final String icon;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(255, 255, 255, .14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color.fromRGBO(255, 255, 255, .2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LenzIcon(icon, size: 14, strokeWidth: 2.4, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: LenzText.chip.copyWith(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White capture flash (prototype `.flash`: 0 -> .9 -> 0 over 380ms).
class LenzCaptureFlash extends StatelessWidget {
  const LenzCaptureFlash({super.key, required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final v = animation.value;
          final o = animation.isAnimating ? .9 * (1 - (2 * v - 1).abs()) : 0.0;
          if (o <= 0) return const SizedBox.expand();
          return ColoredBox(color: Colors.white.withValues(alpha: o));
        },
      ),
    );
  }
}

/// Camera top bar (prototype `.camtop`): glass close, centred title, glass
/// flash toggle (gold bolt when on).
class LenzCameraTopBar extends StatelessWidget {
  const LenzCameraTopBar({
    super.key,
    required this.title,
    this.subtitle,
    required this.onClose,
    required this.onFlash,
    required this.flashOn,
    this.closeIcon = LenzIcons.x,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onClose;
  final VoidCallback onFlash;
  final bool flashOn;
  final String closeIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Row(
        children: [
          LenzIconButton(icon: closeIcon, dark: true, onTap: onClose, semanticLabel: 'Close'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LenzText.title.copyWith(color: Colors.white, fontSize: 17),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LenzText.cap.copyWith(color: LenzColors.onDarkMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          LenzIconButton(
            icon: LenzIcons.bolt,
            dark: true,
            iconSize: 21,
            iconColor: flashOn ? LenzColors.gold2 : Colors.white,
            onTap: onFlash,
            semanticLabel: flashOn ? 'Flash on' : 'Flash off',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Evidence capture chrome (mock-up `evidence_capture_redesign`): step-dot top
// bar, glass pills, the coach avatar. Presentation only.
// ---------------------------------------------------------------------------

/// The few stroke icons the capture mock-up uses that the shared icon set
/// does not have (ported from the mock's `lenz_mock.js`, 24px viewBox).
abstract final class LenzCamIcons {
  static const sun = 'sun';
  static const focus = 'focus';
  static const glare = 'glare';
  static const flip = 'flip';
}

class LenzCamIcon extends StatelessWidget {
  const LenzCamIcon(
    this.name, {
    super.key,
    this.size = 18,
    this.strokeWidth = 2.2,
    this.color = Colors.white,
  });

  final String name;
  final double size;
  final double strokeWidth;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _CamIconPainter(name, strokeWidth, color)),
  );
}

class _CamIconPainter extends CustomPainter {
  _CamIconPainter(this.name, this.strokeWidth, this.color);

  final String name;
  final double strokeWidth;
  final Color color;

  Path _circle(double x, double y, double r) =>
      Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));

  Path get _path => switch (name) {
    'sun' =>
      _circle(12, 12, 4)..addPath(
        parseSvgPathData(
          'M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M19 5l-1.5 1.5M6.5 17.5L5 19',
        ),
        Offset.zero,
      ),
    'focus' =>
      _circle(12, 12, 7.5)
        ..addPath(_circle(12, 12, 2), Offset.zero)
        ..addPath(parseSvgPathData('M12 2v3M12 19v3M2 12h3M19 12h3'), Offset.zero),
    'glare' => parseSvgPathData(
      'M3 3l18 18M10.6 6.2A9 9 0 0 1 12 6c5 0 8 4 9 6a14 14 0 0 1-2.6 3.4M6.5 7.6C4.4 9 3.2 11 3 12c1 2 4 6 9 6 1.4 0 2.6-.3 3.7-.8',
    ),
    'flip' => parseSvgPathData('M4 8h12l-3-3M20 16H8l3 3'),
    _ => Path(),
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      _path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CamIconPainter old) =>
      old.name != name || old.strokeWidth != strokeWidth || old.color != color;
}

/// Frosted pill over the camera (mock `.glass` + `.eg` / `.chip` / `.skip`).
class LenzGlassPill extends StatelessWidget {
  const LenzGlassPill({
    super.key,
    required this.label,
    required this.onTap,
    this.leading,
    this.height = 40,
    this.fontSize = 12.5,
    this.fontWeight = FontWeight.w900,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  final double height;
  final double fontSize;
  final FontWeight fontWeight;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(height / 2);
    return LenzPressable(
      onTap: onTap,
      semanticLabel: semanticLabel ?? label,
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            constraints: BoxConstraints(minHeight: height),
            padding: EdgeInsets.fromLTRB(leading == null ? 14 : 11, 0, 14, 0),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, .14),
              borderRadius: r,
              border: Border.all(color: const Color.fromRGBO(255, 255, 255, .22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 6)],
                Text(
                  label,
                  maxLines: 1,
                  style: LenzText.buttonSm.copyWith(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round Lenz avatar of the coach row (mock `.coach .face`): the peek view,
/// not interactive.
class LenzCoachAvatar extends StatelessWidget {
  const LenzCoachAvatar({super.key, this.size = 54, this.mood = LenzMood.idle, this.ring = true});

  final double size;
  final LenzMood mood;

  /// White ring + shadow (coach row); the sheet head uses a plain mint disc.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final w = size * 1.32;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ring
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [LenzColors.mint, Colors.white],
              )
            : null,
        color: ring ? null : LenzColors.mint,
        boxShadow: ring
            ? const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, .5),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                  spreadRadius: -6,
                ),
                BoxShadow(color: Color.fromRGBO(255, 255, 255, .9), spreadRadius: 3),
              ]
            : null,
      ),
      child: ClipOval(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          minHeight: 0,
          maxWidth: w,
          maxHeight: w,
          child: Transform.translate(
            offset: Offset(-size * .09, -4),
            child: SizedBox(
              width: w,
              child: ExcludeSemantics(child: LenzJourneyRider(mood: mood)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top row of the capture screen: glass close, part title over step dots,
/// glass flash (gold bolt when on). Step dots: done = leaf, current = white
/// pill with halo, rest dim.
class LenzCaptureTopBar extends StatelessWidget {
  const LenzCaptureTopBar({
    super.key,
    required this.title,
    required this.step,
    required this.total,
    required this.onClose,
    required this.onFlash,
    required this.flashOn,
  });

  final String title;

  /// 1-based current step and the number of steps.
  final int step;
  final int total;
  final VoidCallback onClose;
  final VoidCallback onFlash;
  final bool flashOn;

  @override
  Widget build(BuildContext context) {
    final reduced = LenzMotion.reduced(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          LenzIconButton(
            icon: LenzIcons.x,
            dark: true,
            radius: 22,
            iconSize: 20,
            strokeWidth: 2.4,
            onTap: onClose,
            semanticLabel: 'Close',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LenzText.title.copyWith(
                    color: Colors.white,
                    fontSize: 17,
                    shadows: const [
                      Shadow(
                        color: Color.fromRGBO(0, 0, 0, .4),
                        blurRadius: 8,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                if (total > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Semantics(
                      label: 'Photo $step of $total',
                      child: ExcludeSemantics(
                        child: LayoutBuilder(
                          builder: (context, c) {
                            // 22px dots with 6px gaps, shrinking to fit many steps.
                            final avail = math.min(c.maxWidth, 240.0);
                            final w = math
                                .min(22.0, (avail - 6.0 * (total - 1)) / total)
                                .clamp(4.0, 22.0);
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < total; i++) ...[
                                  if (i > 0) const SizedBox(width: 6),
                                  AnimatedContainer(
                                    duration: reduced
                                        ? Duration.zero
                                        : const Duration(milliseconds: 300),
                                    width: w,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      color: i < step - 1
                                          ? LenzColors.leaf
                                          : i == step - 1
                                          ? Colors.white
                                          : const Color.fromRGBO(255, 255, 255, .28),
                                      boxShadow: i == step - 1
                                          ? const [
                                              BoxShadow(
                                                color: Color.fromRGBO(255, 255, 255, .2),
                                                spreadRadius: 3,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          LenzIconButton(
            icon: LenzIcons.bolt,
            dark: true,
            radius: 22,
            iconSize: 20,
            iconColor: flashOn ? LenzColors.gold2 : Colors.white,
            onTap: onFlash,
            semanticLabel: flashOn ? 'Flash on' : 'Flash off',
          ),
        ],
      ),
    );
  }
}
