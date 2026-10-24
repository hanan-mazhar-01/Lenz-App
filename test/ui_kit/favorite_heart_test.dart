import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/widgets/cards/animated_favorite_button.dart';
import 'package:replica_detector/widgets/ui/lenz_icons.dart';

void main() {
  Future<LenzIcon> pump(WidgetTester tester, bool fav) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(child: AnimatedFavoriteButton(isFavorite: fav, onToggle: () {})),
    ));
    return tester.widget<LenzIcon>(find.byType(LenzIcon));
  }

  testWidgets('a saved product shows a filled rose heart', (tester) async {
    final icon = await pump(tester, true);
    expect(icon.filled, isTrue);
    expect(icon.color, AnimatedFavoriteButton.heartColor);
  });

  testWidgets('an unsaved product shows only the outline', (tester) async {
    final icon = await pump(tester, false);
    expect(icon.filled, isFalse);
  });
}
