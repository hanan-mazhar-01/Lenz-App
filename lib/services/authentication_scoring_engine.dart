import '../data/authentication_rules.dart';
import '../data/reference_library.dart';
import '../models/authentication_result.dart';
import '../models/evidence.dart';
import '../models/evidence_observation.dart';
import '../models/product.dart';

class ScoringEngineResult {
  final Verdict verdict;
  final int authenticationConfidence;
  final int identificationConfidence;
  final String evidenceCoverageText;
  final int coveredCount;
  final int totalCount;
  final double weightedCoverage;
  final double criticalCoverage;
  final List<String> quickSummaryPoints;
  final List<String> positiveFindings;
  final List<String> suspiciousFindings;
  final List<String> unclearFindings;
  final List<String> missingEvidenceDescriptions;
  final List<String> contradictionDescriptions;
  final List<String> nextChecks;
  final List<EvidenceItem> scoredEvidenceItems;
  final String rationale;

  const ScoringEngineResult({
    required this.verdict,
    required this.authenticationConfidence,
    required this.identificationConfidence,
    required this.evidenceCoverageText,
    required this.coveredCount,
    required this.totalCount,
    required this.weightedCoverage,
    required this.criticalCoverage,
    required this.quickSummaryPoints,
    required this.positiveFindings,
    required this.suspiciousFindings,
    required this.unclearFindings,
    required this.missingEvidenceDescriptions,
    required this.contradictionDescriptions,
    required this.nextChecks,
    required this.scoredEvidenceItems,
    required this.rationale,
  });
}

/// Pure local scoring. The vision model supplies observations; this engine
/// decides. A model's own confidence is never used as the authenticity
/// score (§22), and the engine prefers INCONCLUSIVE to unsupported
/// confidence (§23, §55).
abstract final class AuthenticationScoringEngine {
  /// Gates that must all hold before "Likely Authentic" is reachable (§55).
  static const double _minWeightedCoverageForAuthentic = 0.75;
  static const int _minPhotoQualityForAuthentic = 65;
  static const int _minUsefulnessForAuthentic = 60;
  static const int _minIdentificationForAuthentic = 60;
  static const int _minConsistentSignalsForAuthentic = 4;
  static const int _minAcceptedAnglesForAuthentic = 3;

  /// No path ever reaches 100% — certainty is not available from photographs (§24).
  static const int _authenticCeiling = 94;
  static const int _replicaCeiling = 94;

  static ScoringEngineResult evaluate({
    required Product product,
    required int rawIdentificationConfidence,
    required List<EvidenceItem> requiredEvidence,
    required Map<String, String> capturedImages,
    required List<PartObservation> observations,
    required List<CrossImageContradiction> contradictions,
    AuthenticationRuleSet? rules,
    ProductReference? reference,
    bool hasModelReference = false,
  }) {
    final ruleSet = rules ??
        AuthenticationRules.resolve(
          category: product.category,
          brand: product.brand,
          model: product.model,
        );

    final observationMap = {for (final o in observations) o.evidenceId.toLowerCase(): o};

    // -------------------------------------------------------------------
    // 1. Weighted evidence coverage
    // -------------------------------------------------------------------
    double totalWeight = 0;
    double coveredWeight = 0;
    double criticalTotal = 0;
    double criticalCovered = 0;
    int coveredCount = 0;

    final missingDescriptions = <String>[];
    final scoredItems = <EvidenceItem>[];

    // -------------------------------------------------------------------
    // 2. Per-item scoring from observations, weighted by importance
    // -------------------------------------------------------------------
    final positives = <String>[];
    final suspicious = <String>[];
    final unclear = <String>[];

    double weightedConsistent = 0;
    double weightedInconsistent = 0;
    int criticalInconsistencies = 0;
    int distinctConsistentSignals = 0;
    int acceptedAngles = 0;

    /// Critical angles that were supplied but produced no confirming signal —
    /// the check was requested, attempted, and still not actually performed.
    int criticalUnverified = 0;

    /// Photos the user chose to keep after the app flagged them as too poor
    /// to inspect reliably (§50).
    int keptLowQualityCount = 0;

    final qualityScores = <int>[];
    final usefulnessScores = <int>[];

    PartObservation? findObservation(EvidenceItem item) {
      final direct = observationMap[item.id.toLowerCase()];
      if (direct != null) return direct;

      final itemId = item.id.toLowerCase();
      final itemTitle = item.title.toLowerCase();

      for (final o in observations) {
        final oId = o.evidenceId.toLowerCase();
        final oTitle = o.title.toLowerCase();
        if (oId == itemId || oTitle == itemTitle) return o;
        if (oId.contains(itemId) || itemId.contains(oId)) return o;
        if (oTitle.contains(itemTitle) || itemTitle.contains(oTitle)) return o;
      }
      return null;
    }

    for (final item in requiredEvidence) {
      final w = item.weight.factor;
      totalWeight += w;
      if (item.isCritical) criticalTotal += 1;

      final path = capturedImages[item.id];
      final hasPhoto = path != null && path.isNotEmpty;

      if (!hasPhoto) {
        missingDescriptions.add(
          item.isUnavailable
              ? "${item.title} — you told us you don't have this"
              : '${item.title} — no photo added',
        );
        scoredItems.add(item.copyWith(
          score: 0,
          status: item.isUnavailable ? EvidenceStatus.unavailable : EvidenceStatus.notProvided,
        ));
        continue;
      }

      coveredWeight += w;
      coveredCount += 1;
      acceptedAngles += 1;
      if (item.isCritical) criticalCovered += 1;

      if (item.validation != null) {
        qualityScores.add(item.validation!.quality.qualityScore);
        usefulnessScores.add(item.validation!.authenticationUsefulness);
      }

      final obs = findObservation(item);
      if (obs == null) {
        // Photo accepted but the analysis returned nothing for it.
        if (item.isCritical) criticalUnverified++;
        final fallbackScore = item.validation?.authenticationUsefulness != null && item.validation!.authenticationUsefulness > 0
            ? item.validation!.authenticationUsefulness
            : 50;
        scoredItems.add(item.copyWith(
          score: fallbackScore,
          status: EvidenceStatus.inconclusive,
          capturedImagePath: path,
        ));
        unclear.add("${item.title}: we couldn't get anything useful from this photo.");
        continue;
      }

      // A low-quality photo the user chose to keep contributes less signal (§50).
      if (item.keptDespiteLowQuality) keptLowQualityCount++;
      final trust = item.keptDespiteLowQuality ? 0.5 : 1.0;
      final usefulnessFactor = item.validation != null
          ? (item.validation!.authenticationUsefulness / 100).clamp(0.0, 1.0)
          : 1.0;
      final contribution = w * trust * (0.4 + 0.6 * usefulnessFactor);

      weightedConsistent += obs.consistentSignals.length * contribution;
      weightedInconsistent += obs.inconsistentSignals.length * contribution;
      distinctConsistentSignals += obs.consistentSignals.length;

      if (item.isCritical && obs.inconsistentSignals.isNotEmpty) {
        criticalInconsistencies += obs.inconsistentSignals.length;
      }
      if (item.isCritical && obs.consistentSignals.isEmpty && obs.inconsistentSignals.isEmpty) {
        criticalUnverified++;
      }

      for (final s in obs.consistentSignals) {
        positives.add('${item.title}: $s');
      }
      for (final s in obs.inconsistentSignals) {
        suspicious.add('${item.title}: $s');
      }
      for (final s in obs.uncertainSignals) {
        unclear.add('${item.title}: $s');
      }

      int itemScore;
      EvidenceStatus itemStatus;
      if (obs.inconsistentSignals.isNotEmpty) {
        itemScore = (40 - (obs.inconsistentSignals.length * 10)).clamp(5, 40);
        itemStatus = EvidenceStatus.suspicious;
      } else if (obs.consistentSignals.length >= 2 && obs.uncertainSignals.isEmpty) {
        itemScore = (72 + (obs.consistentSignals.length * 5)).clamp(72, 93);
        itemStatus = EvidenceStatus.consistent;
      } else if (obs.consistentSignals.isNotEmpty) {
        itemScore = 66;
        itemStatus = EvidenceStatus.consistent;
      } else {
        itemScore = 45;
        itemStatus = EvidenceStatus.inconclusive;
      }

      if (item.keptDespiteLowQuality) {
        itemScore = (itemScore * 0.8).round();
      }

      scoredItems.add(item.copyWith(
        score: itemScore,
        status: itemStatus,
        capturedImagePath: path,
        observations: obs.observations,
        consistentSignals: obs.consistentSignals,
        inconsistentSignals: obs.inconsistentSignals,
        uncertainSignals: obs.uncertainSignals,
      ));
    }

    final weightedCoverage = totalWeight > 0 ? (coveredWeight / totalWeight) : 0.0;
    final criticalCoverage = criticalTotal > 0 ? (criticalCovered / criticalTotal) : 1.0;

    final avgQuality = qualityScores.isEmpty
        ? 0
        : (qualityScores.reduce((a, b) => a + b) / qualityScores.length).round();
    final avgUsefulness = usefulnessScores.isEmpty
        ? 0
        : (usefulnessScores.reduce((a, b) => a + b) / usefulnessScores.length).round();

    // -------------------------------------------------------------------
    // 3. Cross-image contradictions
    // -------------------------------------------------------------------
    final contradictionNotes = <String>[];
    double contradictionPenalty = 0;
    var hasCriticalContradiction = false;
    var hasModerateContradiction = false;

    for (final c in contradictions) {
      if (c.description.trim().isEmpty) continue;
      contradictionNotes.add(c.description);
      switch (c.severity) {
        case ContradictionSeverity.critical:
          contradictionPenalty += 34;
          hasCriticalContradiction = true;
          break;
        case ContradictionSeverity.moderate:
          contradictionPenalty += 18;
          hasModerateContradiction = true;
          break;
        case ContradictionSeverity.minor:
          contradictionPenalty += 8;
          break;
      }
    }

    // -------------------------------------------------------------------
    // 4. Evidence strength — how much we can actually conclude from
    // -------------------------------------------------------------------
    final identification = rawIdentificationConfidence.clamp(0, 99);
    final qualityFactor = avgQuality > 0 ? (avgQuality / 100).clamp(0.0, 1.0) : 0.0;
    final usefulnessFactor = avgUsefulness > 0 ? (avgUsefulness / 100).clamp(0.0, 1.0) : 0.0;

    final evidenceStrength =
        (weightedCoverage * 0.4) + (criticalCoverage * 0.3) + (qualityFactor * 0.15) + (usefulnessFactor * 0.15);

    // -------------------------------------------------------------------
    // 5. Verdict
    // -------------------------------------------------------------------
    final replicaSignalWeight = weightedInconsistent + (criticalInconsistencies * 0.8) + (contradictionPenalty / 25);
    final hasSevereProblem =
        criticalInconsistencies >= 1 || weightedInconsistent >= 1.4 || hasCriticalContradiction;

    Verdict verdict;
    int confidence;

    if (hasSevereProblem) {
      verdict = Verdict.likelyReplica;
      // Certainty that the item is NOT genuine, scaled by how much of the item
      // we actually saw. Thin evidence cannot produce a confident rejection.
      final base = 55 + (replicaSignalWeight * 11);
      confidence = (base * (0.55 + 0.45 * evidenceStrength)).round().clamp(50, _replicaCeiling);

      // Without critical coverage even a bad signal stays short of a firm call.
      if (criticalCoverage < 0.5 || evidenceStrength < 0.45) {
        verdict = Verdict.inconclusive;
        confidence = confidence.clamp(35, 60);
      }
    } else {
      final meetsAuthenticGates = criticalCoverage >= 1.0 &&
          criticalUnverified == 0 &&
          weightedCoverage >= _minWeightedCoverageForAuthentic &&
          avgQuality >= _minPhotoQualityForAuthentic &&
          avgUsefulness >= _minUsefulnessForAuthentic &&
          identification >= _minIdentificationForAuthentic &&
          distinctConsistentSignals >= _minConsistentSignalsForAuthentic &&
          acceptedAngles >= _minAcceptedAnglesForAuthentic &&
          weightedInconsistent == 0 &&
          !hasModerateContradiction &&
          !hasCriticalContradiction;

      if (meetsAuthenticGates) {
        verdict = Verdict.likelyAuthentic;
        var raw = 62 + (weightedConsistent * 4.5) + (evidenceStrength * 20);
        raw -= unclear.length * 1.5;
        raw -= contradictionPenalty;
        if (hasModelReference) raw += 4;

        // The ceiling itself scales with how much usable evidence there is, so
        // a thin or blurry submission cannot reach the same confidence as a
        // complete, sharp one even when nothing looks wrong (§23, §40).
        var ceiling = (72 + (evidenceStrength * 22)).round();
        // Knowingly admitting an unreliable image caps how confident the
        // result may be, however clean everything else looks.
        ceiling -= keptLowQualityCount * 7;
        ceiling = ceiling.clamp(72, _authenticCeiling);
        confidence = raw.round().clamp(72, ceiling);
      } else {
        verdict = Verdict.inconclusive;
        // How strongly the evidence leans positive, given how little there is.
        var raw = 30 + (evidenceStrength * 30) + (weightedConsistent * 2.5);
        raw -= (weightedInconsistent * 8) + contradictionPenalty + (unclear.length * 1.5);
        confidence = raw.round().clamp(20, 68);
      }
    }

    // -------------------------------------------------------------------
    // 6. Evidence-specific narrative (§35, §37, §43)
    // -------------------------------------------------------------------
    final itemName = '${product.brand} ${product.name}'.trim();
    final coverageText = '$coveredCount of ${requiredEvidence.length} photos added';

    final nextChecks = _buildNextChecks(
      product: product,
      ruleSet: ruleSet,
      scoredItems: scoredItems,
      missingCritical: requiredEvidence
          .where((e) => e.isCritical && (capturedImages[e.id] ?? '').isEmpty)
          .toList(),
      suspiciousCount: suspicious.length,
      unclearCount: unclear.length,
      verdict: verdict,
    );

    final rationale = _buildRationale(
      itemName: itemName,
      product: product,
      verdict: verdict,
      coveredCount: coveredCount,
      totalCount: requiredEvidence.length,
      criticalCoverage: criticalCoverage,
      missingCriticalTitles: requiredEvidence
          .where((e) => e.isCritical && (capturedImages[e.id] ?? '').isEmpty)
          .map((e) => e.title)
          .toList(),
      positives: positives,
      suspicious: suspicious,
      unclear: unclear,
      contradictions: contradictionNotes,
      avgQuality: avgQuality,
      identification: identification,
      hasModelReference: hasModelReference,
    );

    final quickPoints = <String>[];
    if (verdict == Verdict.likelyReplica) {
      quickPoints.addAll(suspicious.take(3));
      if (contradictionNotes.isNotEmpty) quickPoints.add(contradictionNotes.first);
    } else if (verdict == Verdict.likelyAuthentic) {
      quickPoints.addAll(positives.take(3));
    } else {
      if (suspicious.isNotEmpty) quickPoints.add(suspicious.first);
      if (positives.isNotEmpty) quickPoints.add(positives.first);
      if (missingDescriptions.isNotEmpty) {
        quickPoints.add('Not supplied: ${missingDescriptions.first}');
      } else if (unclear.isNotEmpty) {
        quickPoints.add(unclear.first);
      }
    }

    return ScoringEngineResult(
      verdict: verdict,
      authenticationConfidence: confidence,
      identificationConfidence: identification,
      evidenceCoverageText: coverageText,
      coveredCount: coveredCount,
      totalCount: requiredEvidence.length,
      weightedCoverage: weightedCoverage,
      criticalCoverage: criticalCoverage,
      quickSummaryPoints: quickPoints.where((p) => p.trim().isNotEmpty).toList(),
      positiveFindings: _dedupe(positives),
      suspiciousFindings: _dedupe(suspicious),
      unclearFindings: _dedupe(unclear),
      missingEvidenceDescriptions: missingDescriptions,
      contradictionDescriptions: _dedupe(contradictionNotes),
      nextChecks: nextChecks,
      scoredEvidenceItems: scoredItems,
      rationale: rationale,
    );
  }

  static List<String> _dedupe(List<String> input) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in input) {
      final t = s.trim();
      if (t.isEmpty) continue;
      if (seen.add(t.toLowerCase())) out.add(t);
    }
    return out;
  }

  static List<String> _buildNextChecks({
    required Product product,
    required AuthenticationRuleSet ruleSet,
    required List<EvidenceItem> scoredItems,
    required List<EvidenceItem> missingCritical,
    required int suspiciousCount,
    required int unclearCount,
    required Verdict verdict,
  }) {
    final checks = <String>[];

    for (final m in missingCritical.take(2)) {
      checks.add(
        m.isUnavailable
            ? "Without a photo of the ${m.title.toLowerCase()} we can only say so much."
            : 'Add a photo of the ${m.title.toLowerCase()}. ${m.guide}',
      );
    }

    final unclearItems = scoredItems.where((i) => i.uncertainSignals.isNotEmpty).take(2);
    for (final u in unclearItems) {
      checks.add('Retake the ${u.title.toLowerCase()} closer and in better light.');
    }

    final suspiciousItems = scoredItems.where((i) => i.status == EvidenceStatus.suspicious).take(2);
    for (final s in suspiciousItems) {
      checks.add(
        'Compare the ${s.title.toLowerCase()} with a real ${product.name} you trust.',
      );
    }

    if (checks.isEmpty && verdict == Verdict.likelyAuthentic) {
      final rule = ruleSet.inspectionRules.isNotEmpty ? ruleSet.inspectionRules.first : null;
      if (rule != null) checks.add(rule.simpleTip);
    }

    return checks;
  }

  static String _buildRationale({
    required String itemName,
    required Product product,
    required Verdict verdict,
    required int coveredCount,
    required int totalCount,
    required double criticalCoverage,
    required List<String> missingCriticalTitles,
    required List<String> positives,
    required List<String> suspicious,
    required List<String> unclear,
    required List<String> contradictions,
    required int avgQuality,
    required int identification,
    required bool hasModelReference,
  }) {
    final b = StringBuffer();
    final subject = itemName.isEmpty ? 'this item' : 'your $itemName';

    switch (verdict) {
      case Verdict.likelyAuthentic:
        b.write('Across the $coveredCount photo${coveredCount == 1 ? '' : 's'} you added, '
            'everything we could check on $subject looks right.');
        if (positives.isNotEmpty) {
          b.write(' In particular, ${_phraseList(positives.take(2))}.');
        }
        if (hasModelReference) {
          b.write(' We had known details for this model to compare against.');
        }
        if (unclear.isNotEmpty) {
          b.write(" A few things we couldn't see clearly, so this is based on what you showed us — it isn't a guarantee.");
        }
        break;

      case Verdict.likelyReplica:
        b.write('Some details on $subject look different from how this model should look.');
        if (suspicious.isNotEmpty) {
          b.write(' The main concerns: ${_phraseList(suspicious.take(2))}.');
        }
        if (contradictions.isNotEmpty) {
          b.write(" Your photos also don't agree with each other: ${contradictions.first}");
        }
        break;

      case Verdict.inconclusive:
        b.write("We can't give a clear answer on $subject yet.");
        if (missingCriticalTitles.isNotEmpty) {
          final list = missingCriticalTitles.join(', ');
          b.write(missingCriticalTitles.length == 1
              ? " We're missing one important photo: $list."
              : " We're missing a few important photos: $list.");
        } else if (coveredCount < totalCount) {
          b.write(" We're missing ${totalCount - coveredCount} of the $totalCount photos we asked for.");
        }
        if (positives.isNotEmpty) {
          b.write(' What we could check looked fine: ${_phraseList(positives.take(2))}.');
        }
        if (suspicious.isNotEmpty) {
          b.write(' But ${_phraseList(suspicious.take(2))} needs a closer look.');
        }
        if (avgQuality > 0 && avgQuality < 65) {
          b.write(" Some photos weren't clear enough to check reliably.");
        }
        if (identification > 0 && identification < 60) {
          b.write(" We also couldn't tell exactly what this item is, which limits what we can check.");
        }
        break;
    }

    return b.toString().trim();
  }

  static String _phraseList(Iterable<String> items) {
    final list = items.map((s) {
      // Strip the "Title: " prefix for prose readability.
      final idx = s.indexOf(': ');
      final body = idx > 0 && idx < 40 ? s.substring(idx + 2) : s;
      return body.trim().replaceAll(RegExp(r'\.$'), '').toLowerCase();
    }).toList();

    if (list.isEmpty) return '';
    if (list.length == 1) return list.first;
    return '${list.sublist(0, list.length - 1).join('; ')} and ${list.last}';
  }
}
