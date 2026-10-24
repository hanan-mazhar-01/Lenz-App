import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/core/theme/lenz_page_transitions.dart';
import 'package:replica_detector/widgets/ui/lenz_stagger.dart';

double _opacityOf(WidgetTester tester) {
  final o = tester.widgetList<Opacity>(find.descendant(of: find.byType(LenzRise), matching: find.byType(Opacity)));
  return o.isEmpty ? 1 : o.first.opacity;
}

void main() {
  testWidgets('a rise on its own fades in', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LenzRise(child: Text('hi'))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_opacityOf(tester), lessThan(1));
    await tester.pump(const Duration(seconds: 2));
    expect(_opacityOf(tester), 1);
  });

  testWidgets('no second animation inside a tab host (always)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LenzEntranceScope(always: true, child: LenzRise(child: Text('hi'))),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_opacityOf(tester), 1);
  });

  testWidgets('no second animation while the page transition plays', (tester) async {
    final c = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 500));
    addTearDown(c.dispose);
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      }),
    ));
    c.forward();
    await tester.pumpWidget(MaterialApp(
      home: LenzTransitions.build(
        context: ctx,
        animation: c,
        secondaryAnimation: kAlwaysDismissedAnimation,
        kind: LenzRouteKind.modalUp,
        child: const LenzRise(child: Text('hi')),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_opacityOf(tester), 1);
    c.stop();
  });

  testWidgets('a rise mounted after the transition finished still plays', (tester) async {
    final done = AnimationController(vsync: const TestVSync(), value: 1);
    addTearDown(done.dispose);
    await tester.pumpWidget(MaterialApp(
      home: LenzEntranceScope(animation: done, child: const LenzRise(child: Text('hi'))),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_opacityOf(tester), lessThan(1));
    await tester.pump(const Duration(seconds: 2));
  });
}
