// Runs in its own isolate so the asset cache starts empty.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/widgets/lenz/lenz.dart';

void main() {
  testWidgets('renders a transparent box of the right aspect before assets load', (tester) async {
    expect(LenzAssets.instance.isReady, isFalse);
    await tester.pumpWidget(const Center(child: SizedBox(width: 200, child: LenzCharacter())));
    expect(tester.getSize(find.byType(LenzCharacter)).height, closeTo(200 * 1400 / 1180, 0.01));
    await tester.pumpWidget(const Center(child: SizedBox(width: 200, child: LenzCharacter(view: LenzView.peek))));
    expect(tester.getSize(find.byType(LenzCharacter)).height, closeTo(200 * 700 / 720, 0.01));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
