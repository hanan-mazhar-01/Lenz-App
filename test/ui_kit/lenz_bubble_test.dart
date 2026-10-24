import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/widgets/ui/lenz_bubble.dart';

void main() {
  testWidgets('bubble types its text out character by character', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: LenzBubble(text: 'Hi, I am Lenz!'))),
    ));
    // Before the typing delay nothing has been typed yet.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Hi, I am Lenz!', findRichText: true), findsNothing);

    // Part-way through: some but not all characters.
    await tester.pump(const Duration(milliseconds: 400));
    final partial = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.toPlainText())
        .join();
    expect(partial.isNotEmpty, isTrue);

    // Once done the full text is shown and the caret is gone.
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Hi, I am Lenz!', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bubble shows the full text at once with reduced motion', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: Center(child: LenzBubble(text: 'No animation please'))),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('No animation please', findRichText: true), findsOneWidget);
  });

  testWidgets('bubble stays within its max width at 320pt and large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: const Scaffold(
          body: Center(
            child: LenzBubble(
              text: 'Snap a few photos and I study the stitching, hardware and details.',
              typewriter: false,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(LenzBubble));
    expect(size.width, lessThanOrEqualTo(210.01));
  });
}
