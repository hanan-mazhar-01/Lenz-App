import 'package:flutter/widgets.dart';

import '../../core/theme/lenz_colors.dart';
import 'lenz_svg_path.dart';

/// Names of the prototype's `IC` icon set (24px viewBox, stroke 2, round caps
/// and joins). Use with [LenzIcon].
abstract final class LenzIcons {
  static const home = 'home';
  static const camera = 'camera';
  static const clock = 'clock';
  static const heart = 'heart';
  static const user = 'user';
  static const search = 'search';
  static const chevR = 'chev-r';
  static const chevL = 'chev-l';
  static const chevD = 'chev-d';
  static const check = 'check';
  static const x = 'x';
  static const plus = 'plus';
  static const shield = 'shield';
  static const shieldOk = 'shield-ok';
  static const sparkles = 'sparkles';
  static const bolt = 'bolt';
  static const bell = 'bell';
  static const lock = 'lock';
  static const mail = 'mail';
  static const eye = 'eye';
  static const eyeOff = 'eye-off';
  static const help = 'help';
  static const file = 'file';
  static const trash = 'trash';
  static const logout = 'logout';
  static const refresh = 'refresh';
  static const image = 'image';
  static const info = 'info';
  static const warn = 'warn';
  static const star = 'star';
  static const crown = 'crown';
  static const gift = 'gift';
  static const share = 'share';
  static const face = 'face';
  static const vibrate = 'vibrate';
  static const cloud = 'cloud';
  static const layers = 'layers';
  static const scan = 'scan';
  static const grid = 'grid';
  static const edit = 'edit';
  static const apple = 'apple';
  static const gicon = 'gicon';
  static const bag = 'bag';
  static const tip = 'tip';
  static const zap = 'zap';

  /// Every icon name, in prototype order.
  static List<String> get all => List.unmodifiable(_defs.keys);
}

/// A stroke icon from the Lenz icon set.
///
/// [strokeWidth] is expressed in 24px viewBox units like the SVG attribute,
/// so a 22px icon with stroke 2 draws a 1.83px line.
class LenzIcon extends StatelessWidget {
  const LenzIcon(
    this.name, {
    super.key,
    this.size,
    this.strokeWidth = 2,
    this.color,
    this.semanticLabel,
    this.filled = false,
  });

  final String name;
  final double? size;
  final double strokeWidth;
  final Color? color;

  /// Also fills the icon's shapes with [color] (e.g. a saved heart).
  final bool filled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final s = size ?? iconTheme.size ?? 22;
    final c = color ?? iconTheme.color ?? LenzColors.ink;
    Widget icon = SizedBox.square(
      dimension: s,
      child: CustomPaint(
        painter: _IconPainter(name, c, strokeWidth, filled),
      ),
    );
    icon = semanticLabel == null
        ? ExcludeSemantics(child: icon)
        : Semantics(label: semanticLabel, image: true, child: icon);
    return icon;
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.name, this.color, this.strokeWidth, this.filled);
  final String name;
  final bool filled;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final shapes = _built(name);
    if (shapes == null) return;
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    for (final s in shapes) {
      if (filled || s.fill != null || s.fillCurrent) {
        canvas.drawPath(s.path, fill..color = s.fill ?? color);
      }
      if (s.stroke) canvas.drawPath(s.path, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.name != name ||
      old.color != color ||
      old.filled != filled ||
      old.strokeWidth != strokeWidth;
}

// ---------------------------------------------------------------------------
// Icon data, ported 1:1 from `IC` in prototype_src/core.js.
// ---------------------------------------------------------------------------

class _Shape {
  _Shape(this.path, {this.fill, this.fillCurrent = false, this.stroke = true});
  final Path path;
  final Color? fill;
  final bool fillCurrent;
  final bool stroke;
}

final Map<String, List<_Shape>> _cache = {};

List<_Shape>? _built(String name) {
  final cached = _cache[name];
  if (cached != null) return cached;
  final def = _defs[name];
  if (def == null) return null;
  return _cache[name] = [for (final b in def) b()];
}

/// Parses an icon's shapes (exposed for tests).
List<Path> lenzIconPaths(String name) =>
    [for (final s in _built(name) ?? const <_Shape>[]) s.path];

_Shape Function() _p(String d, {Color? fill, bool current = false, bool stroke = true}) =>
    () => _Shape(parseSvgPathData(d), fill: fill, fillCurrent: current, stroke: stroke);

_Shape Function() _circle(double cx, double cy, double r) => () =>
    _Shape(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)));

_Shape Function() _rect(double x, double y, double w, double h, double rx) => () =>
    _Shape(Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(rx))));

final Map<String, List<_Shape Function()>> _defs = {
  'home': [_p('M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z')],
  'camera': [
    _p('M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z'),
    _circle(12, 13.5, 3.8),
  ],
  'clock': [_circle(12, 12, 9), _p('M12 7v5l3 2')],
  'heart': [
    _p('M12 20s-7.5-4.6-9.2-9.2C1.6 7.4 3.7 4 7 4c2 0 3.4 1.1 5 3 1.6-1.9 3-3 5-3 3.3 0 5.4 3.4 4.2 6.8C19.5 15.4 12 20 12 20z'),
  ],
  'user': [_circle(12, 8, 4), _p('M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7')],
  'search': [_circle(11, 11, 7), _p('m20 20-3.5-3.5')],
  'chev-r': [_p('m9 6 6 6-6 6')],
  'chev-l': [_p('m15 6-6 6 6 6')],
  'chev-d': [_p('m6 9 6 6 6-6')],
  'check': [_p('m5 12.5 4.5 4.5L19 7.5')],
  'x': [_p('M6 6l12 12M18 6 6 18')],
  'plus': [_p('M12 5v14M5 12h14')],
  'shield': [_p('M12 3 4.5 6v5.5c0 4.6 3 8 7.5 9.5 4.5-1.5 7.5-4.9 7.5-9.5V6z')],
  'shield-ok': [
    _p('M12 3 4.5 6v5.5c0 4.6 3 8 7.5 9.5 4.5-1.5 7.5-4.9 7.5-9.5V6z'),
    _p('m9 12 2.2 2.2L15.5 10'),
  ],
  'sparkles': [
    _p('M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8z'),
    _p('M19 15l.8 2 2 .8-2 .8L19 21l-.8-2.4-2-.8 2-.8z'),
  ],
  'bolt': [_p('M13 3 5 13.5h6L10 21l8-10.5h-6z')],
  'bell': [_p('M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15z'), _p('M10 21h4')],
  'lock': [_rect(5, 10.5, 14, 10, 2.5), _p('M8 10.5V8a4 4 0 0 1 8 0v2.5')],
  'mail': [_rect(3, 5, 18, 14, 3), _p('m4 7 8 6 8-6')],
  'eye': [
    _p('M2 12s3.6-6.5 10-6.5S22 12 22 12s-3.6 6.5-10 6.5S2 12 2 12z'),
    _circle(12, 12, 3),
  ],
  'eye-off': [
    _p('M3 3l18 18'),
    _p('M10.6 6A9.7 9.7 0 0 1 12 5.5c6.4 0 10 6.5 10 6.5a17 17 0 0 1-3.2 4M6.6 7.6A17 17 0 0 0 2 12s3.6 6.5 10 6.5c1.5 0 2.8-.3 4-.8'),
  ],
  'help': [
    _circle(12, 12, 9),
    _p('M9.5 9.3a2.6 2.6 0 0 1 5 .9c0 1.7-2.5 2-2.5 3.6M12 17h.01'),
  ],
  'file': [
    _p('M7 3h7l5 5v12a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z'),
    _p('M14 3v5h5M9 13h6M9 17h6'),
  ],
  'trash': [_p('M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3')],
  'logout': [_p('M10 4H5a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h5M15 8l4 4-4 4M19 12H9')],
  'refresh': [_p('M20 11a8 8 0 0 0-14.5-4M4 4v4h4M4 13a8 8 0 0 0 14.5 4M20 20v-4h-4')],
  'image': [
    _rect(3, 4, 18, 16, 3),
    _circle(9, 10, 1.8),
    _p('m4 18 5-5 4 4 3-3 4 4'),
  ],
  'info': [_circle(12, 12, 9), _p('M12 11v6M12 7.5h.01')],
  'warn': [
    _p('M12 4 2.8 19.5a1 1 0 0 0 .9 1.5h16.6a1 1 0 0 0 .9-1.5z'),
    _p('M12 10v4.5M12 17.5h.01'),
  ],
  'star': [_p('m12 3 2.6 5.6 6.1.7-4.5 4.2 1.2 6L12 16.5 6.6 19.5l1.2-6L3.3 9.3l6.1-.7z')],
  'crown': [_p('m3 8 4.5 4L12 5l4.5 7L21 8l-2 11H5z')],
  'gift': [
    _rect(3, 9, 18, 12, 2),
    _p('M12 9v12M3 13h18M12 9c-3 0-5-1-5-3s3-3 5 0c2-3 5-2 5 0s-2 3-5 3z'),
  ],
  'share': [_p('M12 15V4M8 8l4-4 4 4M5 13v6a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-6')],
  'face': [
    _p('M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2M9 10v1.5M15 10v1.5M9.5 15.5c1.4 1.2 3.6 1.2 5 0'),
  ],
  'vibrate': [_rect(8, 3, 8, 18, 2), _p('M4 8v8M20 8v8')],
  'cloud': [_p('M7 18a4.5 4.5 0 0 1-.5-9A6 6 0 0 1 18 9.5 4 4 0 0 1 17.5 18z')],
  'layers': [_p('m12 3 9 5-9 5-9-5z'), _p('m3 13 9 5 9-5')],
  'scan': [
    _p('M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2M4 12h16'),
  ],
  'grid': [
    _rect(4, 4, 7, 7, 2),
    _rect(13, 4, 7, 7, 2),
    _rect(4, 13, 7, 7, 2),
    _rect(13, 13, 7, 7, 2),
  ],
  'edit': [_p('M4 20h4L19 9l-4-4L4 16z'), _p('m13.5 6.5 4 4')],
  'apple': [
    _p('M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z',
        current: true, stroke: false),
  ],
  'gicon': [
    _p('M21 12.2c0-.7-.1-1.300-.2-1.900H12v3.600h5.100a4.400 4.400 0 0 1-1.900 2.900v2.400h3.100c1.800-1.700 2.700-4.100 2.700-7z',
        fill: const Color(0xFF4285F4), stroke: false),
    _p('M12 21.500c2.600 0 4.700-.9 6.300-2.300l-3.100-2.400c-.9.600-1.900.9-3.200.9-2.400 0-4.500-1.600-5.200-3.800H3.600v2.500A9.500 9.500 0 0 0 12 21.500z',
        fill: const Color(0xFF34A853), stroke: false),
    _p('M6.800 13.900a5.700 5.700 0 0 1 0-3.700V7.700H3.600a9.500 9.500 0 0 0 0 8.600z',
        fill: const Color(0xFFFBBC05), stroke: false),
    _p('M12 6.300c1.400 0 2.600.5 3.600 1.400l2.700-2.700A9.500 9.500 0 0 0 3.600 7.700l3.200 2.500C7.500 7.900 9.600 6.300 12 6.300z',
        fill: const Color(0xFFEA4335), stroke: false),
  ],
  'bag': [_p('M5 8h14l1 12H4z'), _p('M9 8V6.500a3 3 0 0 1 6 0V8')],
  'tip': [
    _p('M9 18h6M10 21h4M12 3a6 6 0 0 0-3.500 10.900c.6.5 1 1.200 1 2V16h5v-.1c0-.8.4-1.500 1-2A6 6 0 0 0 12 3z'),
  ],
  'zap': [_p('M13 3 5 13.5h6L10 21l8-10.5h-6z')],
};
