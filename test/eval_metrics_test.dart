import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/models/authentication_result.dart';

import 'eval/eval_metrics.dart';

EvalScan s(String item, bool genuine, int repeat, Verdict v, {int conf = 80, String cat = 'WATCH'}) =>
    EvalScan(itemId: item, category: cat, genuine: genuine, repeat: repeat, rawVerdict: v, shownVerdict: v, confidence: conf);

void main() {
  test('metrics: false positives, flips, consistency and inconclusive rate', () {
    final scans = [
      // Genuine watch, flipping like engine v1 did.
      s('g1', true, 1, Verdict.likelyAuthentic),
      s('g1', true, 2, Verdict.likelyReplica),
      s('g1', true, 3, Verdict.likelyAuthentic),
      s('g1', true, 4, Verdict.inconclusive, conf: 50),
      // Replica, caught consistently.
      s('r1', false, 1, Verdict.likelyReplica, conf: 90),
      s('r1', false, 2, Verdict.likelyReplica, conf: 90),
      s('r1', false, 3, Verdict.likelyReplica, conf: 90),
      s('r1', false, 4, Verdict.inconclusive, conf: 45),
    ];
    final m = EvalMetrics.compute(scans);

    expect(m.falsePositiveRate, closeTo(0.25, 1e-9), reason: '1 of 4 genuine scans called replica');
    expect(m.recall, closeTo(0.75, 1e-9));
    expect(m.precision, closeTo(0.75, 1e-9));
    expect(m.inconclusiveRate, closeTo(0.25, 1e-9));
    expect(m.authenticReplicaFlipRate, closeTo(2 / 6, 1e-9), reason: 'g1 flipped twice in 3 transitions');
    expect(m.repeatScanConsistency, closeTo((2 / 4 + 3 / 4) / 2, 1e-9));
    expect(m.byCategory['WATCH']!.scans, 8);
  });

  test('a perfectly stable engine scores consistency 1 and flip rate 0', () {
    final scans = [for (var r = 1; r <= 10; r++) s('g', true, r, Verdict.likelyAuthentic)];
    final m = EvalMetrics.compute(scans);
    expect(m.repeatScanConsistency, 1.0);
    expect(m.authenticReplicaFlipRate, 0.0);
    expect(m.falsePositiveRate, 0.0);
  });
}
