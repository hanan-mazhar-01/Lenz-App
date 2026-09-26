import 'dart:math';

import 'package:replica_detector/models/authentication_result.dart';

/// One scored scan of a labelled item in the evaluation dataset.
class EvalScan {
  final String itemId;
  final String category;

  /// Ground truth: true = genuine, false = replica.
  final bool genuine;
  final int repeat;

  /// Verdict from this scan's evidence alone.
  final Verdict rawVerdict;

  /// Verdict after repeat-scan consistency (what the user would see).
  final Verdict shownVerdict;
  final int confidence;

  const EvalScan({
    required this.itemId,
    required this.category,
    required this.genuine,
    required this.repeat,
    required this.rawVerdict,
    required this.shownVerdict,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'item': itemId,
        'category': category,
        'truth': genuine ? 'GENUINE' : 'REPLICA',
        'repeat': repeat,
        'raw': rawVerdict.code,
        'shown': shownVerdict.code,
        'confidence': confidence,
      };
}

/// §33 metrics. "Positive" = the engine says LIKELY_REPLICA.
class EvalMetrics {
  final int scans;
  final int genuineScans;
  final int replicaScans;

  /// Genuine items called LIKELY_REPLICA. The most damaging error.
  final double falsePositiveRate;

  /// Replicas NOT called LIKELY_REPLICA (includes inconclusive).
  final double falseNegativeRate;

  /// Replicas called LIKELY_AUTHENTIC. The other serious error.
  final double replicaPassedAsAuthenticRate;
  final double precision;
  final double recall;
  final double inconclusiveRate;

  /// Share of repeats of one item that agree with its most common verdict,
  /// averaged over items. 1.0 = every item got the same verdict every time.
  final double repeatScanConsistency;

  /// Share of consecutive repeats of one item that flip directly between
  /// LIKELY_AUTHENTIC and LIKELY_REPLICA. Target: 0.
  final double authenticReplicaFlipRate;

  /// Mean |confidence - accuracy| over decisive verdicts, by 10-point bucket.
  final double expectedCalibrationError;
  final Map<String, EvalMetrics> byCategory;

  const EvalMetrics({
    required this.scans,
    required this.genuineScans,
    required this.replicaScans,
    required this.falsePositiveRate,
    required this.falseNegativeRate,
    required this.replicaPassedAsAuthenticRate,
    required this.precision,
    required this.recall,
    required this.inconclusiveRate,
    required this.repeatScanConsistency,
    required this.authenticReplicaFlipRate,
    required this.expectedCalibrationError,
    this.byCategory = const {},
  });

  static EvalMetrics compute(List<EvalScan> all, {bool shown = true, bool perCategory = true}) {
    Verdict v(EvalScan s) => shown ? s.shownVerdict : s.rawVerdict;
    double ratio(int a, int b) => b == 0 ? 0 : a / b;

    final genuine = all.where((s) => s.genuine).toList();
    final replica = all.where((s) => !s.genuine).toList();
    final tp = replica.where((s) => v(s) == Verdict.likelyReplica).length;
    final fp = genuine.where((s) => v(s) == Verdict.likelyReplica).length;
    final fn = replica.length - tp;

    // Repeat-scan consistency and flips, per item in repeat order.
    final byItem = <String, List<EvalScan>>{};
    for (final s in all) {
      byItem.putIfAbsent(s.itemId, () => []).add(s);
    }
    var consistencySum = 0.0;
    var flips = 0, transitions = 0;
    for (final scans in byItem.values) {
      scans.sort((a, b) => a.repeat.compareTo(b.repeat));
      final counts = <Verdict, int>{};
      for (final s in scans) {
        counts[v(s)] = (counts[v(s)] ?? 0) + 1;
      }
      consistencySum += counts.values.reduce(max) / scans.length;
      for (var i = 1; i < scans.length; i++) {
        transitions++;
        final pair = {v(scans[i - 1]), v(scans[i])};
        if (pair.containsAll({Verdict.likelyAuthentic, Verdict.likelyReplica})) flips++;
      }
    }

    // Calibration over decisive verdicts: does "80%" mean right 80% of the time?
    final buckets = <int, List<(double, bool)>>{};
    for (final s in all) {
      final verdict = v(s);
      if (verdict == Verdict.inconclusive) continue;
      final correct = (verdict == Verdict.likelyReplica) != s.genuine;
      buckets.putIfAbsent((s.confidence ~/ 10).clamp(0, 9), () => []).add((s.confidence / 100, correct));
    }
    var ece = 0.0;
    final decisive = buckets.values.fold<int>(0, (n, b) => n + b.length);
    for (final b in buckets.values) {
      final conf = b.map((e) => e.$1).reduce((a, c) => a + c) / b.length;
      final acc = b.where((e) => e.$2).length / b.length;
      ece += (b.length / max(1, decisive)) * (conf - acc).abs();
    }

    return EvalMetrics(
      scans: all.length,
      genuineScans: genuine.length,
      replicaScans: replica.length,
      falsePositiveRate: ratio(fp, genuine.length),
      falseNegativeRate: ratio(fn, replica.length),
      replicaPassedAsAuthenticRate: ratio(replica.where((s) => v(s) == Verdict.likelyAuthentic).length, replica.length),
      precision: ratio(tp, tp + fp),
      recall: ratio(tp, replica.length),
      inconclusiveRate: ratio(all.where((s) => v(s) == Verdict.inconclusive).length, all.length),
      repeatScanConsistency: byItem.isEmpty ? 0 : consistencySum / byItem.length,
      authenticReplicaFlipRate: ratio(flips, transitions),
      expectedCalibrationError: ece,
      byCategory: !perCategory
          ? const {}
          : {
              for (final c in all.map((s) => s.category).toSet())
                c: compute(all.where((s) => s.category == c).toList(), shown: shown, perCategory: false),
            },
    );
  }

  Map<String, dynamic> toJson() => {
        'scans': scans,
        'genuine_scans': genuineScans,
        'replica_scans': replicaScans,
        'false_positive_rate_genuine_called_replica': _r(falsePositiveRate),
        'false_negative_rate_replica_not_caught': _r(falseNegativeRate),
        'replica_passed_as_authentic_rate': _r(replicaPassedAsAuthenticRate),
        'precision': _r(precision),
        'recall': _r(recall),
        'inconclusive_rate': _r(inconclusiveRate),
        'repeat_scan_consistency': _r(repeatScanConsistency),
        'authentic_replica_flip_rate': _r(authenticReplicaFlipRate),
        'expected_calibration_error': _r(expectedCalibrationError),
        if (byCategory.isNotEmpty) 'by_category': byCategory.map((k, m) => MapEntry(k, m.toJson())),
      };

  static double _r(double x) => (x * 1000).round() / 1000;
}
