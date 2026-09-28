import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/models/product_reference.dart';

import 'support/fixtures.dart';

void main() {
  final checklist = ProductReference.checklist(appleWatch());

  test('the checklist comes from the profile, one item per checkpoint', () {
    expect(checklist.claims.map((c) => c.id), everyElement(startsWith('b')));
    expect(checklist.claims.length, appleWatch().profile.checkpoints.length);
    expect(checklist.claims.every((c) => c.checkpointId != null), isTrue);
  });

  test('catalog-decisive parts are marked, device screens are SOFTWARE', () {
    final back = checklist.claims.firstWhere((c) => c.checkpointId == 'aw_back_material');
    expect(back.decisiveIfDifferent, isTrue);
    expect(checklist.claims.firstWhere((c) => c.checkpointId == 'aw_device_info').kind, 'SOFTWARE');
  });

  test('items without a documented genuine detail say what to check', () {
    final undocumented = checklist.claims.where((c) => !c.documented).toList();
    expect(undocumented, isNotEmpty);
    expect(undocumented.first.detail, startsWith('What to check:'));
  });

  test('the report sentence never claims manufacturer verification', () {
    expect(ProductReference.basisSentence, contains("Gemini's own knowledge"));
    expect(ProductReference.basisSentence, contains('not a verification by the manufacturer'));
  });

  test('serialises for the analysis log', () {
    expect((checklist.toJson()['claims'] as List).length, checklist.claims.length);
  });
}
