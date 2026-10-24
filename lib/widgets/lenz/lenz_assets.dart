import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Placement of one PNG layer in the shared 1254x1254 artwork space.
@immutable
class LenzLayerRect {
  const LenzLayerRect(this.x, this.y, this.w, this.h);
  final double x, y, w, h;
  ui.Rect get rect => ui.Rect.fromLTWH(x, y, w, h);
}

/// Eye opening polygon (clip region) plus its bounding box `[x0, y0, x1, y1]`.
class LenzEyeOpening {
  LenzEyeOpening(this.path, this.bbox, [this.points = const []]);
  final ui.Path path;
  final List<double> bbox;

  /// Polygon vertices as x0,y0,x1,y1,... (empty when unknown).
  final List<double> points;

  /// The polygon rounded off with a closed Catmull-Rom spline: the artwork's
  /// opening is a coarse polygon whose facets show when zoomed in.
  late final ui.Path smooth = _smoothClosed(points) ?? path;
  double get x0 => bbox[0];
  double get y0 => bbox[1];
  double get x1 => bbox[2];
  double get y1 => bbox[3];
}

/// Parsed `meta.json` of a layer set.
class LenzMeta {
  LenzMeta({required this.layers, required this.openL, required this.openR});

  final Map<String, LenzLayerRect> layers;
  final LenzEyeOpening openL;
  final LenzEyeOpening openR;

  static LenzMeta parse(String jsonText) {
    final raw = json.decode(jsonText) as Map<String, dynamic>;
    final layers = <String, LenzLayerRect>{};
    late LenzEyeOpening openL, openR;
    raw.forEach((key, value) {
      final m = value as Map<String, dynamic>;
      if (m.containsKey('path')) {
        final bbox = (m['bbox'] as List).map((e) => (e as num).toDouble()).toList();
        final eye = LenzEyeOpening(parseSvgPolygon(m['path'] as String), bbox, parseSvgPoints(m['path'] as String));
        if (key == 'openL') openL = eye;
        if (key == 'openR') openR = eye;
      } else {
        double d(String k) => (m[k] as num).toDouble();
        layers[key] = LenzLayerRect(d('x'), d('y'), d('w'), d('h'));
      }
    });
    return LenzMeta(layers: layers, openL: openL, openR: openR);
  }
}

/// Parses an SVG path made only of M / L / Z commands with absolute coords.
ui.Path parseSvgPolygon(String d) {
  final path = ui.Path();
  final re = RegExp(r'([MLZmlz])|(-?\d+(?:\.\d+)?)');
  String cmd = 'M';
  final nums = <double>[];
  void flush() {
    for (var i = 0; i + 1 < nums.length; i += 2) {
      if (cmd == 'M' && i == 0) {
        path.moveTo(nums[i], nums[i + 1]);
      } else {
        path.lineTo(nums[i], nums[i + 1]);
      }
    }
    nums.clear();
  }

  for (final m in re.allMatches(d)) {
    final c = m.group(1);
    if (c != null) {
      flush();
      cmd = c.toUpperCase();
      if (cmd == 'Z') path.close();
    } else {
      nums.add(double.parse(m.group(2)!));
    }
  }
  flush();
  return path;
}

/// Global cache of the decoded Lenz layer images (character + splash icon
/// close-up). Load once with [ensureLoaded]; [isReady] is synchronous.
class LenzAssets {
  LenzAssets._();
  static final LenzAssets instance = LenzAssets._();

  static const String charDir = 'assets/lenz/character';
  static const String iconDir = 'assets/lenz/icon_closeup';
  static const List<String> charLayers = [
    'tail', 'body', 'head', 'browL', 'browR', 'irisL', 'irisR', 'lidL', 'lidR', 'mag', //
  ];
  static const List<String> iconLayers = ['base', 'irisL', 'irisR', 'lidL', 'lidR'];

  final Map<String, ui.Image> char = {};
  final Map<String, ui.Image> icon = {};
  LenzMeta? charMeta;
  LenzMeta? iconMeta;

  Future<void>? _charFuture;
  Future<void>? _iconFuture;
  bool _charReady = false;
  bool _iconReady = false;

  /// True when the character layers are decoded and usable.
  bool get isReady => _charReady;

  /// True when the splash icon close-up layers are decoded.
  bool get isIconReady => _iconReady;

  /// Loads the character layers (idempotent). Never throws; failures are
  /// logged and a later call retries.
  Future<void> ensureLoaded({AssetBundle? bundle}) {
    return _charFuture ??= _load(bundle ?? rootBundle, charDir, charLayers, char, (m) => charMeta = m)
        .then((ok) {
      _charReady = ok;
      if (!ok) _charFuture = null;
    });
  }

  /// Loads the icon close-up layers used by the splash (idempotent).
  Future<void> ensureIconLoaded({AssetBundle? bundle}) {
    return _iconFuture ??= _load(bundle ?? rootBundle, iconDir, iconLayers, icon, (m) => iconMeta = m)
        .then((ok) {
      _iconReady = ok;
      if (!ok) _iconFuture = null;
    });
  }

  /// Loads both sets.
  Future<void> ensureAllLoaded({AssetBundle? bundle}) =>
      Future.wait([ensureLoaded(bundle: bundle), ensureIconLoaded(bundle: bundle)]);

  Future<bool> _load(
    AssetBundle bundle,
    String dir,
    List<String> names,
    Map<String, ui.Image> into,
    void Function(LenzMeta) setMeta,
  ) async {
    try {
      final metaText = await bundle.loadString('$dir/meta.json', cache: false);
      final meta = LenzMeta.parse(metaText);
      final images = await Future.wait(names.map((n) => _decode(bundle, '$dir/$n.png')));
      for (var i = 0; i < names.length; i++) {
        into[names[i]] = images[i];
      }
      setMeta(meta);
      return true;
    } catch (e, st) {
      debugPrint('LenzAssets: failed to load $dir: $e\n$st');
      return false;
    }
  }

  static Future<ui.Image> _decode(AssetBundle bundle, String key) async {
    final data = await bundle.load(key);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}

/// Vertices of an M / L / Z polygon as x0,y0,x1,y1,...
List<double> parseSvgPoints(String d) {
  final nums = RegExp(r'-?\d+(?:\.\d+)?').allMatches(d).map((m) => double.parse(m.group(0)!)).toList();
  return nums.length.isEven ? nums : nums.sublist(0, nums.length - 1);
}

/// Closed Catmull-Rom spline through [pts] (x,y pairs); null if too few points.
ui.Path? _smoothClosed(List<double> pts) {
  final n = pts.length ~/ 2;
  if (n < 4) return null;
  ui.Offset at(int i) {
    final k = ((i % n) + n) % n;
    return ui.Offset(pts[k * 2], pts[k * 2 + 1]);
  }

  final path = ui.Path()..moveTo(at(0).dx, at(0).dy);
  for (var i = 0; i < n; i++) {
    final p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path..close();
}
