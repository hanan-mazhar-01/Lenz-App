import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:replica_detector/widgets/lenz/lenz.dart';

/// Loads the Nunito Black face so FX text renders with the real font.
Future<void> loadNunito() async {
  final f = File('assets/fonts/Nunito-Black.ttf');
  if (!f.existsSync()) return;
  final loader = FontLoader('Nunito')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

/// Renders [rig] with [view] into an image of [width] logical px.
Future<ui.Image> renderRig(LenzRig rig, LenzView view, {double width = 600, bool fx = true, bool shadow = false}) async {
  final size = ui.Size(width, width / view.aspectRatio);
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  LenzPainter(rig: rig, cache: LenzPaintCache(), view: view, fx: fx, shadow: shadow).paint(canvas, size);
  final pic = rec.endRecording();
  return pic.toImage(size.width.round(), size.height.round());
}

Future<Uint8List> rgba(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bd!.buffer.asUint8List();
}

Future<void> writePng(ui.Image img, String path) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  final f = File(path)..parent.createSync(recursive: true);
  f.writeAsBytesSync(bd!.buffer.asUint8List());
}

/// Advances [rig] by [seconds] in 16 ms frames.
void settle(LenzRig rig, double seconds) {
  for (var t = 0.0; t < seconds; t += 0.016) {
    rig.advance(0.016);
  }
}
