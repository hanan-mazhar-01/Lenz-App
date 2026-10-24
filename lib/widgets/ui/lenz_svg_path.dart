import 'dart:ui';

/// Minimal SVG path-data parser (`M m L l H h V v C c S s Q q T t A a Z z`),
/// producing a Flutter [Path] in the SVG's own coordinate system.
///
/// Used by `LenzIcon` so the prototype's stroke icons can be ported verbatim
/// from `core.js` without bundling SVG assets.
Path parseSvgPathData(String data) {
  final p = _Parser(data);
  final path = Path();
  var x = 0.0, y = 0.0; // current point
  var sx = 0.0, sy = 0.0; // sub-path start
  var lcx = 0.0, lcy = 0.0; // last control point (for S / T)
  var cmd = '';
  var prev = '';

  while (true) {
    p.skipSeparators();
    if (p.done) break;
    if (p.atCommand) {
      cmd = p.readCommand();
    } else if (cmd.isEmpty || cmd == 'z' || cmd == 'Z') {
      throw FormatException('Unexpected number in path data', data, p.index);
    } else if (cmd == 'M') {
      cmd = 'L';
    } else if (cmd == 'm') {
      cmd = 'l';
    }

    final rel = cmd.toLowerCase() == cmd;
    switch (cmd.toLowerCase()) {
      case 'm':
        var nx = p.number(), ny = p.number();
        if (rel) {
          nx += x;
          ny += y;
        }
        path.moveTo(nx, ny);
        x = sx = nx;
        y = sy = ny;
      case 'l':
        var nx = p.number(), ny = p.number();
        if (rel) {
          nx += x;
          ny += y;
        }
        path.lineTo(nx, ny);
        x = nx;
        y = ny;
      case 'h':
        var nx = p.number();
        if (rel) nx += x;
        path.lineTo(nx, y);
        x = nx;
      case 'v':
        var ny = p.number();
        if (rel) ny += y;
        path.lineTo(x, ny);
        y = ny;
      case 'c':
        var x1 = p.number(), y1 = p.number();
        var x2 = p.number(), y2 = p.number();
        var nx = p.number(), ny = p.number();
        if (rel) {
          x1 += x;
          y1 += y;
          x2 += x;
          y2 += y;
          nx += x;
          ny += y;
        }
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        lcx = x2;
        lcy = y2;
        x = nx;
        y = ny;
      case 's':
        var x2 = p.number(), y2 = p.number();
        var nx = p.number(), ny = p.number();
        if (rel) {
          x2 += x;
          y2 += y;
          nx += x;
          ny += y;
        }
        final smooth = 'cs'.contains(prev.toLowerCase()) && prev.isNotEmpty;
        final x1 = smooth ? 2 * x - lcx : x;
        final y1 = smooth ? 2 * y - lcy : y;
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        lcx = x2;
        lcy = y2;
        x = nx;
        y = ny;
      case 'q':
        var x1 = p.number(), y1 = p.number();
        var nx = p.number(), ny = p.number();
        if (rel) {
          x1 += x;
          y1 += y;
          nx += x;
          ny += y;
        }
        path.quadraticBezierTo(x1, y1, nx, ny);
        lcx = x1;
        lcy = y1;
        x = nx;
        y = ny;
      case 't':
        var nx = p.number(), ny = p.number();
        if (rel) {
          nx += x;
          ny += y;
        }
        final smooth = 'qt'.contains(prev.toLowerCase()) && prev.isNotEmpty;
        final x1 = smooth ? 2 * x - lcx : x;
        final y1 = smooth ? 2 * y - lcy : y;
        path.quadraticBezierTo(x1, y1, nx, ny);
        lcx = x1;
        lcy = y1;
        x = nx;
        y = ny;
      case 'a':
        final rx = p.number().abs(), ry = p.number().abs();
        final rot = p.number();
        final large = p.flag(), sweep = p.flag();
        var nx = p.number(), ny = p.number();
        if (rel) {
          nx += x;
          ny += y;
        }
        if (rx == 0 || ry == 0) {
          path.lineTo(nx, ny);
        } else if (nx != x || ny != y) {
          path.arcToPoint(
            Offset(nx, ny),
            radius: Radius.elliptical(rx, ry),
            rotation: rot,
            largeArc: large,
            clockwise: sweep,
          );
        }
        x = nx;
        y = ny;
      case 'z':
        path.close();
        x = sx;
        y = sy;
      default:
        throw FormatException('Unknown path command "$cmd"', data, p.index);
    }
    prev = cmd;
  }
  return path;
}

class _Parser {
  _Parser(this.s);
  final String s;
  int index = 0;

  bool get done => index >= s.length;

  static bool _isSep(int c) => c == 0x20 || c == 0x2C || c == 0x0A || c == 0x09 || c == 0x0D;

  void skipSeparators() {
    while (index < s.length && _isSep(s.codeUnitAt(index))) {
      index++;
    }
  }

  bool get atCommand {
    final c = s.codeUnitAt(index);
    // letters except exponent markers can never start a number.
    return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  }

  String readCommand() => s[index++];

  double number() {
    skipSeparators();
    final start = index;
    if (index < s.length && (s[index] == '-' || s[index] == '+')) index++;
    var digits = 0;
    while (index < s.length && _isDigit(s.codeUnitAt(index))) {
      index++;
      digits++;
    }
    if (index < s.length && s[index] == '.') {
      index++;
      while (index < s.length && _isDigit(s.codeUnitAt(index))) {
        index++;
        digits++;
      }
    }
    if (digits == 0) {
      throw FormatException('Expected a number', s, start);
    }
    if (index < s.length && (s[index] == 'e' || s[index] == 'E')) {
      final save = index;
      index++;
      if (index < s.length && (s[index] == '-' || s[index] == '+')) index++;
      var expDigits = 0;
      while (index < s.length && _isDigit(s.codeUnitAt(index))) {
        index++;
        expDigits++;
      }
      if (expDigits == 0) index = save;
    }
    return double.parse(s.substring(start, index));
  }

  /// Arc flags are single characters and may be written without separators.
  bool flag() {
    skipSeparators();
    if (index >= s.length) throw FormatException('Expected a flag', s, index);
    final c = s[index++];
    if (c == '0') return false;
    if (c == '1') return true;
    throw FormatException('Invalid arc flag "$c"', s, index - 1);
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
}
