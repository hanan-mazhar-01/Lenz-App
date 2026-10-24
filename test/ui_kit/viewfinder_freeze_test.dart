import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/models/capture_guide.dart';
import 'package:replica_detector/widgets/camera/capture_guide_overlay.dart';
import 'package:replica_detector/widgets/camera/lenz_camera_chrome.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: SizedBox(width: 300, height: 300, child: child));

  testWidgets('the viewfinder animates until the shutter locks it', (tester) async {
    await tester.pumpWidget(host(const LenzViewfinder()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.transientCallbackCount, greaterThan(0)); // sweeping

    await tester.pumpWidget(host(const LenzViewfinder(frozen: true)));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0); // locked: nothing moves
  });

  testWidgets('the capture guide stops breathing and sweeping when frozen', (tester) async {
    await tester.pumpWidget(host(const CaptureGuideOverlay(type: CaptureGuideType.watchFaceRound, animate: true)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(host(const CaptureGuideOverlay(type: CaptureGuideType.watchFaceRound, animate: true, frozen: true)));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
