import '../core/config/authenticity_engine_config.dart';
import '../data/authentication_rules.dart';
import '../data/reference_library.dart';
import '../models/authentication_result.dart';
import '../models/evidence.dart';
import '../models/evidence_finding.dart';
import '../models/evidence_observation.dart';
import '../models/product.dart';

typedef _C = AuthenticityEngineConfig;

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

  // ------------------------------------------------------------ engine v2
  /// 0-100: how well the photos let anyone inspect the item.
  final int imageQualityScore;

  /// 0-100: how confident the analysis itself is (quality, identification,
  /// how decisive the findings were). Not the same as authenticity.
  final int analysisConfidence;

  final bool needsMoreImages;
  final List<String> recommendedViews;

  /// What this result could not establish, in plain words.
  final List<String> limitations;

  /// Every finding after the engine's normalization, for the debug log.
  final List<EvidenceFinding> normalizedFindings;

  final double authenticPoints;
  final double counterfeitPoints;
  final int strongCounterfeitCount;

  /// Step-by-step record of how the verdict was reached, for the debug log.
  final List<String> decisionTrace;

  /// Counterfeit findings that would support LIKELY_REPLICA and should be
  /// independently verified before that verdict is shown.
  final List<EvidenceFinding> counterfeitFindingsToVerify;

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
    this.imageQualityScore = 0,
    this.analysisConfidence = 0,
    this.needsMoreImages = false,
    this.recommendedViews = const [],
    this.limitations = const [],
    this.normalizedFindings = const [],
    this.authenticPoints = 0,
    this.counterfeitPoints = 0,
    this.strongCounterfeitCount = 0,
    this.decisionTrace = const [],
    this.counterfeitFindingsToVerify = const [],
  });
}

/// Pure local scoring. The vision model supplies evidence; this engine
/// decides, using the hierarchy:
///
///   strong, specific, reliable counterfeit evidence   -> LIKELY_REPLICA
///   multiple independent authenticity indicators,
///   nothing meaningful contradicting them            -> LIKELY_AUTHENTIC
///   anything else                                     -> INCONCLUSIVE
///
/// It never treats a missing detail as counterfeit evidence, never lets one
/// weak discrepancy decide, and never reaches 100%.
abstract final class AuthenticationScoringEngine {
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
    GeminiEvidenceResponse? analysis,
    List<int> localQualityScores = const [],
    Map<String, VerificationResult> verifications = const {},
    bool? verificationSufficient,
  }) {
    final ruleSet = rules ??
        AuthenticationRules.resolve(
          category: product.category,
          brand: product.brand,
          model: product.model,
          name: product.name,
        );
    final trace = <String>[];
    final identification = rawIdentificationConfidence.clamp(0, 99);
    final modelReliable = analysis?.contradictionCheck.modelIdentificationReliable ?? true;

    final observationMap = {for (final o in observations) o.evidenceId.toLowerCase(): o};
    final usedObservations = <PartObservation>{};

    PartObservation? findObservation(EvidenceItem item) {
      final direct = observationMap[item.id.toLowerCase()];
      if (direct != null) return direct;
      final itemId = item.id.toLowerCase();
      final itemTitle = item.title.toLowerCase();
      for (final o in observations) {
        if (usedObservations.contains(o)) continue;
        final oId = o.evidenceId.toLowerCase();
        final oTitle = o.title.toLowerCase();
        if (oId.isEmpty) continue;
        if (oId == itemId || oTitle == itemTitle) return o;
        if (oId.contains(itemId) || itemId.contains(oId)) return o;
      }
      return null;
    }

    // -------------------------------------------------------------------
    // 1. Coverage + finding normalization, per requested photo
    // -------------------------------------------------------------------
    double totalWeight = 0, coveredWeight = 0, criticalTotal = 0, criticalCovered = 0;
    int coveredCount = 0, keptLowQualityCount = 0;
    final missingDescriptions = <String>[];
    final scoredItems = <EvidenceItem>[];
    final qualityScores = <int>[];
    final allFindings = <EvidenceFinding>[];
    final criticalIds = <String>{};
    final photographedIdentityIds = <String>{};

    for (final item in requiredEvidence) {
      final w = item.weight.factor;
      totalWeight += w;
      if (item.isCritical) {
        criticalTotal += 1;
        criticalIds.add(item.id.toLowerCase());
      }

      final path = capturedImages[item.id];
      if (path == null || path.isEmpty) {
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
      if (item.isCritical) criticalCovered += 1;
      if (ruleSet.identityEvidenceIds.contains(item.id)) photographedIdentityIds.add(item.id.toLowerCase());
      if (item.keptDespiteLowQuality) keptLowQualityCount++;

      final validationQuality = item.validation?.quality.qualityScore;
      if (validationQuality != null) qualityScores.add(validationQuality);

      final obs = findObservation(item);
      if (obs == null) {
        scoredItems.add(item.copyWith(
          score: 45,
          status: EvidenceStatus.inconclusive,
          capturedImagePath: path,
          uncertainSignals: ["We couldn't get anything useful from this photo."],
        ));
        continue;
      }
      usedObservations.add(obs);

      final photoQuality = validationQuality ?? obs.visibleQuality;
      final normalized = [
        for (final f in obs.effectiveFindings)
          _normalize(
            f.copyWithEvidenceId(item.id),
            photoQuality: photoQuality,
            keptLowQuality: item.keptDespiteLowQuality,
            lowWeightEvidence: item.weight == EvidenceWeight.low,
            identification: identification,
            modelReliable: modelReliable,
            verification: verifications[_findingKey(item.id, f)],
          ),
      ];
      allFindings.addAll(normalized);

      final itemScored = _scoreItem(item, normalized);
      scoredItems.add(itemScored.copyWith(
        capturedImagePath: path,
        observations: obs.observations,
        consistentSignals: normalized.where((f) => f.isAuthentic).map((f) => f.displayText).toList(),
        inconsistentSignals: normalized.where((f) => f.isCounterfeit).map((f) => f.displayText).toList(),
        uncertainSignals: normalized.where((f) => f.isUncertain).map((f) => f.displayText).toList(),
      ));
    }

    // Observations for photos outside the plan (e.g. the overview photo
    // when no requested angle was supplied) still count as evidence.
    // An observation that names a requested photo the user never supplied
    // describes an image that doesn't exist, so it is ignored.
    final requestedIds = {for (final e in requiredEvidence) e.id.toLowerCase()};
    for (final o in observations) {
      if (usedObservations.contains(o)) continue;
      if (requestedIds.contains(o.evidenceId.toLowerCase())) {
        trace.add('ignored observation for unsupplied photo "${o.evidenceId}"');
        continue;
      }
      for (final f in o.effectiveFindings) {
        allFindings.add(_normalize(
          f.copyWithEvidenceId(o.evidenceId.isEmpty ? 'overview' : o.evidenceId),
          photoQuality: o.visibleQuality,
          keptLowQuality: false,
          identification: identification,
          modelReliable: modelReliable,
          verification: verifications[_findingKey(o.evidenceId, f)],
        ));
      }
    }

    // Structured missing evidence from the model is informational only.
    for (final m in analysis?.missingEvidence ?? const <EvidenceFinding>[]) {
      allFindings.add(m.copyWith(type: FindingType.missing, strength: FindingStrength.weak));
    }

    // Cross-image contradictions become findings of matching strength.
    final contradictionNotes = <String>[];
    var hasModerateOrWorseContradiction = false;
    for (final c in contradictions) {
      if (c.description.trim().isEmpty) continue;
      contradictionNotes.add(c.description);
      final strength = switch (c.severity) {
        ContradictionSeverity.critical => FindingStrength.strong,
        ContradictionSeverity.moderate => FindingStrength.moderate,
        ContradictionSeverity.minor => FindingStrength.weak,
      };
      if (c.severity != ContradictionSeverity.minor) hasModerateOrWorseContradiction = true;
      final eid = c.involvedPartIds.isEmpty ? 'cross_image' : c.involvedPartIds.join('+');
      allFindings.add(_normalize(
        EvidenceFinding(
          evidenceId: eid,
          feature: 'Photos disagree',
          dimension: 'CROSS_IMAGE',
          type: FindingType.counterfeitIndicator,
          strength: strength,
          observation: c.description,
          modelSpecific: c.severity == ContradictionSeverity.critical,
        ),
        photoQuality: 100,
        keptLowQuality: false,
        identification: identification,
        modelReliable: modelReliable,
        verification: verifications[_findingKey(eid, null, c.description)],
      ));
    }

    // -------------------------------------------------------------------
    // 2. Aggregate evidence
    // -------------------------------------------------------------------
    final weightedCoverage = totalWeight > 0 ? coveredWeight / totalWeight : 0.0;
    final criticalCoverage = criticalTotal > 0 ? criticalCovered / criticalTotal : 1.0;

    if (analysis != null && analysis.imageQualityScore > 0) qualityScores.add(analysis.imageQualityScore);
    qualityScores.addAll(localQualityScores.where((q) => q > 0));
    final imageQuality = qualityScores.isEmpty
        ? 0
        : (qualityScores.reduce((a, b) => a + b) / qualityScores.length).round().clamp(0, 100);

    final counterfeit = allFindings.where((f) => f.isCounterfeit).toList();
    final authentic = allFindings.where((f) => f.isAuthentic).toList();
    final uncertain = allFindings.where((f) => f.isUncertain).toList();

    // Weak counterfeit findings never count toward a replica verdict.
    final countedCounterfeit = counterfeit.where((f) => f.strength != FindingStrength.weak).toList();
    final counterfeitPoints = countedCounterfeit.fold<double>(0, (s, f) => s + f.strength.points);
    final strongCounterfeit =
        countedCounterfeit.where((f) => f.strength == FindingStrength.strong && f.modelSpecific).toList();
    final independentCounterfeitAreas = countedCounterfeit.map(_independenceKey).toSet().length;

    final countedAuthentic = authentic.where((f) => f.strength != FindingStrength.weak).toList();
    final authenticPoints = authentic.fold<double>(0, (s, f) => s + f.strength.points);
    final independentAuthenticAreas = countedAuthentic.map((f) => f.evidenceId.toLowerCase()).toSet().length;
    final authenticOnCritical = countedAuthentic.any((f) => criticalIds.contains(f.evidenceId.toLowerCase()));

    trace.add('findings: ${authentic.length} authentic (${authenticPoints.toStringAsFixed(1)} pts, '
        '$independentAuthenticAreas photos), ${counterfeit.length} counterfeit '
        '(${counterfeitPoints.toStringAsFixed(1)} counted pts, ${strongCounterfeit.length} strong, '
        '$independentCounterfeitAreas independent), ${uncertain.length} missing/ambiguous/unverifiable');
    trace.add('coverage ${(weightedCoverage * 100).round()}%, critical ${(criticalCoverage * 100).round()}%, '
        'image quality $imageQuality, identification $identification');

    final evidenceStrength = (weightedCoverage * 0.4) +
        (criticalCoverage * 0.3) +
        ((imageQuality / 100).clamp(0.0, 1.0) * 0.3);

    // -------------------------------------------------------------------
    // 3. Decision hierarchy
    // -------------------------------------------------------------------
    Verdict verdict;
    int confidence;
    var toVerify = <EvidenceFinding>[];

    final qualityGateFailed = imageQuality > 0 && imageQuality < _C.imageQualityGate;

    final replicaEvidenceMet = counterfeitPoints >= _C.minCounterfeitPoints &&
        independentCounterfeitAreas >= _C.minIndependentCounterfeitAreas &&
        strongCounterfeit.length >= _C.minStrongCounterfeitFindings;

    if (qualityGateFailed) {
      verdict = Verdict.inconclusive;
      confidence = 25;
      trace.add('quality gate: $imageQuality < ${_C.imageQualityGate} -> INCONCLUSIVE, no classification attempted');
    } else if (replicaEvidenceMet) {
      final blockers = <String>[
        if (identification < _C.minIdentificationForReplica) 'identification $identification < ${_C.minIdentificationForReplica}',
        if (analysis != null && analysis.contradictionCheck.couldBeExplainedByConditions)
          'model says conditions could explain it',
        if (analysis != null &&
            analysis.modelClassification != null &&
            analysis.modelClassification != 'LIKELY_REPLICA')
          'model itself classified ${analysis.modelClassification}',
        if (verificationSufficient == false) 'verification pass: evidence not sufficient',
      ];
      if (blockers.isEmpty) {
        verdict = Verdict.likelyReplica;
        final raw = 58 + counterfeitPoints * 2.5 + strongCounterfeit.length * 4;
        final scaled = raw * (0.75 + 0.25 * evidenceStrength);
        confidence = scaled.round().clamp(60, _C.confidenceCeiling);
        toVerify = countedCounterfeit;
        trace.add('replica evidence met and not blocked -> LIKELY_REPLICA');
      } else {
        verdict = Verdict.inconclusive;
        confidence = 45;
        trace.add('replica evidence met but blocked (${blockers.join('; ')}) -> INCONCLUSIVE');
      }
    } else {
      // A "meaningful" contradiction (§25) is one that could change the
      // answer: anything strong, anything model-specific, anything on a
      // critical photo, or moderate findings in two or more independent areas. A lone generic moderate
      // complaint lowers confidence but doesn't block the result.
      final meaningfulCounterfeit = countedCounterfeit.any((f) => f.strength == FindingStrength.strong) ||
          countedCounterfeit.any((f) => f.modelSpecific) ||
          countedCounterfeit.any((f) => criticalIds.contains(f.evidenceId.toLowerCase())) ||
          independentCounterfeitAreas >= 2;
      final authenticGates = <String, bool>{
        'authentic indicators >= ${_C.minAuthenticIndicators}': countedAuthentic.length >= _C.minAuthenticIndicators,
        'independent photos >= ${_C.minIndependentAuthenticAreas}':
            independentAuthenticAreas >= _C.minIndependentAuthenticAreas,
        'authentic points >= ${_C.minAuthenticPoints}': authenticPoints >= _C.minAuthenticPoints,
        'indicator on a critical photo': authenticOnCritical,
        'critical coverage >= ${_C.minCriticalCoverageForAuthentic}':
            criticalCoverage >= _C.minCriticalCoverageForAuthentic,
        'identification >= ${_C.minIdentificationForAuthentic}': identification >= _C.minIdentificationForAuthentic,
        'image quality >= ${_C.minImageQualityForAuthentic}':
            imageQuality == 0 || imageQuality >= _C.minImageQualityForAuthentic,
        'no meaningful counterfeit indicator': !meaningfulCounterfeit,
        'no moderate/critical contradiction': !hasModerateOrWorseContradiction,
        'model did not classify replica': analysis?.modelClassification != 'LIKELY_REPLICA',
      };
      final failed = authenticGates.entries.where((e) => !e.value).map((e) => e.key).toList();

      if (failed.isEmpty) {
        verdict = Verdict.likelyAuthentic;
        // Every unresolved counterfeit finding still costs confidence.
        final weakCounterfeitPts = counterfeit.fold<double>(0, (s, f) => s + f.strength.points);
        var raw = 60 + authenticPoints * 1.6 + evidenceStrength * 14 - uncertain.length * 0.8;
        if (hasModelReference) raw += 3;

        var ceiling = (72 + evidenceStrength * 22).round();
        final identityVerified = ruleSet.identityEvidenceIds.isEmpty ||
            countedAuthentic.any((f) => ruleSet.identityEvidenceIds.contains(f.evidenceId));
        if (!identityVerified) ceiling = ceiling.clamp(0, _C.ceilingWithoutIdentityMarking);
        ceiling -= keptLowQualityCount * 7;
        ceiling = ceiling.clamp(70, _C.confidenceCeiling);
        // Unresolved counterfeit findings come off after the ceiling, so
        // they always show in the final number.
        confidence = (raw.round().clamp(65, ceiling) - (weakCounterfeitPts * 2.5).round()).clamp(65, ceiling);
        trace.add('all authentic gates passed -> LIKELY_AUTHENTIC (ceiling $ceiling'
            '${identityVerified ? '' : ', identity marking not verified'})');
      } else {
        verdict = Verdict.inconclusive;
        final raw = 30 + evidenceStrength * 25 + (authenticPoints - counterfeitPoints) * 1.2;
        confidence = raw.round().clamp(20, 60);
        trace.add('not enough for either verdict (${failed.join('; ')}) -> INCONCLUSIVE');
      }
    }

    // -------------------------------------------------------------------
    // 4. Analysis confidence, limitations, next photos
    // -------------------------------------------------------------------
    final decisive = authentic.length + counterfeit.length;
    final decisiveness = allFindings.isEmpty ? 0 : (decisive * 100 / allFindings.length).round();
    final analysisConfidence =
        (((imageQuality == 0 ? 60 : imageQuality) + identification + decisiveness) / 3).round().clamp(0, 95);

    final limitations = <String>[];
    final identityBlueprints =
        ruleSet.evidenceBlueprint.where((b) => b.identityMarking).map((b) => b.title.toLowerCase()).toList();
    if (identityBlueprints.isNotEmpty &&
        !countedAuthentic.any((f) => ruleSet.identityEvidenceIds.contains(f.evidenceId))) {
      limitations.add(photographedIdentityIds.isEmpty
          ? "The ${identityBlueprints.first} wasn't photographed, so complete verification wasn't possible from these photos."
          : "The ${identityBlueprints.first} wasn't clear enough to confirm, so complete verification wasn't possible.");
    }
    if (analysis != null && !analysis.modelConfirmed) {
      limitations.add('The exact model could not be confirmed from the photos.');
    }
    if (analysis != null && analysis.observedText.isNotEmpty) {
      limitations.add('Any serial or model number shown was read from the photo only. '
          'It has not been checked with the brand.');
    }
    if (allFindings.any((f) => f.type == FindingType.unverifiable)) {
      limitations.add("Some things, like weight and internal parts, can't be checked from photos.");
    }

    final missingCritical = requiredEvidence
        .where((e) => e.isCritical && (capturedImages[e.id] ?? '').isEmpty)
        .toList();
    for (final m in missingCritical) {
      final alreadyCovered = limitations.any((l) => l.toLowerCase().contains(m.title.toLowerCase()));
      if (!alreadyCovered) {
        limitations.add(m.isUnavailable
            ? "You don't have the ${m.title.toLowerCase()}, so it wasn't checked."
            : 'No photo of the ${m.title.toLowerCase()} was added, so it wasn\'t checked.');
      }
    }

    final recommendedViews = <String>[];
    void addView(String v) {
      final t = v.trim();
      if (t.isEmpty) return;
      if (recommendedViews.any((r) => r.toLowerCase() == t.toLowerCase())) return;
      recommendedViews.add(t);
    }

    for (final m in missingCritical) {
      addView(m.guide);
    }
    for (final i in scoredItems.where((i) => i.status == EvidenceStatus.inconclusive && i.hasPhoto)) {
      addView('Retake the ${i.title.toLowerCase()} closer and in better light.');
    }
    for (final v in analysis?.recommendedViews ?? const <String>[]) {
      addView(v);
    }
    final needsMoreImages = verdict == Verdict.inconclusive &&
        (qualityGateFailed ||
            missingCritical.isNotEmpty ||
            (analysis?.contradictionCheck.morePhotosRequired ?? false) ||
            recommendedViews.isNotEmpty);

    // -------------------------------------------------------------------
    // 5. Narrative
    // -------------------------------------------------------------------
    final positives = _dedupe([
      for (final f in authentic) '${_titleFor(f.evidenceId, requiredEvidence)}: ${f.observation.isEmpty ? f.feature : f.observation}',
    ]);
    final suspicious = _dedupe([
      for (final f in counterfeit) '${_titleFor(f.evidenceId, requiredEvidence)}: ${f.observation.isEmpty ? f.feature : f.observation}',
    ]);
    final unclear = _dedupe([
      for (final f in uncertain.where((f) => f.type != FindingType.missing))
        '${_titleFor(f.evidenceId, requiredEvidence)}: ${f.observation.isEmpty ? f.feature : f.observation}',
      for (final i in scoredItems.where((i) => i.status == EvidenceStatus.inconclusive && i.hasPhoto && i.uncertainSignals.isEmpty))
        "${i.title}: we couldn't get anything useful from this photo.",
    ]);

    final itemName = '${product.brand} ${product.name}'.trim();
    final nextChecks = _buildNextChecks(
      product: product,
      ruleSet: ruleSet,
      scoredItems: scoredItems,
      missingCritical: missingCritical,
      verdict: verdict,
      recommendedViews: recommendedViews,
    );

    final rationale = _buildRationale(
      itemName: itemName,
      verdict: verdict,
      coveredCount: coveredCount,
      totalCount: requiredEvidence.length,
      missingCriticalTitles: missingCritical.map((e) => e.title).toList(),
      positives: positives,
      suspicious: suspicious,
      contradictions: contradictionNotes,
      imageQuality: imageQuality,
      qualityGateFailed: qualityGateFailed,
      identification: identification,
      hasModelReference: hasModelReference,
      limitations: limitations,
      firstRecommendedView: recommendedViews.isEmpty ? null : recommendedViews.first,
    );

    final quickPoints = <String>[];
    if (verdict == Verdict.likelyReplica) {
      quickPoints.addAll(suspicious.take(3));
    } else if (verdict == Verdict.likelyAuthentic) {
      quickPoints.addAll(positives.take(3));
      if (limitations.isNotEmpty) quickPoints.add(limitations.first);
    } else {
      if (positives.isNotEmpty) quickPoints.add(positives.first);
      if (suspicious.isNotEmpty) quickPoints.add('Needs a closer look — ${suspicious.first}');
      if (recommendedViews.isNotEmpty) quickPoints.add('Next photo: ${recommendedViews.first}');
    }

    return ScoringEngineResult(
      verdict: verdict,
      authenticationConfidence: confidence,
      identificationConfidence: identification,
      evidenceCoverageText: '$coveredCount of ${requiredEvidence.length} photos added',
      coveredCount: coveredCount,
      totalCount: requiredEvidence.length,
      weightedCoverage: weightedCoverage,
      criticalCoverage: criticalCoverage,
      quickSummaryPoints: quickPoints.where((p) => p.trim().isNotEmpty).toList(),
      positiveFindings: positives,
      suspiciousFindings: suspicious,
      unclearFindings: unclear,
      missingEvidenceDescriptions: missingDescriptions,
      contradictionDescriptions: _dedupe(contradictionNotes),
      nextChecks: nextChecks,
      scoredEvidenceItems: scoredItems,
      rationale: rationale,
      imageQualityScore: imageQuality,
      analysisConfidence: analysisConfidence,
      needsMoreImages: needsMoreImages,
      recommendedViews: recommendedViews.take(3).toList(),
      limitations: limitations,
      normalizedFindings: allFindings,
      authenticPoints: authenticPoints,
      counterfeitPoints: counterfeitPoints,
      strongCounterfeitCount: strongCounterfeit.length,
      decisionTrace: trace,
      counterfeitFindingsToVerify: toVerify,
    );
  }

  // ---------------------------------------------------------------------
  // Finding normalization: the rules that stop noise from becoming a verdict
  // ---------------------------------------------------------------------

  static EvidenceFinding _normalize(
    EvidenceFinding f, {
    required int photoQuality,
    required bool keptLowQuality,
    required int identification,
    required bool modelReliable,
    bool lowWeightEvidence = false,
    VerificationResult? verification,
  }) {
    if (!f.isCounterfeit) return f;
    final text = '${f.feature} ${f.observation}';

    // Rule 1: absence is uncertainty, never counterfeit evidence.
    if (EvidenceFinding.describesAbsence(text)) {
      return f.copyWith(type: FindingType.missing, strength: FindingStrength.weak,
          engineNote: 'reclassified: describes something not visible');
    }
    // Rule 2: a discrepancy attributed to photo conditions is ambiguous.
    if (EvidenceFinding.attributesToConditions(text)) {
      return f.copyWith(type: FindingType.ambiguous, strength: FindingStrength.weak,
          engineNote: 'reclassified: attributed to photo conditions');
    }

    // Rule 3: the independent verification pass has the last word.
    if (verification != null) {
      switch (verification.outcome) {
        case VerificationOutcome.confirmed:
          return f.copyWith(strength: verification.strength, engineNote: 'verified: confirmed');
        case VerificationOutcome.notVisible:
          return f.copyWith(type: FindingType.missing, strength: FindingStrength.weak,
              engineNote: 'verification: not actually visible');
        case VerificationOutcome.explainedByConditions:
          return f.copyWith(type: FindingType.ambiguous, strength: FindingStrength.weak,
              engineNote: 'verification: explained by conditions');
        case VerificationOutcome.notModelSpecific:
          return f.copyWith(strength: FindingStrength.weak, engineNote: 'verification: not model-specific');
      }
    }

    var strength = f.strength;
    final notes = <String>[];
    // Rule 4: STRONG requires a model-specific comparison.
    if (strength == FindingStrength.strong && !f.modelSpecific) {
      strength = FindingStrength.moderate;
      notes.add('not model-specific');
    }
    // Rule 5: blurry or kept-low-quality photos can't carry strong claims.
    if (photoQuality < _C.lowQualityDowngradeThreshold || keptLowQuality) {
      strength = strength.downgraded;
      notes.add('photo quality $photoQuality');
    }
    // Rule 6: a plausible benign explanation costs one level.
    if (f.alternativeExplanation != null && f.alternativeExplanation!.length > 3) {
      strength = strength.downgraded;
      notes.add('alternative explanation offered');
    }
    // Rule 7: packaging and papers are never decisive.
    if (lowWeightEvidence) {
      strength = strength.downgraded;
      notes.add('packaging-level evidence');
    }
    // Rule 8: comparisons against a model we aren't sure of are weak.
    if (f.modelSpecific && (!modelReliable || identification < _C.minIdentificationForReplica)) {
      strength = strength.downgraded;
      notes.add('model identification unreliable');
    }
    if (notes.isEmpty) return f;
    return f.copyWith(strength: strength, engineNote: 'downgraded: ${notes.join(', ')}');
  }

  static EvidenceItem _scoreItem(EvidenceItem item, List<EvidenceFinding> findings) {
    final cf = findings.where((f) => f.isCounterfeit && f.strength != FindingStrength.weak).toList();
    final au = findings.where((f) => f.isAuthentic).toList();
    int score;
    EvidenceStatus status;
    if (cf.isNotEmpty) {
      score = (40 - cf.fold<double>(0, (s, f) => s + f.strength.points) * 4).round().clamp(5, 40);
      status = EvidenceStatus.suspicious;
    } else if (au.length >= 2) {
      score = (72 + au.length * 5).clamp(72, 93);
      status = EvidenceStatus.consistent;
    } else if (au.isNotEmpty) {
      score = 66;
      status = EvidenceStatus.consistent;
    } else {
      score = 45;
      status = EvidenceStatus.inconclusive;
    }
    if (item.keptDespiteLowQuality) score = (score * 0.8).round();
    return item.copyWith(score: score, status: status);
  }

  /// Two counterfeit findings are independent when they concern different
  /// aspects of the item; three complaints about the same logo are one.
  static String _independenceKey(EvidenceFinding f) {
    if (f.dimension != 'OTHER' && f.dimension.isNotEmpty) return f.dimension;
    return '${f.evidenceId}|${f.feature}'.toLowerCase();
  }

  /// Key used to match a verification result back to its finding.
  static String findingKey(String evidenceId, EvidenceFinding f) => _findingKey(evidenceId, f);

  static String _findingKey(String evidenceId, EvidenceFinding? f, [String? text]) =>
      '${evidenceId.toLowerCase()}|${(text ?? f?.observation ?? '').trim().toLowerCase()}';

  static String _titleFor(String evidenceId, List<EvidenceItem> items) {
    for (final i in items) {
      if (i.id.toLowerCase() == evidenceId.toLowerCase()) return i.title;
    }
    if (evidenceId == 'overview') return 'Overview photo';
    if (evidenceId.contains('+') || evidenceId == 'cross_image') return 'Across photos';
    return evidenceId.replaceAll('_', ' ');
  }

  static List<String> _dedupe(List<String> input) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in input) {
      final t = s.trim();
      if (t.isEmpty || t.endsWith(': ')) continue;
      if (seen.add(t.toLowerCase())) out.add(t);
    }
    return out;
  }

  static List<String> _buildNextChecks({
    required Product product,
    required AuthenticationRuleSet ruleSet,
    required List<EvidenceItem> scoredItems,
    required List<EvidenceItem> missingCritical,
    required Verdict verdict,
    required List<String> recommendedViews,
  }) {
    final checks = <String>[];
    for (final m in missingCritical.take(2)) {
      checks.add(
        m.isUnavailable
            ? "Without a photo of the ${m.title.toLowerCase()} we can only say so much."
            : 'Add a photo of the ${m.title.toLowerCase()}. ${m.guide}',
      );
    }
    for (final u in scoredItems.where((i) => i.uncertainSignals.isNotEmpty && i.hasPhoto).take(2)) {
      checks.add('Retake the ${u.title.toLowerCase()} closer and in better light.');
    }
    for (final s in scoredItems.where((i) => i.status == EvidenceStatus.suspicious).take(2)) {
      checks.add('Compare the ${s.title.toLowerCase()} with a real ${product.name} you trust.');
    }
    if (checks.isEmpty && recommendedViews.isNotEmpty) checks.add(recommendedViews.first);
    if (checks.isEmpty && verdict == Verdict.likelyAuthentic && ruleSet.inspectionRules.isNotEmpty) {
      checks.add(ruleSet.inspectionRules.first.simpleTip);
    }
    return checks;
  }

  static String _buildRationale({
    required String itemName,
    required Verdict verdict,
    required int coveredCount,
    required int totalCount,
    required List<String> missingCriticalTitles,
    required List<String> positives,
    required List<String> suspicious,
    required List<String> contradictions,
    required int imageQuality,
    required bool qualityGateFailed,
    required int identification,
    required bool hasModelReference,
    required List<String> limitations,
    String? firstRecommendedView,
  }) {
    final b = StringBuffer();
    final subject = itemName.isEmpty ? 'this item' : 'your $itemName';

    switch (verdict) {
      case Verdict.likelyAuthentic:
        b.write('We found several details consistent with $subject');
        b.write(positives.isNotEmpty ? ', including ${_phraseList(positives.take(3))}.' : '.');
        if (hasModelReference) b.write(' We had known details for this model to compare against.');
        if (limitations.isNotEmpty) b.write(' Limitations: ${limitations.first}');
        b.write(' This is an AI-assisted opinion, not a guarantee.');
        break;

      case Verdict.likelyReplica:
        b.write('We found multiple details on $subject that differ from how this model is made');
        b.write(suspicious.isNotEmpty ? ', including ${_phraseList(suspicious.take(3))}.' : '.');
        if (contradictions.isNotEmpty) {
          b.write(" Your photos also don't agree with each other: ${contradictions.first}");
        }
        b.write(' Each of these was checked a second time before this result was shown.');
        break;

      case Verdict.inconclusive:
        if (qualityGateFailed) {
          b.write("The photos of $subject aren't clear enough to check authenticity, so we didn't guess.");
        } else {
          b.write("The visible details don't show enough authentication-specific features "
              'to say whether $subject is genuine.');
        }
        if (missingCriticalTitles.isNotEmpty) {
          b.write(missingCriticalTitles.length == 1
              ? " We're missing one important photo: ${missingCriticalTitles.first}."
              : " We're missing a few important photos: ${missingCriticalTitles.join(', ')}.");
        } else if (coveredCount < totalCount) {
          b.write(" We're missing ${totalCount - coveredCount} of the $totalCount photos we asked for.");
        }
        if (positives.isNotEmpty) b.write(' What we could check looked consistent: ${_phraseList(positives.take(2))}.');
        if (suspicious.isNotEmpty) b.write(' ${_capitalize(_phraseList(suspicious.take(2)))} needs a closer look.');
        if (!qualityGateFailed && imageQuality > 0 && imageQuality < 60) {
          b.write(" Some photos weren't clear enough to check reliably.");
        }
        if (identification > 0 && identification < 60) {
          b.write(" We also couldn't tell exactly what this item is, which limits what we can check.");
        }
        if (firstRecommendedView != null) b.write(' Recommended next photo: $firstRecommendedView');
        break;
    }
    return b.toString().trim();
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _phraseList(Iterable<String> items) {
    final list = items.map((s) {
      final idx = s.indexOf(': ');
      final body = idx > 0 && idx < 40 ? s.substring(idx + 2) : s;
      return body.trim().replaceAll(RegExp(r'\.$'), '').toLowerCase();
    }).toList();
    if (list.isEmpty) return '';
    if (list.length == 1) return list.first;
    return '${list.sublist(0, list.length - 1).join('; ')} and ${list.last}';
  }
}

/// Outcome of the second-pass verification for one counterfeit finding.
class VerificationResult {
  final VerificationOutcome outcome;
  final FindingStrength strength;
  final String reason;

  const VerificationResult({required this.outcome, required this.strength, this.reason = ''});

  Map<String, dynamic> toJson() => {'outcome': outcome.code, 'strength': strength.code, 'reason': reason};
}

extension on EvidenceFinding {
  EvidenceFinding copyWithEvidenceId(String id) => EvidenceFinding(
        evidenceId: id,
        feature: feature,
        dimension: dimension,
        type: type,
        strength: strength,
        observation: observation,
        modelSpecific: modelSpecific,
        alternativeExplanation: alternativeExplanation,
        engineNote: engineNote,
      );
}
