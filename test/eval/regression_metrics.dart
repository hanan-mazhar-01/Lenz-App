import 'package:replica_detector/models/authentication_result.dart';

/// Ground truth of an evaluation case.
enum Truth {
  genuine,
  counterfeit,

  /// Genuinely undecidable from the photos provided.
  inconclusive,

  /// No trustworthy label: reported, never scored.
  unlabeled;

  static Truth parse(String? s) => switch ((s ?? '').toUpperCase()) {
        'GENUINE' => Truth.genuine,
        'COUNTERFEIT' || 'REPLICA' => Truth.counterfeit,
        'INCONCLUSIVE' => Truth.inconclusive,
        _ => Truth.unlabeled,
      };
}

/// One case evaluated with k photos under one photo-selection strategy.
class CaseRun {
  final String caseId;
  final String strategy;
  final Truth truth;
  final int photos;
  final Verdict verdict;
  final bool sufficient;

  const CaseRun({
    required this.caseId,
    required this.strategy,
    required this.truth,
    required this.photos,
    required this.verdict,
    required this.sufficient,
  });

  bool get correct => switch (truth) {
        Truth.genuine => verdict == Verdict.likelyAuthentic,
        Truth.counterfeit => verdict == Verdict.likelyReplica,
        Truth.inconclusive => verdict == Verdict.inconclusive,
        Truth.unlabeled => false,
      };

  Map<String, dynamic> toJson() => {
        'case': caseId,
        'strategy': strategy,
        'truth': truth.name,
        'photos': photos,
        'verdict': verdict.code,
        'sufficient': sufficient,
      };
}

/// §10 metrics over labelled runs. Unlabelled cases are excluded.
class RegressionMetrics {
  final int labelled;
  final int genuine;
  final int counterfeit;
  final double accuracy;

  /// Counterfeits called authentic (the most damaging error for buyers).
  final double falseAuthenticRate;

  /// Genuine items called replica (the most damaging error for owners).
  final double falseReplicaRate;
  final double inconclusiveRate;

  const RegressionMetrics({
    required this.labelled,
    required this.genuine,
    required this.counterfeit,
    required this.accuracy,
    required this.falseAuthenticRate,
    required this.falseReplicaRate,
    required this.inconclusiveRate,
  });

  static RegressionMetrics compute(Iterable<CaseRun> runs) {
    final l = runs.where((r) => r.truth != Truth.unlabeled).toList();
    final g = l.where((r) => r.truth == Truth.genuine).toList();
    final c = l.where((r) => r.truth == Truth.counterfeit).toList();
    double rate(int n, int d) => d == 0 ? 0 : n / d;
    return RegressionMetrics(
      labelled: l.length,
      genuine: g.length,
      counterfeit: c.length,
      accuracy: rate(l.where((r) => r.correct).length, l.length),
      falseAuthenticRate: rate(c.where((r) => r.verdict == Verdict.likelyAuthentic).length, c.length),
      falseReplicaRate: rate(g.where((r) => r.verdict == Verdict.likelyReplica).length, g.length),
      inconclusiveRate: rate(l.where((r) => r.verdict == Verdict.inconclusive).length, l.length),
    );
  }

  Map<String, dynamic> toJson() => {
        'labelled_runs': labelled,
        'genuine_runs': genuine,
        'counterfeit_runs': counterfeit,
        'accuracy': double.parse(accuracy.toStringAsFixed(3)),
        'false_authentic_rate': double.parse(falseAuthenticRate.toStringAsFixed(3)),
        'false_replica_rate': double.parse(falseReplicaRate.toStringAsFixed(3)),
        'inconclusive_rate': double.parse(inconclusiveRate.toStringAsFixed(3)),
      };
}
