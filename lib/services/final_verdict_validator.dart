import '../data/evidence_profiles.dart';
import '../models/authentication_result.dart';
import '../models/evidence_record.dart';
import '../models/product_reference.dart';
import 'evidence_decision_engine.dart';

/// One finding of the final combined analysis, with image ids already
/// mapped to photo ids (a close-up counts as its parent photo).
class CombinedFinding {
  final String claimId;
  final String feature;
  final String area;
  final List<String> photoIds;
  final String observed;

  /// MATCHES | CONFLICTS | UNCLEAR | NOT_VISIBLE
  final String comparison;

  /// CLEAR | PARTIAL | OBSCURED
  final String visibility;
  final Reliability reliability;

  /// REFERENCE_CLAIM | MODEL_KNOWLEDGE | GENERIC_QUALITY
  final String basis;
  final String? alternativeExplanation;
  final VariationCheck variation;

  /// The app's photo part the detail is on (independence group), or null.
  final String? partRequestId;

  /// DIFFERENT | ABSENT | NOT_APPLICABLE
  final String differenceKind;

  /// MARKING | MATERIAL | CONSTRUCTION | LABEL | SOFTWARE | PACKAGING | OTHER
  final String detailKind;

  /// Gemini's own judgement, used only for details from its knowledge.
  final bool hardToCopy;
  final bool counterfeitTell;

  /// THIS_GENERATION | MODEL_FAMILY | BRAND_WIDE | NOT_SURE
  final String knowledgeScope;

  const CombinedFinding({
    required this.claimId,
    required this.feature,
    required this.area,
    required this.photoIds,
    required this.observed,
    required this.comparison,
    required this.visibility,
    required this.reliability,
    required this.basis,
    required this.alternativeExplanation,
    required this.variation,
    this.partRequestId,
    this.differenceKind = 'NOT_APPLICABLE',
    this.detailKind = 'OTHER',
    this.hardToCopy = false,
    this.counterfeitTell = false,
    this.knowledgeScope = 'NOT_SURE',
  });

  Map<String, dynamic> toJson() => {
        'claim_id': claimId,
        'part': ?partRequestId,
        'difference_kind': differenceKind,
        'detail_kind': detailKind,
        'hard_to_copy': hardToCopy,
        'counterfeit_tell': counterfeitTell,
        'knowledge_scope': knowledgeScope,
        'feature': feature,
        'area': area,
        'photo_ids': photoIds,
        'observed': observed,
        'comparison': comparison,
        'visibility': visibility,
        'reliability': reliability.code,
        'basis': basis,
        if (alternativeExplanation != null) 'alternative_explanation': alternativeExplanation,
        'legitimate_variation': variation.code,
      };
}

class UnresolvedItem {
  final String issue;
  final String? requestId;
  final String? check;
  const UnresolvedItem(this.issue, this.requestId, this.check);

  Map<String, dynamic> toJson() => {'issue': issue, 'request_id': ?requestId, 'check': ?check};
}

/// Parsed and structurally validated answer of the combined analysis.
class CombinedAnalysis {
  final String? brand;
  final String? model;
  final String? generation;
  final String? variant;
  final String identityBasis;
  final bool identityConsistent;
  final List<CombinedFinding> findings;
  final List<CrossPhotoContradiction> contradictions;

  /// AUTHENTIC | REPLICA | NOT_SURE
  final String proposedVerdict;
  final String reasoning;
  final List<String> summaryPoints;
  final List<UnresolvedItem> unresolved;
  final List<String> independentVerification;

  /// Findings dropped by validation (unknown images, empty text), for logs.
  final int droppedFindings;

  const CombinedAnalysis({
    this.brand,
    this.model,
    this.generation,
    this.variant,
    this.identityBasis = '',
    required this.identityConsistent,
    required this.findings,
    required this.contradictions,
    required this.proposedVerdict,
    required this.reasoning,
    this.summaryPoints = const [],
    required this.unresolved,
    this.independentVerification = const [],
    this.droppedFindings = 0,
  });

  /// Throws [FormatException] when a required part is missing, so the caller
  /// retries and then reports an error instead of producing a result.
  factory CombinedAnalysis.parse(
    Map<String, dynamic> json, {
    required Map<String, String> imageToPhoto,
    required Set<String> claimIds,
    required Set<String> requestIds,
  }) {
    final ident = json['identity_established'];
    if (ident is! Map || ident['consistent_with_identification'] is! bool) {
      throw const FormatException('combined analysis without identity_established');
    }
    if (json['findings'] is! List || json['cross_image_contradictions'] is! List || json['unresolved'] is! List) {
      throw const FormatException('combined analysis without findings / contradictions / unresolved');
    }
    final verdict = json['proposed_verdict']?.toString();
    if (!const {'AUTHENTIC', 'REPLICA', 'NOT_SURE'}.contains(verdict)) {
      throw const FormatException('combined analysis without a valid proposed_verdict');
    }
    String? str(Object? v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty || s.toLowerCase() == 'null' || s.toLowerCase() == 'unknown' ? null : s;
    }

    List<String> photos(Object? ids) => {
          for (final i in (ids as List? ?? const []))
            if (imageToPhoto.containsKey(i.toString())) imageToPhoto[i.toString()]!,
        }.toList();

    var dropped = 0;
    final findings = <CombinedFinding>[];
    for (final f in (json['findings'] as List).whereType<Map>()) {
      final ids = photos(f['image_ids']);
      final observed = str(f['observed']);
      final comparison = f['comparison']?.toString() ?? '';
      if (ids.isEmpty || observed == null || !const {'MATCHES', 'CONFLICTS', 'UNCLEAR', 'NOT_VISIBLE'}.contains(comparison)) {
        dropped++;
        continue;
      }
      final claim = f['claim_id']?.toString() ?? 'none';
      findings.add(CombinedFinding(
        claimId: claimIds.contains(claim) ? claim : 'none',
        feature: str(f['feature']) ?? str(f['area']) ?? 'Detail',
        area: (str(f['area']) ?? str(f['feature']) ?? 'detail').toLowerCase(),
        photoIds: ids,
        observed: observed,
        comparison: comparison,
        visibility: const {'CLEAR', 'PARTIAL', 'OBSCURED'}.contains(f['visibility']) ? f['visibility'] as String : 'PARTIAL',
        reliability: Reliability.parse(f['reliability']?.toString()),
        basis: switch (f['basis']?.toString()) {
          'CHECKLIST_ITEM' || 'REFERENCE_CLAIM' => 'CHECKLIST_ITEM',
          'GENERIC_QUALITY' => 'GENERIC_QUALITY',
          _ => 'MODEL_KNOWLEDGE',
        },
        alternativeExplanation: str(f['alternative_explanation']),
        variation: switch (f['legitimate_variation']?.toString()) {
          'LIKELY' => VariationCheck.likely,
          'POSSIBLE' => VariationCheck.possible,
          'RULED_OUT' => VariationCheck.ruledOut,
          _ => VariationCheck.notChecked,
        },
        partRequestId: requestIds.contains(f['part_request_id']?.toString()) ? f['part_request_id'].toString() : null,
        differenceKind: const {'DIFFERENT', 'ABSENT'}.contains(f['difference_kind']) ? f['difference_kind'] as String : 'NOT_APPLICABLE',
        detailKind: const {'MARKING', 'MATERIAL', 'CONSTRUCTION', 'LABEL', 'SOFTWARE', 'PACKAGING'}.contains(f['detail_kind'])
            ? f['detail_kind'] as String
            : 'OTHER',
        hardToCopy: f['hard_to_copy'] == true,
        counterfeitTell: f['counterfeit_tell'] == true,
        knowledgeScope: const {'THIS_GENERATION', 'MODEL_FAMILY', 'BRAND_WIDE'}.contains(f['knowledge_scope']) ? f['knowledge_scope'] as String : 'NOT_SURE',
      ));
    }

    return CombinedAnalysis(
      brand: str(ident['brand']),
      model: str(ident['model']),
      generation: str(ident['generation']),
      variant: str(ident['variant']),
      identityBasis: str(ident['basis']) ?? '',
      identityConsistent: ident['consistent_with_identification'] == true,
      findings: findings,
      contradictions: [
        for (final c in (json['cross_image_contradictions'] as List).whereType<Map>())
          if (str(c['description']) != null)
            CrossPhotoContradiction(
              description: str(c['description'])!,
              photoIds: photos(c['image_ids']),
              severity: const {'minor', 'moderate', 'critical'}.contains(c['severity']) ? c['severity'] as String : 'moderate',
              identityRelated: c['identity_related'] == true,
            ),
      ],
      proposedVerdict: verdict!,
      reasoning: str(json['verdict_reasoning']) ?? '',
      summaryPoints: [
        for (final s in (json['summary_points'] as List? ?? const []))
          if (str(s) != null) str(s)!,
      ],
      unresolved: [
        for (final u in (json['unresolved'] as List).whereType<Map>())
          if (str(u['issue']) != null)
            UnresolvedItem(
              str(u['issue'])!,
              requestIds.contains(u['resolving_photo']?.toString()) ? u['resolving_photo'].toString() : null,
              str(u['resolving_check']),
            ),
      ],
      independentVerification: [
        for (final v in (json['independent_verification'] as List? ?? const []))
          if (str(v) != null) str(v)!,
      ].take(2).toList(),
      droppedFindings: dropped,
    );
  }

  Map<String, dynamic> toJson() => {
        'identity_established': {
          'brand': brand,
          'model': model,
          'generation': generation,
          'variant': variant,
          'basis': identityBasis,
          'consistent_with_identification': identityConsistent,
        },
        'findings': findings.map((f) => f.toJson()).toList(),
        'cross_image_contradictions': contradictions.map((c) => c.toJson()).toList(),
        'proposed_verdict': proposedVerdict,
        'verdict_reasoning': reasoning,
        'summary_points': summaryPoints,
        'unresolved': unresolved.map((u) => u.toJson()).toList(),
        'independent_verification': independentVerification,
        'dropped_findings': droppedFindings,
      };
}

/// Validates the combined analysis and decides the verdict with explicit
/// rules. Gemini proposes; these rules decide whether the proposal is
/// supported. A proposal the rules do not support becomes "Not sure"; the
/// rules never turn a "Not sure" proposal into a definitive verdict. There is
/// no external research: findings rest on Gemini's own knowledge and the
/// app checklist, and are never presented as manufacturer verification.
///
/// * a detail that is not visible is never evidence either way;
/// * generic quality never proves authenticity;
/// * a detail Gemini is not sure applies (or that is specific to a
///   generation that is not established) does not count;
/// * observations of one physical part count once;
/// * a device screen and printed/engraved text never serve as the
///   hard-to-copy match;
/// * a missing detail counts only if the checklist documents it;
/// * with an unknown brand there is no verdict;
/// * Authentic: three independent specific matches on different parts, one
///   of them hard to copy, seen in two or more photos, nothing material
///   against, no unsettled per-photo difference, identity consistent;
/// * Replica: a decisive checklist difference (clearly visible, reliable,
///   variations ruled out) or material differences on two independent
///   parts; a difference known only from Gemini's knowledge is never
///   decisive on its own.
abstract final class FinalVerdictValidator {
  static final RegExp _conditions = RegExp(
    r'\b(glare|reflection|lighting|shadow|blur|out of focus|focus|compression|pixelat|resolution|angle|perspective|exposure|too dark|too bright|dirt|grime|wear|worn|scratch)',
    caseSensitive: false,
  );
  static final RegExp _deviceScreen = RegExp(r'\b(screen|display info|settings|about page|software|app|pairing|watchos|firmware)', caseSensitive: false);

  static const _groupSynonyms = {
    'digital': 'crown',
    'caseback': 'back',
    'rear': 'back',
    'about': 'device',
    'software': 'device',
    'settings': 'device',
    'screws': 'back',
    'fasteners': 'back',
    'sensors': 'sensor',
  };

  /// Independence group of a part: its first word, with a few synonyms, so
  /// "back", "back material" and "back fasteners" count as one part.
  static String group(String area) {
    final words = area.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'detail';
    return _groupSynonyms[words.first] ?? words.first;
  }

  static Reliability _down(Reliability r) => switch (r) {
        Reliability.high => Reliability.medium,
        _ => Reliability.low,
      };

  static EngineResult validate({
    required ResolvedProfile profile,
    required List<PhotoEvidence> photos,
    required ProductReference checklist,
    required CombinedAnalysis analysis,
    EngineResult? preliminary,
  }) {
    final trace = <String>[];
    final byId = {for (final p in photos) p.photoId: p};
    final evaluatedModel = profile.evaluatedModelLabel;
    final modelKnown = profile.identity.modelFamily.isKnown || analysis.model != null;
    final generationKnown = profile.identity.generation.isKnown || analysis.generation != null;
    // Nothing can be authentic or a replica of an unknown brand.
    final brandKnown = profile.identity.brand.isKnown || analysis.brand != null;

    final records = <EvidenceRecord>[];
    final decisiveGroups = <String>{};
    final hardGroups = <String>{};
    final unclearHard = <(String, String)>[]; // (photoId, feature)

    for (final f in analysis.findings) {
      var claim = f.claimId == 'none' ? null : checklist.claim(f.claimId);
      // Fallback reconciliation for unmapped checklist claims (incorrect evidence-ID mapping)
      if (claim == null && f.claimId != 'none') {
        final match = checklist.claims.where((c) {
          if (c.id.toLowerCase() == f.claimId.toLowerCase()) return true;
          if (c.checkpointId != null && (c.checkpointId == f.claimId || c.checkpointId == f.partRequestId)) return true;
          return false;
        }).firstOrNull;
        if (match != null) {
          claim = match;
        }
      }
      final fromKnowledge = claim == null;
      final generic = f.basis == 'GENERIC_QUALITY' || (claim?.isGeneric ?? false);
      final marking = f.detailKind == 'MARKING';
      final deviceReported = claim?.kind == 'SOFTWARE' || f.detailKind == 'SOFTWARE' ||
          _deviceScreen.hasMatch('${claim?.area ?? f.area} ${f.feature}');
      final notes = <String>[];

      var reliability = f.reliability;
      if (f.visibility == 'PARTIAL' && reliability == Reliability.high) {
        reliability = Reliability.medium;
        notes.add('partly visible');
      }
      final penalised = f.photoIds.every((id) => (byId[id]?.quality.fineDetailPenalty ?? 0) >= 2);
      if (penalised) {
        reliability = _down(reliability);
        notes.add('photo not sharp enough for fine detail');
      }

      var direction = switch (f.comparison) {
        'MATCHES' => EvidenceDirection.supportsAuthentic,
        'CONFLICTS' => EvidenceDirection.supportsCounterfeit,
        _ => EvidenceDirection.unclear,
      };
      if (f.visibility == 'OBSCURED') {
        direction = EvidenceDirection.unclear;
        notes.add('obscured: never counted either way');
      }
      if (claim != null && claim.specificity == ClaimSpecificity.modelSpecific && !modelKnown) {
        direction = EvidenceDirection.unclear;
        notes.add('model-specific detail, but the model is not established');
      }
      if (fromKnowledge && !generic) {
        if (f.knowledgeScope == 'NOT_SURE') {
          direction = EvidenceDirection.unclear;
          notes.add('Gemini was not sure this detail applies to this item');
        } else if (f.knowledgeScope == 'THIS_GENERATION' && !generationKnown) {
          direction = EvidenceDirection.unclear;
          notes.add('generation-specific detail, but the generation is not established');
        }
      }
      // A missing detail only counts when the checklist documents that the
      // genuine item has it, the area is clearly photographed and the brand
      // is known. A missing logo on an unknown brand proves nothing.
      if (direction == EvidenceDirection.supportsCounterfeit && f.differenceKind == 'ABSENT') {
        if (!(brandKnown && f.visibility == 'CLEAR' && claim != null && claim.documented)) {
          direction = EvidenceDirection.unclear;
          notes.add('an absent detail that is not documented for the genuine item');
        }
      }

      // Weight: checklist items by their catalog flags; details from
      // Gemini's knowledge at most medium, except a clearly seen,
      // hard-to-copy physical detail supporting authenticity.
      var weight = generic
          ? Weight.low
          : claim != null
              ? (claim.hardToCopy ? Weight.high : Weight.medium)
              : (reliability == Reliability.high && f.visibility == 'CLEAR' && f.hardToCopy && !marking && f.knowledgeScope != 'BRAND_WIDE'
                  ? Weight.high
                  : reliability == Reliability.low
                      ? Weight.low
                      : Weight.medium);

      var variation = f.variation;
      if (direction == EvidenceDirection.supportsAuthentic && generic) {
        direction = EvidenceDirection.neutral;
        notes.add('general quality only, not proof');
      }
      if (direction == EvidenceDirection.supportsCounterfeit) {
        if (claim != null && claim.decisiveIfDifferent) {
          weight = Weight.high;
        } else if (fromKnowledge && weight == Weight.high) {
          weight = Weight.medium;
        }
        if (f.alternativeExplanation != null && _conditions.hasMatch(f.alternativeExplanation!)) {
          reliability = _down(reliability);
          notes.add('photo conditions could explain it');
        }
        if (variation == VariationCheck.likely) {
          direction = EvidenceDirection.unclear;
          notes.add('a legitimate variation likely explains it');
        } else if (variation == VariationCheck.possible) {
          weight = Weight.low;
          notes.add('a legitimate variation might explain it');
        }
        if (generic) weight = Weight.low;
      }
      if (direction == EvidenceDirection.supportsAuthentic && deviceReported && weight == Weight.high) {
        weight = Weight.medium; // a clone can display false values
        notes.add('device-reported: not hard-to-copy proof');
      }

      // Independence = the physical part (the app's photo part when given).
      final group = f.partRequestId ?? FinalVerdictValidator.group(claim?.area ?? f.area);
      final source = generic
          ? 'General quality, not proof'
          : claim != null
              ? (claim.documented ? 'App checklist (not verified manufacturer data)' : "App checklist item, judged with Gemini's own knowledge")
              : "Gemini's own knowledge (${f.knowledgeScope.toLowerCase().replaceAll('_', ' ')}), not externally verified";
      final kind = deviceReported
          ? EvidenceKind.deviceReported
          : f.visibility == 'CLEAR' && f.comparison != 'UNCLEAR'
              ? EvidenceKind.observedFact
              : EvidenceKind.aiInterpretation;
      final interpretation = switch (direction) {
        EvidenceDirection.supportsAuthentic => claim != null && claim.documented ? 'Matches the checklist: ${claim.detail}' : 'Consistent with the genuine product',
        EvidenceDirection.supportsCounterfeit => claim != null && claim.documented ? 'Differs from the checklist: ${claim.detail}' : 'Differs from the genuine product',
        EvidenceDirection.neutral => 'General quality only; it does not show the item is genuine',
        _ => 'Could not be judged from the photos',
      };

      final material = direction == EvidenceDirection.supportsCounterfeit && reliability.atLeast(Reliability.medium) && weight.atLeast(Weight.medium);
      final decisive = material &&
          reliability == Reliability.high &&
          f.visibility == 'CLEAR' &&
          (variation == VariationCheck.ruledOut || variation == VariationCheck.notChecked) &&
          weight == Weight.high;
      final support = direction == EvidenceDirection.supportsAuthentic && reliability.atLeast(Reliability.medium) && weight.atLeast(Weight.medium);
      if (decisive) decisiveGroups.add(group);
      // Printed or engraved text and logos are what copies imitate best:
      // they never serve as the hard-to-copy match.
      if (support && weight == Weight.high && !marking) hardGroups.add(group);
      if (direction == EvidenceDirection.unclear && (claim?.hardToCopy ?? f.hardToCopy)) unclearHard.add((f.photoIds.first, f.feature));

      // One record per photo for the per-part report; the group makes them
      // count once.
      for (final pid in f.photoIds) {
        final p = byId[pid];
        records.add(EvidenceRecord(
          featureId: claim?.id ?? 'x_$group',
          featureName: f.feature,
          group: group,
          photoId: pid,
          photoTitle: p?.requestTitle ?? pid,
          observation: f.observed,
          interpretation: interpretation,
          evaluatedModel: evaluatedModel,
          referenceSource: source,
          direction: direction,
          reliability: reliability,
          weight: weight,
          kind: kind,
          variation: variation,
          variationNote: f.alternativeExplanation,
          alternativeExplanation: f.alternativeExplanation,
          engineNotes: [
            ...notes,
            if (decisive) 'decisive',
            if (f.photoIds.length > 1) 'seen in ${f.photoIds.length} photos',
          ],
        ));
      }
    }

    // Contradictions between photos.
    var identityConsistent = analysis.identityConsistent;
    for (var i = 0; i < analysis.contradictions.length; i++) {
      final c = analysis.contradictions[i];
      final critical = c.severity == 'critical';
      if (critical && c.identityRelated) identityConsistent = false;
      records.add(EvidenceRecord(
        featureId: 'cross_photo_$i',
        featureName: c.identityRelated ? 'Photos disagree about the model' : 'Photos disagree',
        group: c.identityRelated ? 'cross_photo_identity' : 'cross_photo_$i',
        photoId: c.photoIds.isEmpty ? (photos.isEmpty ? 'overview' : photos.first.photoId) : c.photoIds.first,
        photoTitle: 'Across photos',
        observation: c.description,
        interpretation: c.description,
        evaluatedModel: evaluatedModel,
        referenceSource: 'Comparison between your photos',
        direction: c.severity == 'minor' ? EvidenceDirection.unclear : EvidenceDirection.supportsCounterfeit,
        reliability: critical ? Reliability.high : Reliability.medium,
        weight: critical ? Weight.medium : Weight.low,
        kind: EvidenceKind.aiInterpretation,
        variation: VariationCheck.ruledOut,
        engineNotes: const ['from the combined cross-photo comparison'],
      ));
    }

    // ------------------------------------------------------ aggregation
    bool isSupport(EvidenceRecord r) =>
        r.direction == EvidenceDirection.supportsAuthentic && r.reliability.atLeast(Reliability.medium) && r.weight.atLeast(Weight.medium);
    bool isMaterial(EvidenceRecord r) =>
        r.direction == EvidenceDirection.supportsCounterfeit && r.reliability.atLeast(Reliability.medium) && r.weight.atLeast(Weight.medium);

    final supportGroups = {for (final r in records.where(isSupport)) r.group};
    final counterfeitGroups = {for (final r in records.where(isMaterial)) r.group};
    final supportPhotos = {for (final r in records.where(isSupport)) r.photoId};
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final corroborated = isSupport(r)
          ? supportGroups.difference({r.group}).isNotEmpty
          : isMaterial(r) && counterfeitGroups.difference({r.group}).isNotEmpty;
      if (corroborated != r.corroborated) records[i] = r.copyWith(corroborated: corroborated);
    }

    // Serious differences the per-photo checks found must be confirmed or
    // settled by the combined comparison; until then Authentic is blocked.
    final claimByCheckpoint = {
      for (final c in checklist.claims)
        if (c.checkpointId != null) c.checkpointId!: c,
    };
    final unresolvedPrior = <EvidenceRecord>[];
    for (final r in preliminary?.records ?? const <EvidenceRecord>[]) {
      final serious = r.direction == EvidenceDirection.supportsCounterfeit &&
          r.reliability.atLeast(Reliability.medium) &&
          r.weight.atLeast(Weight.medium) &&
          r.variation != VariationCheck.likely;
      if (!serious) continue;
      final claim = claimByCheckpoint[r.featureId];
      final confirmed = counterfeitGroups.contains(r.group) ||
          (claim != null && analysis.findings.any((f) => f.claimId == claim.id && f.comparison == 'CONFLICTS'));
      final settledAsMatch = (claim != null && analysis.findings.any((f) => f.claimId == claim.id && f.comparison == 'MATCHES')) ||
          analysis.findings.any((f) =>
              (FinalVerdictValidator.group(f.partRequestId ?? '') == r.group || FinalVerdictValidator.group(f.area) == r.group) &&
              f.comparison == 'MATCHES');
      final settledAsVariation = analysis.findings.any((f) =>
          (claim != null && f.claimId == claim.id || FinalVerdictValidator.group(f.partRequestId ?? '') == r.group || FinalVerdictValidator.group(f.area) == r.group) &&
          (f.variation == VariationCheck.likely || f.alternativeExplanation != null));

      if (!confirmed && !settledAsMatch && !settledAsVariation) {
        unresolvedPrior.add(r);
      }
    }
    if (unresolvedPrior.isNotEmpty) {
      trace.add('unresolved per-photo differences: ${unresolvedPrior.map((r) => r.featureId).toSet().join(', ')}');
    }

    final allowsAuthentic = profile.profile.policy.allowsAuthentic;
    final contested = decisiveGroups.isNotEmpty && hardGroups.length >= 2;

    trace.add('${analysis.findings.length} finding(s) over ${photos.length} photo(s); support groups $supportGroups '
        '(hard to copy $hardGroups), conflict groups $counterfeitGroups, decisive $decisiveGroups');

    final proposed = switch (analysis.proposedVerdict) {
      'AUTHENTIC' => Verdict.likelyAuthentic,
      'REPLICA' => Verdict.likelyReplica,
      _ => Verdict.inconclusive,
    };

    Verdict verdict = proposed;
    String validationResult = 'agreed';
    String? disagreementReason;

    final readableSupportPhotos = {
      for (final r in records.where(isSupport))
        if (byId[r.photoId]?.quality.detailReadability != 'NOT_READABLE') r.photoId,
    };

    // Lightweight Technical Validation (§1, §7):
    // Gemini is the visual decision-maker. Only intercept when technical integrity,
    // brand establishment, cross-photo identity, or internal contradictions fail.
    if (!brandKnown) {
      verdict = Verdict.inconclusive;
      validationResult = 'overridden_to_inconclusive';
      disagreementReason = 'brand_not_established';
      trace.add('lightweight validation: brand is not established -> inconclusive');
    } else if (contested) {
      verdict = Verdict.inconclusive;
      validationResult = 'overridden_to_inconclusive';
      disagreementReason = 'contested_evidence';
      trace.add('lightweight validation: contested evidence (decisive difference and hard-to-copy matches) -> inconclusive');
    } else if (proposed == Verdict.likelyAuthentic) {
      if (!identityConsistent) {
        verdict = Verdict.inconclusive;
        validationResult = 'overridden_to_inconclusive';
        disagreementReason = 'contradictory_model_identity';
        trace.add('lightweight validation: cross-photo identity contradicts -> inconclusive');
      } else
      if (counterfeitGroups.isNotEmpty || decisiveGroups.isNotEmpty) {
        verdict = Verdict.inconclusive;
        validationResult = 'overridden_to_inconclusive';
        disagreementReason = 'unresolved_counterfeit_findings';
        trace.add('lightweight validation: Gemini proposed AUTHENTIC but documented counterfeit findings: $counterfeitGroups $decisiveGroups');
      } else if (unresolvedPrior.isNotEmpty) {
        verdict = Verdict.inconclusive;
        validationResult = 'overridden_to_inconclusive';
        disagreementReason = 'unsettled_prior_differences';
        trace.add('lightweight validation: Gemini proposed AUTHENTIC but prior per-photo differences unsettled: ${unresolvedPrior.map((r) => r.featureId).join(', ')}');
      } else if (supportGroups.isEmpty) {
        verdict = Verdict.inconclusive;
        validationResult = 'overridden_to_inconclusive';
        disagreementReason = 'unsupported_authentic_claim';
        trace.add('lightweight validation: Gemini proposed AUTHENTIC with 0 supporting features');
      } else if (supportPhotos.length < 2 || readableSupportPhotos.length < 2) {
        verdict = Verdict.inconclusive;
        validationResult = 'overridden_to_inconclusive';
        disagreementReason = 'insufficient_photo_corroboration';
        trace.add('lightweight validation: Gemini proposed AUTHENTIC but evidence lacks readable multi-photo corroboration');
      } else if (supportGroups.length < 2) {
        verdict = Verdict.inconclusive;
        validationResult = 'overridden_to_inconclusive';
        disagreementReason = 'insufficient_independent_parts';
        trace.add('lightweight validation: Gemini proposed AUTHENTIC but only ${supportGroups.length} independent part shown (same detail does not count as independent)');
      } else if (!allowsAuthentic) {
        verdict = Verdict.inconclusive;
        validationResult = 'overridden_to_inconclusive';
        disagreementReason = 'category_policy_disallows_authentic';
        trace.add('lightweight validation: Gemini proposed AUTHENTIC but category policy does not allow authentic');
      } else {
        verdict = Verdict.likelyAuthentic;
        validationResult = 'agreed';
        trace.add('lightweight validation: Gemini proposed AUTHENTIC accepted directly with ${supportGroups.length} feature groups across ${supportPhotos.length} photo(s)');
      }
    } else if (proposed == Verdict.likelyReplica) {
      final hasObservedConflicts = counterfeitGroups.isNotEmpty ||
          decisiveGroups.isNotEmpty ||
          analysis.findings.any((f) => f.comparison == 'CONFLICTS' && f.visibility != 'OBSCURED' && f.variation != VariationCheck.likely);
      if (!hasObservedConflicts) {
        verdict = Verdict.inconclusive;
        validationResult = 'overridden_to_inconclusive';
        disagreementReason = 'unsupported_counterfeit_claim';
        trace.add('lightweight validation: proposed REPLICA with 0 observed discrepancies');
      } else {
        verdict = Verdict.likelyReplica;
        validationResult = 'agreed';
        trace.add('lightweight validation: Gemini proposed REPLICA accepted directly with ${counterfeitGroups.length} conflicting groups');
      }
    } else {
      // Gemini proposed NOT_SURE
      verdict = Verdict.inconclusive;
      validationResult = 'agreed';
      trace.add('lightweight validation: Gemini proposed NOT_SURE accepted');
    }

    if (disagreementReason != null) {
      trace.add('disagreement analysis: proposed=${analysis.proposedVerdict} result=$validationResult reason=$disagreementReason');
    }
    if (analysis.reasoning.isNotEmpty) trace.add('Gemini reasoning: ${analysis.reasoning}');

    // ------------------------------------------------------------- gaps
    final gaps = <EngineGap>[];
    if (verdict == Verdict.inconclusive) {
      Set<String> targets(String? requestId) => requestId == null ? const {} : (profile.request(requestId)?.checkpointIds.toSet() ?? const {});
      if (!brandKnown) {
        gaps.add(const EngineGap(
          type: GapType.identity,
          description: 'The brand could not be established, so there is nothing to compare the item with. A photo of the logo or label would help.',
        ));
      }
      if (contested) {
        gaps.add(const EngineGap(type: GapType.contested, description: 'Some details match the genuine product closely while one clearly differs.'));
      }
      if (!identityConsistent) {
        gaps.add(const EngineGap(type: GapType.identity, description: 'Your photos disagree about which model this is.'));
      }
      for (final r in unresolvedPrior.take(2)) {
        gaps.add(EngineGap(
          type: GapType.contested,
          description: 'The close check of the ${r.photoTitle.toLowerCase()} found the ${r.featureName.toLowerCase()} different from the genuine product, '
              'and the full comparison of your photos did not settle it.',
          targetCheckpointIds: {r.featureId},
        ));
      }
      for (final (pid, feature) in unclearHard.take(1)) {
        gaps.add(EngineGap(
          type: GapType.unclearPhoto,
          description: 'The ${feature.toLowerCase()} could not be checked in the ${(byId[pid]?.requestTitle ?? 'photo').toLowerCase()}.',
          retakeRequestId: byId[pid]?.isInitialPhoto == true ? null : byId[pid]?.requestId,
        ));
      }
      if (counterfeitGroups.isEmpty && brandKnown && !allowsAuthentic) {
        gaps.add(const EngineGap(type: GapType.noAuthenticCriteria, description: 'The app has no reliable criteria to confirm this kind of item as genuine.'));
      }
      if (supportGroups.isNotEmpty && (supportPhotos.length < 2 || readableSupportPhotos.length < 2)) {
        gaps.add(const EngineGap(
          type: GapType.independentGroups,
          description: 'Everything that matched came from one photo; a second photo must confirm it.',
        ));
      }
      if (supportGroups.length < 2 && brandKnown) {
        final n = 2 - supportGroups.length;
        gaps.add(EngineGap(
          type: GapType.independentGroups,
          description: '$n more independent detail${n == 1 ? ' is' : 's are'} needed to confirm the result.',
        ));
      }
      for (final u in analysis.unresolved.take(3)) {
        gaps.add(EngineGap(type: GapType.independentGroups, description: u.issue, targetCheckpointIds: targets(u.requestId), fix: u.check));
      }
      if (gaps.isEmpty) {
        gaps.add(const EngineGap(
          type: GapType.independentGroups,
          description: 'Additional photographic evidence is needed to reliably verify this item.',
        ));
      }
    }

    final strength = switch (verdict) {
      Verdict.likelyAuthentic => hardGroups.isNotEmpty || supportGroups.length >= 2 ? EvidenceStrength.strong : EvidenceStrength.moderate,
      Verdict.likelyReplica => decisiveGroups.isNotEmpty || counterfeitGroups.length >= 2 ? EvidenceStrength.strong : EvidenceStrength.moderate,
      Verdict.inconclusive => EvidenceStrength.limited,
    };

    EvidenceRecord best(Iterable<EvidenceRecord> rs) => rs.reduce((a, b) {
          // Reliability is declared high-to-low, so invert its index.
          int score(EvidenceRecord r) => r.weight.index * 10 + (Reliability.values.length - 1 - r.reliability.index) * 3;
          return score(b) > score(a) ? b : a;
        });
    List<EvidenceRecord> bestPerGroup(bool Function(EvidenceRecord) keep) {
      final groups = <String, List<EvidenceRecord>>{};
      for (final r in records.where(keep)) {
        groups.putIfAbsent(r.group, () => []).add(r);
      }
      return [for (final g in groups.values) best(g)];
    }

    final progress = switch (verdict) {
      Verdict.inconclusive => (supportGroups.isEmpty ? 0.3 : (supportGroups.length / 3).clamp(0.4, 0.85)),
      _ => 1.0,
    };

    String redactSensitive(String text) {
      return text.replaceAllMapped(RegExp(r'\b([A-Z0-9]{8,14})\b', caseSensitive: false), (m) {
        final val = m[1]!;
        if (val.length <= 4) return val;
        return '${val.substring(0, 2)}***${val.substring(val.length - 2)}';
      });
    }

    final diagnostics = <String, dynamic>{
      'identified_product': profile.identity.modelFamily.value ?? profile.profile.name,
      'identified_model': evaluatedModel,
      'submitted_photos_count': photos.length,
      'features_per_photo': <String, List<String>>{
        for (final p in photos)
          p.photoId: [
            for (final f in analysis.findings)
              if (f.photoIds.contains(p.photoId)) f.feature,
          ],
      },
      'gemini_proposed_verdict': analysis.proposedVerdict,
      'supporting_findings': [
        for (final r in records.where(isSupport)) '${r.photoId}: ${r.featureName} - ${redactSensitive(r.observation)}',
      ],
      'contradictory_findings': [
        for (final r in records.where(isMaterial)) '${r.photoId}: ${r.featureName} - ${redactSensitive(r.observation)}',
      ],
      'validation_result': validationResult,
      'disagreement_reason': ?disagreementReason,
      'final_verdict': verdict.code,
      'inconclusive_reasons': [for (final g in gaps) g.description],
    };

    return EngineResult(
      verdict: verdict,
      sufficient: verdict != Verdict.inconclusive,
      awaitingFinalEvaluation: false,
      strength: strength,
      records: records,
      supporting: bestPerGroup(isSupport),
      contradicting: bestPerGroup(isMaterial),
      neutral: records.where((r) => r.direction == EvidenceDirection.neutral).toList(),
      unclear: records.where((r) => r.direction == EvidenceDirection.unclear).toList(),
      authenticGroups: supportGroups,
      hardToCopyGroups: hardGroups,
      counterfeitGroups: counterfeitGroups,
      decisiveCount: decisiveGroups.length,
      contested: contested,
      identityMet: identityConsistent,
      observedCheckpointIds: preliminary?.observedCheckpointIds ?? const {},
      gaps: gaps,
      // What is still open: Gemini's unresolved issues, or the rule gaps
      // when it listed none (a "not sure" always says why).
      remainingUncertainty: {
        ...analysis.unresolved.map((u) => u.issue),
        if (analysis.unresolved.isEmpty) ...gaps.map((g) => g.description),
      }.take(3).toList(),
      progress: progress,
      progressLabel: verdict == Verdict.inconclusive ? '${supportGroups.length} independent detail${supportGroups.length == 1 ? '' : 's'} confirmed' : 'Complete',
      trace: trace,
      diagnostics: diagnostics,
    );
  }
}
