import '../data/evidence_profiles.dart';
import '../models/authentication_result.dart';
import '../models/evidence_record.dart';
import '../models/product_identity.dart';
import 'image_hash.dart';

/// Why the evidence is not yet enough for a verdict, and what would fix it.
enum GapType {
  /// Strong evidence points both ways at once.
  contested,

  /// A counterfeit indicator still needs its legitimate-variation check.
  variationCheck,

  /// Only one counterfeit indicator: a second independent one is needed.
  corroborateCounterfeit,

  /// A key detail was photographed but could not be judged.
  unclearPhoto,

  /// The model / generation is not established well enough.
  identity,

  /// A check the profile requires before an authentic result is missing.
  requiredCheck,

  /// No hard-to-copy feature has been checked yet.
  hardToCopy,

  /// Not enough independent features support authenticity.
  independentGroups,

  /// The app has no reliable criteria to confirm this kind of item.
  noAuthenticCriteria,
}

class EngineGap {
  final GapType type;

  /// Plain-language description of what is unresolved.
  final String description;

  /// Checkpoints whose clean observation would resolve the gap.
  final Set<String> targetCheckpointIds;

  /// For [GapType.unclearPhoto]: the request whose photo should be retaken.
  final String? retakeRequestId;
  final String? fix;

  const EngineGap({
    required this.type,
    required this.description,
    this.targetCheckpointIds = const {},
    this.retakeRequestId,
    this.fix,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'description': description,
        'targets': targetCheckpointIds.toList(),
        if (retakeRequestId != null) 'retake': retakeRequestId,
      };
}

/// Qualitative strength of the evidence behind a verdict. Deliberately not a
/// number: nothing here has been calibrated against verified test data.
enum EvidenceStrength {
  strong('Strong'),
  moderate('Moderate'),
  limited('Limited');

  final String label;
  const EvidenceStrength(this.label);

  static EvidenceStrength parse(String? raw) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return EvidenceStrength.limited;
  }
}

/// One contradiction between photos found by the final evaluation.
class CrossPhotoContradiction {
  final String description;
  final List<String> photoIds;

  /// minor / moderate / critical.
  final String severity;

  /// True when it is about what the product is (model, serial, size).
  final bool identityRelated;

  const CrossPhotoContradiction({
    required this.description,
    this.photoIds = const [],
    this.severity = 'moderate',
    this.identityRelated = false,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'photo_ids': photoIds,
        'severity': severity,
        'identity_related': identityRelated,
      };
}

class VariationResult {
  final VariationCheck outcome;
  final String explanation;
  const VariationResult(this.outcome, this.explanation);

  Map<String, dynamic> toJson() => {'outcome': outcome.code, 'explanation': explanation};
}

/// Output of the final (text-only) evidence evaluation. It can only weaken
/// counterfeit evidence or add contradictions; it can never add support for
/// authenticity, so a second AI pass is never treated as independent proof.
class FinalEvaluation {
  final List<CrossPhotoContradiction> contradictions;

  /// Keyed by [EvidenceDecisionEngine.recordKey].
  final Map<String, VariationResult> variationChecks;
  final bool identityConsistent;
  final String explanation;
  final List<String> remainingUncertainty;
  final String model;

  const FinalEvaluation({
    this.contradictions = const [],
    this.variationChecks = const {},
    this.identityConsistent = true,
    this.explanation = '',
    this.remainingUncertainty = const [],
    this.model = '',
  });

  Map<String, dynamic> toJson() => {
        'contradictions': contradictions.map((c) => c.toJson()).toList(),
        'variation_checks': [for (final e in variationChecks.entries) {'key': e.key, ...e.value.toJson()}],
        'identity_consistent': identityConsistent,
        'explanation': explanation,
        'remaining_uncertainty': remainingUncertainty,
        'model': model,
      };
}

class EngineResult {
  final Verdict verdict;

  /// Enough evidence for a supported verdict. The final evaluation may still
  /// be pending (see [awaitingFinalEvaluation]).
  final bool sufficient;
  final bool awaitingFinalEvaluation;
  final EvidenceStrength strength;

  /// Every observation after normalisation.
  final List<EvidenceRecord> records;

  /// Best record per independent group, in each direction.
  final List<EvidenceRecord> supporting;
  final List<EvidenceRecord> contradicting;

  /// Design matches, unclear and not-visible observations.
  final List<EvidenceRecord> neutral;
  final List<EvidenceRecord> unclear;

  final Set<String> authenticGroups;
  final Set<String> hardToCopyGroups;
  final Set<String> counterfeitGroups;
  final int decisiveCount;
  final bool contested;
  final bool identityMet;

  /// Checkpoints actually seen (a consistent or inconsistent observation).
  final Set<String> observedCheckpointIds;
  final List<EngineGap> gaps;
  final List<String> remainingUncertainty;

  /// 0-1: share of what the leading verdict still needs that is in place.
  final double progress;
  final String progressLabel;
  final List<String> trace;
  final Map<String, dynamic> diagnostics;

  const EngineResult({
    required this.verdict,
    required this.sufficient,
    required this.awaitingFinalEvaluation,
    required this.strength,
    required this.records,
    required this.supporting,
    required this.contradicting,
    required this.neutral,
    required this.unclear,
    required this.authenticGroups,
    required this.hardToCopyGroups,
    required this.counterfeitGroups,
    required this.decisiveCount,
    required this.contested,
    required this.identityMet,
    required this.observedCheckpointIds,
    required this.gaps,
    required this.remainingUncertainty,
    required this.progress,
    required this.progressLabel,
    required this.trace,
    this.diagnostics = const {},
  });

  /// Counterfeit records that must be checked against legitimate variations
  /// before a replica verdict is final.
  List<EvidenceRecord> get recordsNeedingVariationCheck => records
      .where((r) =>
          r.direction == EvidenceDirection.supportsCounterfeit &&
          r.reliability.atLeast(Reliability.medium) &&
          r.weight.atLeast(Weight.medium))
      .toList();
}

/// Decides from structured evidence. The vision model reports observations
/// per checkpoint; this engine applies explicit rules:
///
/// * Replica: a decisive, reliable, variation-checked mismatch, or mismatches
///   in two independent features.
/// * Authentic ("visually consistent"): no material mismatch, enough
///   independent supporting features including a hard-to-copy one, and the
///   model identified to the level the profile requires.
/// * Unable to verify: otherwise, with the specific gaps that remain.
///
/// The number of photos never enters a decision.
abstract final class EvidenceDecisionEngine {
  static String recordKey(String photoId, String featureId) => '$photoId|$featureId';

  static final RegExp _conditions = RegExp(
    r'\b(glare|reflection|lighting|shadow|blur|out of focus|focus|compression|pixelat|resolution|angle|perspective|exposure|too dark|too bright|dirt|grime|wear|worn|scratch)',
    caseSensitive: false,
  );

  static final RegExp _brandImitation = RegExp(
    r'\b(imitat|knock-?off|look-?alike|mimic|misspell|counterfeit (brand|logo|marking)|fake logo|trademark)',
    caseSensitive: false,
  );

  static EngineResult evaluate({
    required ResolvedProfile profile,
    required List<PhotoEvidence> photos,
    FinalEvaluation? finalEvaluation,
  }) {
    final trace = <String>[];
    final identity = profile.identity;
    final policy = profile.profile.policy;
    final evaluatedModel = profile.evaluatedModelLabel;

    // ------------------------------------------------------------ photos
    // The same picture submitted twice is one piece of evidence.
    final usedPhotos = <PhotoEvidence>[];
    for (final p in photos) {
      final dup = usedPhotos.any((u) =>
          u.imageHash.isNotEmpty && p.imageHash.isNotEmpty && ImageHash.isDuplicate(u.imageHash, p.imageHash));
      if (dup) {
        trace.add('photo ${p.photoId} is a duplicate of an earlier photo; not counted again');
        continue;
      }
      usedPhotos.add(p);
    }

    // ----------------------------------------------------- normalisation
    final records = <EvidenceRecord>[];
    for (final photo in usedPhotos) {
      for (final a in photo.assessments) {
        records.add(_normalize(a, photo, profile, identity, evaluatedModel));
      }
    }

    // ----------------------------------------- legitimate variation check
    final variation = finalEvaluation?.variationChecks ?? const <String, VariationResult>{};
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      if (r.direction != EvidenceDirection.supportsCounterfeit) continue;
      final v = variation[recordKey(r.photoId, r.featureId)];
      if (v == null) continue;
      switch (v.outcome) {
        case VariationCheck.likely:
          records[i] = r.copyWith(
            direction: EvidenceDirection.unclear,
            variation: VariationCheck.likely,
            variationNote: v.explanation,
            engineNotes: [...r.engineNotes, 'a legitimate variation most likely explains it'],
          );
        case VariationCheck.possible:
          records[i] = r.copyWith(
            reliability: r.reliability.downgraded,
            variation: VariationCheck.possible,
            variationNote: v.explanation,
            engineNotes: [...r.engineNotes, 'a legitimate variation might explain it'],
          );
        case VariationCheck.ruledOut:
          records[i] = r.copyWith(variation: VariationCheck.ruledOut, variationNote: v.explanation);
        case VariationCheck.notChecked:
          break;
      }
    }

    // ------------------------------------- cross-photo contradictions
    final contradictions = finalEvaluation?.contradictions ?? const <CrossPhotoContradiction>[];
    for (var i = 0; i < contradictions.length; i++) {
      final c = contradictions[i];
      final sev = c.severity.toLowerCase();
      final minor = sev.startsWith('minor');
      records.add(EvidenceRecord(
        featureId: 'cross_photo_$i',
        featureName: c.identityRelated ? 'Photos disagree about the model' : 'Photos disagree',
        group: c.identityRelated ? 'cross_photo_identity' : 'cross_photo_$i',
        photoId: c.photoIds.join('+'),
        photoTitle: 'Across photos',
        observation: c.description,
        interpretation: c.description,
        evaluatedModel: evaluatedModel,
        referenceSource: 'Comparison between your photos',
        direction: minor ? EvidenceDirection.unclear : EvidenceDirection.supportsCounterfeit,
        reliability: sev.startsWith('critical') ? Reliability.high : Reliability.medium,
        weight: sev.startsWith('critical') ? Weight.high : Weight.medium,
        kind: EvidenceKind.aiInterpretation,
        variation: VariationCheck.ruledOut,
        engineNotes: const ['from the final cross-photo check'],
      ));
    }

    // ------------------------------------------ feature-level merging
    // Several photos of one checkpoint are one observation. If they
    // disagree, the more reliable one stands; equally reliable disagreement
    // makes the feature unclear.
    final disputes = <String>[];
    final byFeature = <String, List<int>>{};
    for (var i = 0; i < records.length; i++) {
      byFeature.putIfAbsent(records[i].featureId, () => []).add(i);
    }
    for (final entry in byFeature.entries) {
      final idx = entry.value;
      final auth = idx.where((i) => records[i].direction == EvidenceDirection.supportsAuthentic).toList();
      final cf = idx.where((i) => records[i].direction == EvidenceDirection.supportsCounterfeit).toList();
      if (auth.isEmpty || cf.isEmpty) continue;
      final bestA = auth.map((i) => records[i].reliability.index).reduce((a, b) => a < b ? a : b);
      final bestC = cf.map((i) => records[i].reliability.index).reduce((a, b) => a < b ? a : b);
      final name = records[idx.first].featureName;
      if (bestA == bestC) {
        for (final i in [...auth, ...cf]) {
          records[i] = records[i].copyWith(
            direction: EvidenceDirection.unclear,
            engineNotes: [...records[i].engineNotes, 'photos disagree about this feature'],
          );
        }
        disputes.add('Your photos disagree about the ${name.toLowerCase()}.');
      } else {
        final losers = bestA < bestC ? cf : auth;
        for (final i in losers) {
          records[i] = records[i].copyWith(
            direction: EvidenceDirection.unclear,
            engineNotes: [...records[i].engineNotes, 'outweighed by a clearer photo of the same feature'],
          );
        }
      }
    }

    // ------------------------------------------------- group aggregation
    EvidenceRecord? best(Iterable<EvidenceRecord> rs) {
      EvidenceRecord? b;
      for (final r in rs) {
        if (b == null ||
            r.reliability.index < b.reliability.index ||
            (r.reliability == b.reliability && r.weight.index > b.weight.index)) {
          b = r;
        }
      }
      return b;
    }

    bool qualifies(EvidenceRecord r) => r.reliability.atLeast(Reliability.medium) && r.weight.atLeast(Weight.medium);

    final groups = <String>{for (final r in records) r.group};
    final authenticGroups = <String>{};
    final hardGroups = <String>{};
    final counterfeitGroups = <String>{};
    var decisiveCount = 0;
    for (final g in groups) {
      final inGroup = records.where((r) => r.group == g);
      final a = best(inGroup.where((r) => r.direction == EvidenceDirection.supportsAuthentic));
      final c = best(inGroup.where((r) => r.direction == EvidenceDirection.supportsCounterfeit));
      if (a != null && qualifies(a)) {
        authenticGroups.add(g);
        final cp = profile.checkpoint(a.featureId);
        if (cp != null && cp.hardToCopy) hardGroups.add(g);
      }
      if (c != null) {
        if (qualifies(c)) counterfeitGroups.add(g);
        if (c.weight == Weight.decisive && c.reliability == Reliability.high) decisiveCount++;
      }
    }

    // Corroboration: another independent qualifying group points the same way.
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final corroborated = switch (r.direction) {
        EvidenceDirection.supportsAuthentic => authenticGroups.difference({r.group}).isNotEmpty,
        EvidenceDirection.supportsCounterfeit => counterfeitGroups.difference({r.group}).isNotEmpty,
        _ => false,
      };
      if (corroborated != r.corroborated) records[i] = r.copyWith(corroborated: corroborated);
    }

    // Best record per group, for the report.
    final supportingOut = <EvidenceRecord>[];
    final contradictingOut = <EvidenceRecord>[];
    for (final g in groups) {
      final inGroup = records.where((r) => r.group == g);
      final a = best(inGroup.where((r) => r.direction == EvidenceDirection.supportsAuthentic));
      final c = best(inGroup.where((r) => r.direction == EvidenceDirection.supportsCounterfeit));
      if (a != null) supportingOut.add(a);
      if (c != null) contradictingOut.add(c);
    }
    int byStrength(EvidenceRecord x, EvidenceRecord y) {
      final r = x.reliability.index.compareTo(y.reliability.index);
      return r != 0 ? r : y.weight.index.compareTo(x.weight.index);
    }

    supportingOut.sort(byStrength);
    contradictingOut.sort(byStrength);

    trace.add('${usedPhotos.length} photo(s), ${records.length} observations; authentic groups $authenticGroups '
        '(hard-to-copy $hardGroups), counterfeit groups $counterfeitGroups, decisive $decisiveCount');

    // ---------------------------------------------------------- decision
    final identityConsistent = finalEvaluation?.identityConsistent ?? true;
    final missingRequired = policy.requiredForAuthentic
        .where((id) => !records.any((r) =>
            r.featureId == id && r.direction == EvidenceDirection.supportsAuthentic && qualifies(r)))
        .toSet();
    final requiredMet = missingRequired.isEmpty;
    final authenticPhotoIds = {
      for (final r in records)
        if (r.direction == EvidenceDirection.supportsAuthentic && qualifies(r) && authenticGroups.contains(r.group)) r.photoId,
    };
    final photosMet = authenticPhotoIds.length >= policy.minAuthenticPhotos;
    final identityMet = policy.identityForAuthentic.satisfiedBy(identity) && identityConsistent;
    final replicaEvidence = decisiveCount > 0 || counterfeitGroups.length >= 2;
    // A decisive mismatch (no genuine version has it) outweighs one
    // hard-to-copy match; only strong authentic evidence contests it.
    final strongAuthentic = hardGroups.length >= 2 ||
        (policy.requiredForAuthentic.isNotEmpty && requiredMet && hardGroups.isNotEmpty);
    final contested = replicaEvidence && (decisiveCount == 0 ? hardGroups.isNotEmpty : strongAuthentic);
    final gaps = <EngineGap>[];

    Verdict verdict = Verdict.inconclusive;
    var sufficient = false;
    var awaitingFinal = false;

    Set<String> checkpointsWhere(bool Function(Checkpoint c) test) =>
        {for (final c in profile.profile.checkpoints) if (test(c)) c.id};

    if (replicaEvidence && !contested) {
      if (finalEvaluation == null) {
        verdict = Verdict.likelyReplica;
        sufficient = true;
        awaitingFinal = true;
        trace.add('replica evidence present; provisional until the legitimate-variation check runs');
      } else {
        final supportingReplica = records.where((r) =>
            r.direction == EvidenceDirection.supportsCounterfeit &&
            qualifies(r) &&
            r.variation == VariationCheck.ruledOut);
        final decisiveChecked =
            supportingReplica.any((r) => r.weight == Weight.decisive && r.reliability == Reliability.high);
        final checkedGroups = {for (final r in supportingReplica) r.group};
        if (decisiveChecked || checkedGroups.length >= 2) {
          verdict = Verdict.likelyReplica;
          sufficient = true;
          trace.add('replica: ${decisiveChecked ? 'decisive mismatch' : '${checkedGroups.length} independent mismatches'} '
              'with legitimate variations ruled out');
        } else {
          gaps.add(EngineGap(
            type: GapType.variationCheck,
            description: 'A detail looked different from the genuine model, but it could be a legitimate variation '
                '(a different edition, region or replacement part).',
            targetCheckpointIds: checkpointsWhere((c) => c.counterfeitWeight.atLeast(Weight.high)),
          ));
          trace.add('replica evidence not confirmed: legitimate variation not ruled out');
        }
      }
    } else if (contested) {
      gaps.add(EngineGap(
        type: GapType.contested,
        description: 'Some hard-to-copy details look genuine while others look wrong. This can mean a replica, '
            'or a genuine item with replaced parts.',
        targetCheckpointIds: checkpointsWhere((c) => c.hardToCopy || c.counterfeitWeight == Weight.decisive),
      ));
      trace.add('contested: replica evidence and hard-to-copy authentic evidence at once');
    } else {
      final authenticMet = policy.allowsAuthentic &&
          counterfeitGroups.isEmpty &&
          identityMet &&
          requiredMet &&
          photosMet &&
          authenticGroups.length >= policy.minAuthenticGroups &&
          hardGroups.length >= policy.minHardToCopyGroups;
      if (authenticMet) {
        verdict = Verdict.likelyAuthentic;
        sufficient = true;
        awaitingFinal = finalEvaluation == null;
        trace.add('authentic: ${authenticGroups.length} independent groups (${hardGroups.length} hard to copy), no material mismatch');
      } else {
        trace.add('no verdict yet');
      }
    }

    // --------------------------------------------------------------- gaps
    if (!sufficient && !contested) {
      final unclearKey = records.where((r) {
        if (r.direction != EvidenceDirection.unclear) return false;
        final cp = profile.checkpoint(r.featureId);
        return cp != null && cp.needsFineDetail && (cp.hardToCopy || cp.counterfeitWeight.atLeast(Weight.high));
      }).toList();

      if (counterfeitGroups.length == 1 && decisiveCount == 0) {
        final flagged = contradictingOut.firstWhere((r) => counterfeitGroups.contains(r.group), orElse: () => contradictingOut.first);
        gaps.add(EngineGap(
          type: GapType.corroborateCounterfeit,
          description: 'One detail looked different from the genuine model (${flagged.featureName.toLowerCase()}). '
              'A second, independent detail is needed before calling it a replica.',
          targetCheckpointIds: checkpointsWhere(
              (c) => c.group != flagged.group && c.counterfeitWeight.atLeast(Weight.high)),
        ));
      }
      if (unclearKey.isNotEmpty) {
        final r = unclearKey.first;
        final photo = usedPhotos.where((p) => p.photoId == r.photoId).firstOrNull;
        gaps.add(EngineGap(
          type: GapType.unclearPhoto,
          description: 'The ${r.photoTitle.toLowerCase()} photo was not clear enough to check the ${r.featureName.toLowerCase()}.',
          targetCheckpointIds: {r.featureId},
          retakeRequestId: photo?.requestId,
          fix: photo?.quality.fix,
        ));
      }
      if (!identityMet) {
        final what = switch (policy.identityForAuthentic) {
          ModelLevel.generation => 'the exact model and generation',
          ModelLevel.family => 'the exact model',
          _ => 'the brand',
        };
        gaps.add(EngineGap(
          type: GapType.identity,
          description: identityConsistent
              ? 'We have not yet established $what, so model-specific details cannot be confirmed.'
              : 'Your photos disagree about which model this is.',
          targetCheckpointIds: checkpointsWhere((c) => c.identityEstablishing),
        ));
      }
      if (policy.allowsAuthentic && !requiredMet && counterfeitGroups.isEmpty) {
        final names = missingRequired.map((id) => profile.checkpoint(id)?.name.toLowerCase() ?? id).join(' and ');
        gaps.add(EngineGap(
          type: GapType.requiredCheck,
          description: 'The $names has not been checked yet. The outside of this product is copied closely, so its own information screen is needed to confirm it.',
          targetCheckpointIds: missingRequired,
        ));
      }
      if (policy.allowsAuthentic && hardGroups.length < policy.minHardToCopyGroups) {
        gaps.add(EngineGap(
          type: GapType.hardToCopy,
          description: 'None of the hard-to-copy details has been confirmed yet. Copies usually match the outside design.',
          targetCheckpointIds: checkpointsWhere((c) => c.hardToCopy),
        ));
      }
      if (policy.allowsAuthentic && counterfeitGroups.isEmpty && authenticGroups.isNotEmpty && !photosMet) {
        final shown = {
          for (final p in usedPhotos)
            if (authenticPhotoIds.contains(p.photoId)) ...?profile.request(p.requestId)?.checkpointIds,
        };
        gaps.add(EngineGap(
          type: GapType.independentGroups,
          description: 'The details that look right all come from one photo. A photo of a different part is needed to confirm them independently.',
          targetCheckpointIds: checkpointsWhere((c) => c.authenticWeight.atLeast(Weight.medium) && !shown.contains(c.id)),
        ));
      }
      if (policy.allowsAuthentic && authenticGroups.length < policy.minAuthenticGroups) {
        final need = policy.minAuthenticGroups - authenticGroups.length;
        gaps.add(EngineGap(
          type: GapType.independentGroups,
          description: need == 1
              ? 'One more independent detail is needed to confirm the result.'
              : '$need more independent details are needed to confirm the result.',
          targetCheckpointIds: checkpointsWhere(
              (c) => c.authenticWeight.atLeast(Weight.medium) && !authenticGroups.contains(c.group)),
        ));
      }
      if (!policy.allowsAuthentic) {
        gaps.add(const EngineGap(
          type: GapType.noAuthenticCriteria,
          description: 'There is no reliable product-specific reference for this kind of item, so the app can flag '
              'obvious imitation but cannot confirm authenticity.',
        ));
      }
    }

    // ---------------------------------------------------------- strength
    final strength = switch (verdict) {
      Verdict.likelyAuthentic => hardGroups.length >= 2 ||
              (hardGroups.isNotEmpty && authenticGroups.length > policy.minAuthenticGroups)
          ? EvidenceStrength.strong
          : EvidenceStrength.moderate,
      Verdict.likelyReplica => (decisiveCount >= 1 && counterfeitGroups.length >= 2) ||
              counterfeitGroups.length >= 3 ||
              decisiveCount >= 2
          ? EvidenceStrength.strong
          : EvidenceStrength.moderate,
      Verdict.inconclusive => EvidenceStrength.limited,
    };

    // ---------------------------------------------------------- progress
    double authenticProgress() {
      if (!policy.allowsAuthentic) return 0;
      final parts = <double>[
        identityMet ? 1 : 0,
        if (policy.requiredForAuthentic.isNotEmpty) requiredMet ? 1 : 0,
        (authenticPhotoIds.length / policy.minAuthenticPhotos).clamp(0, 1).toDouble(),
        (authenticGroups.length / policy.minAuthenticGroups).clamp(0, 1).toDouble(),
        if (policy.minHardToCopyGroups > 0) (hardGroups.length / policy.minHardToCopyGroups).clamp(0, 1).toDouble(),
        counterfeitGroups.isEmpty ? 1 : 0,
      ];
      return parts.reduce((a, b) => a + b) / parts.length;
    }

    final replicaProgress = decisiveCount > 0 ? 1.0 : (counterfeitGroups.length / 2).clamp(0.0, 1.0);
    final progress = sufficient
        ? 1.0
        : (authenticProgress() > replicaProgress ? authenticProgress() : replicaProgress).clamp(0.0, 0.9);
    final progressLabel = sufficient
        ? 'Enough evidence for a result'
        : gaps.isEmpty
            ? 'Gathering evidence'
            : 'Still needed: ${_short(gaps.first)}';

    // ------------------------------------------------ remaining uncertainty
    final uncertainty = <String>[
      ...gaps.map((g) => g.description),
      ...disputes,
      if (identity.generation.status != AttributeStatus.confirmed && profile.profile.hasGenerations)
        'The generation has not been confirmed, so generation-specific details were not compared.',
      if (identity.modelFamily.status == AttributeStatus.unknown) 'The exact model was not established.',
      for (final c in identity.conflicts) 'Identity check: $c',
      ...?finalEvaluation?.remainingUncertainty,
    ];

    final neutral = records.where((r) => r.direction == EvidenceDirection.neutral).toList();
    final unclear = records
        .where((r) => r.direction == EvidenceDirection.unclear || r.direction == EvidenceDirection.missing)
        .toList();

    return EngineResult(
      verdict: verdict,
      sufficient: sufficient,
      awaitingFinalEvaluation: awaitingFinal,
      strength: strength,
      records: List.unmodifiable(records),
      supporting: supportingOut,
      contradicting: contradictingOut,
      neutral: neutral,
      unclear: unclear,
      authenticGroups: authenticGroups,
      hardToCopyGroups: hardGroups,
      counterfeitGroups: counterfeitGroups,
      decisiveCount: decisiveCount,
      contested: contested,
      identityMet: identityMet,
      observedCheckpointIds: {
        for (final r in records)
          if (r.direction != EvidenceDirection.missing && r.direction != EvidenceDirection.unclear) r.featureId,
      },
      gaps: gaps,
      remainingUncertainty: _dedupe(uncertainty),
      progress: progress,
      progressLabel: progressLabel,
      trace: trace,
    );
  }

  // ------------------------------------------------------------------
  // Normalisation: the explicit rules that turn one model assessment into
  // an evidence record.
  // ------------------------------------------------------------------

  static EvidenceRecord _normalize(
    CheckpointAssessment a,
    PhotoEvidence photo,
    ResolvedProfile profile,
    ProductIdentity identity,
    String evaluatedModel,
  ) {
    final notes = <String>[];
    final text = '${a.feature} ${a.observation} ${a.interpretation}';

    var cp = profile.checkpoint(a.checkpointId);
    // A finding outside the checklist that describes a brand imitation is
    // the brand-marking checkpoint.
    if (cp == null && _brandImitation.hasMatch(text)) {
      cp = profile.checkpoint('brand_marking');
      if (cp != null) notes.add('mapped to brand marking');
    }

    final adHoc = cp == null;
    final featureId = cp?.id ?? 'other:${_slug(a.feature.isEmpty ? a.observation : a.feature)}';
    final featureName = cp?.name ?? (a.feature.isEmpty ? 'Other detail' : a.feature);
    final group = cp?.group ?? featureId;

    var direction = switch (a.outcome) {
      CheckpointOutcome.consistent => EvidenceDirection.supportsAuthentic,
      CheckpointOutcome.inconsistent => EvidenceDirection.supportsCounterfeit,
      CheckpointOutcome.notVisible => EvidenceDirection.missing,
      CheckpointOutcome.unclear => EvidenceDirection.unclear,
    };

    // Findings outside the profile's checklist can inform, never decide:
    // the app does not invent authentication criteria.
    var weight = switch (direction) {
      EvidenceDirection.supportsAuthentic => adHoc ? Weight.none : cp.authenticWeight,
      EvidenceDirection.supportsCounterfeit => adHoc ? Weight.low : cp.counterfeitWeight,
      _ => Weight.none,
    };
    if (adHoc) notes.add('outside the checklist for this product: informational only');

    if (direction == EvidenceDirection.supportsAuthentic && weight == Weight.none) {
      direction = EvidenceDirection.neutral;
      notes.add('design match only: replicas copy this');
    }

    var reliability = a.reliability;
    final limitations = <String>[if (a.limitation.isNotEmpty) a.limitation];

    // Rule 1: fine details cannot be judged reliably from a blurry, glary or
    // distant photo, or from one the user kept despite a quality warning.
    if (cp != null && cp.needsFineDetail) {
      switch (photo.quality.fineDetailPenalty) {
        case 2:
          if (reliability != Reliability.low) notes.add('detail not readable in this photo');
          reliability = Reliability.low;
          limitations.add('The photo was not sharp or clear enough for fine detail.');
        case 1:
          if (reliability != Reliability.low) notes.add('detail only partly readable');
          reliability = reliability.downgraded;
          limitations.add('Fine detail was only partly readable in this photo.');
      }
    }
    if (photo.keptDespiteLowQuality) {
      if (reliability != Reliability.low) notes.add('photo kept despite a quality warning');
      reliability = Reliability.low;
    }

    // Rule 2: a difference the model itself attributes to photo conditions
    // or wear is less reliable. (Merely offering some alternative
    // explanation does not weaken a finding; the variation check handles
    // legitimate alternatives.)
    if (direction == EvidenceDirection.supportsCounterfeit &&
        a.alternativeExplanation != null &&
        _conditions.hasMatch(a.alternativeExplanation!)) {
      reliability = reliability.downgraded;
      notes.add('may be explained by photo conditions or wear');
    }

    // Rule 3: a mismatch only counts against the model it was compared with
    // when that model is established well enough.
    if (cp != null && direction == EvidenceDirection.supportsCounterfeit && !cp.requires.satisfiedBy(identity)) {
      direction = EvidenceDirection.unclear;
      notes.add('model/generation not established enough to compare (${cp.requires.name})');
      limitations.add('The exact ${cp.requires == ModelLevel.generation ? 'generation' : 'model'} is not established, so this could not be compared.');
    }
    // Generation-specific support is only meaningful for a known generation.
    if (cp != null &&
        cp.generationSpecific &&
        direction == EvidenceDirection.supportsAuthentic &&
        !identity.generation.isKnown) {
      weight = weight.capped(Weight.low);
      notes.add('generation unknown: support limited');
    }

    // Evidence kind and reference.
    var kind = a.kind;
    if (a.basis == ReferenceBasis.deviceReported) kind = EvidenceKind.deviceReported;
    if (cp != null && cp.generationSpecific && identity.generation.status != AttributeStatus.confirmed) {
      kind = EvidenceKind.unverifiedAssumption;
    }
    final reference = switch (a.basis) {
      ReferenceBasis.curatedReference => 'AI model knowledge (not independently verified)',
      ReferenceBasis.modelKnowledge => 'AI model knowledge (not independently verified)',
      ReferenceBasis.generalPrinciple => 'General construction principle',
      ReferenceBasis.deviceReported => 'Device-reported information (not verified with the manufacturer)',
    };

    return EvidenceRecord(
      featureId: featureId,
      featureName: featureName,
      group: group,
      photoId: photo.photoId,
      photoTitle: photo.requestTitle,
      observation: a.observation,
      interpretation: a.interpretation,
      evaluatedModel: evaluatedModel,
      referenceSource: reference,
      direction: direction,
      reliability: reliability,
      weight: weight,
      limitations: limitations,
      kind: kind,
      alternativeExplanation: a.alternativeExplanation,
      engineNotes: notes,
    );
  }

  static String _short(EngineGap g) => switch (g.type) {
        GapType.contested => 'resolve conflicting details',
        GapType.variationCheck => 'rule out a legitimate variation',
        GapType.corroborateCounterfeit => 'a second independent detail',
        GapType.unclearPhoto => 'a clearer photo',
        GapType.identity => 'confirm the exact model',
        GapType.requiredCheck => 'the model information screen',
        GapType.hardToCopy => 'a hard-to-copy detail',
        GapType.independentGroups => 'another independent detail',
        GapType.noAuthenticCriteria => 'no reference for this item type',
      };

  static String _slug(String s) {
    final v = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return v.isEmpty ? 'detail' : (v.length > 40 ? v.substring(0, 40) : v);
  }

  static List<String> _dedupe(List<String> input) {
    final seen = <String>{};
    return [
      for (final s in input)
        if (s.trim().isNotEmpty && seen.add(s.trim().toLowerCase())) s.trim(),
    ];
  }
}
