import '../core/config/authenticity_engine_config.dart';
import '../data/evidence_profiles.dart';
import '../models/evidence_record.dart';
import 'evidence_decision_engine.dart';

/// Model-specific ranking of the candidate photos (evidence recommendation
/// step). Advisory: it re-orders the profile's own requests and can never
/// add a new kind of photo.
class AiEvidenceRanking {
  final Map<String, AiRankEntry> entries;
  final List<String> modelNotes;
  final String model;

  const AiEvidenceRanking({this.entries = const {}, this.modelNotes = const [], this.model = ''});

  factory AiEvidenceRanking.fromJson(Map<String, dynamic> json, Set<String> validIds) {
    final entries = <String, AiRankEntry>{};
    for (final e in (json['ranked'] as List? ?? const []).whereType<Map>()) {
      final id = e['request_id']?.toString() ?? '';
      if (!validIds.contains(id) || entries.containsKey(id)) continue;
      entries[id] = AiRankEntry(
        value: (e['discriminative_value']?.toString() ?? 'MEDIUM').toUpperCase(),
        assessable: e['photo_assessable'] != false,
        checks: [
          for (final c in (e['model_specific_checks'] as List? ?? const []))
            if (c.toString().trim().isNotEmpty) c.toString().trim(),
        ].take(3).toList(),
        reason: e['reason']?.toString().trim() ?? '',
      );
    }
    return AiEvidenceRanking(
      entries: entries,
      modelNotes: [
        for (final n in (json['model_notes'] as List? ?? const []))
          if (n.toString().trim().isNotEmpty) n.toString().trim(),
      ].take(3).toList(),
      model: (json['_meta'] as Map?)?['model']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'entries': {for (final e in entries.entries) e.key: e.value.toJson()},
        'model_notes': modelNotes,
        'model': model,
      };
}

class AiRankEntry {
  /// HIGH / MEDIUM / LOW discriminative value for the exact model.
  final String value;
  final bool assessable;

  /// Model-specific things to look for (AI knowledge, unverified).
  final List<String> checks;
  final String reason;

  const AiRankEntry({required this.value, required this.assessable, this.checks = const [], this.reason = ''});

  Map<String, dynamic> toJson() => {'value': value, 'assessable': assessable, 'checks': checks, 'reason': reason};
}

class PlannedRequest {
  final PhotoRequestTemplate template;

  /// Lower is better.
  final double score;

  /// HIGH / MEDIUM / LOW, from the AI ranking or derived from the profile.
  final String discriminativeValue;
  final List<String> aiChecks;

  /// Why this photo would help now, in plain words.
  final String reason;
  final bool isRetake;

  const PlannedRequest({
    required this.template,
    required this.score,
    required this.discriminativeValue,
    this.aiChecks = const [],
    required this.reason,
    this.isRetake = false,
  });

  String get id => template.id;

  String get usefulnessLabel => switch (discriminativeValue) {
        'HIGH' => 'Very useful',
        'LOW' => 'Extra',
        _ => 'Useful',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'score': double.parse(score.toStringAsFixed(2)),
        'value': discriminativeValue,
        'reason': reason,
        if (isRetake) 'retake': true,
      };
}

class EvidencePlan {
  /// Photos that could still help, best first.
  final List<PlannedRequest> ranked;

  /// The single most informative next photo, if any.
  final PlannedRequest? recommended;

  /// True when the evidence already supports a verdict: any further photo
  /// is optional.
  final bool nextOptional;
  final bool limitReached;

  /// Why nothing is recommended, when [recommended] is null.
  final String? noRecommendationReason;

  const EvidencePlan({
    required this.ranked,
    required this.recommended,
    required this.nextOptional,
    required this.limitReached,
    this.noRecommendationReason,
  });

  Map<String, dynamic> toJson() => {
        'recommended': recommended?.toJson(),
        'next_optional': nextOptional,
        'limit_reached': limitReached,
        'ranked': ranked.map((r) => r.toJson()).toList(),
        if (noRecommendationReason != null) 'none_because': noRecommendationReason,
      };
}

/// Chooses the next photo. Deterministic for a given profile, ranking,
/// photo set and engine result, so repeat scans of the same item are asked
/// for the same photos.
abstract final class EvidencePlanner {
  static EvidencePlan plan({
    required ResolvedProfile profile,
    required List<PhotoEvidence> photos,
    required EngineResult result,
    AiEvidenceRanking? ranking,
    Set<String> skipped = const {},
    Map<String, int> retakeSuggestions = const {},
    int maxPhotos = AuthenticityEngineConfig.maxPhotosPerScan,
  }) {
    final limitReached = photos.length >= maxPhotos;
    final taken = {for (final p in photos) p.requestId};
    final observed = result.observedCheckpointIds;
    final gaps = result.gaps;

    final candidates = <PlannedRequest>[];

    // Retake: a key detail was photographed but could not be judged.
    for (final g in gaps.where((g) => g.type == GapType.unclearPhoto && g.retakeRequestId != null)) {
      final t = profile.request(g.retakeRequestId!);
      if (t == null) continue;
      if ((retakeSuggestions[t.id] ?? 0) >= AuthenticityEngineConfig.maxRetakeSuggestionsPerPart) continue;
      final gapIndex = gaps.indexOf(g);
      candidates.add(PlannedRequest(
        template: t,
        score: -6.0 + gapIndex,
        discriminativeValue: 'HIGH',
        aiChecks: ranking?.entries[t.id]?.checks ?? const [],
        reason: '${g.description} ${g.fix != null && g.fix!.isNotEmpty ? g.fix! : 'Try again closer, in even light.'}',
        isRetake: true,
      ));
    }

    for (final t in profile.profile.requests) {
      if (taken.contains(t.id) || skipped.contains(t.id)) continue;
      final ai = ranking?.entries[t.id];
      var score = t.basePriority.toDouble();
      var value = derivedValue(profile, t);
      if (ai != null) {
        value = ai.value;
        // Model-specific knowledge carries as much weight as the most
        // pressing evidence gap, so it can re-order the profile's defaults.
        if (ai.value == 'HIGH') score -= 3;
        if (ai.value == 'LOW') score += 3;
        if (!ai.assessable) score += 5;
      }

      // What would this photo resolve?
      EngineGap? bestGap;
      for (var i = 0; i < gaps.length; i++) {
        final g = gaps[i];
        if (g.type == GapType.unclearPhoto || g.type == GapType.noAuthenticCriteria) continue;
        if (t.checkpointIds.any(g.targetCheckpointIds.contains)) {
          score -= i == 0 ? 3 : 1.5;
          bestGap ??= g;
        }
      }

      // Little new information if everything it shows has already been seen.
      final unseen = t.checkpointIds.where((id) => !observed.contains(id)).length;
      if (unseen == 0) score += 3;

      candidates.add(PlannedRequest(
        template: t,
        score: score,
        discriminativeValue: value,
        aiChecks: ai?.checks ?? const [],
        reason: _reason(bestGap, t, result.sufficient),
      ));
    }

    candidates.sort((a, b) {
      final c = a.score.compareTo(b.score);
      if (c != 0) return c;
      final p = a.template.basePriority.compareTo(b.template.basePriority);
      return p != 0 ? p : a.id.compareTo(b.id);
    });

    String? none;
    PlannedRequest? recommended;
    if (limitReached) {
      none = 'You have added the maximum of $maxPhotos photos for one scan.';
    } else if (candidates.isEmpty) {
      none = 'Every suggested photo has been added or skipped.';
    } else {
      recommended = candidates.first;
    }

    return EvidencePlan(
      ranked: limitReached ? const [] : candidates,
      recommended: recommended,
      nextOptional: result.sufficient,
      limitReached: limitReached,
      noRecommendationReason: none,
    );
  }

  /// HIGH / MEDIUM / LOW from the profile alone, before model-specific ranking.
  static String derivedValue(ResolvedProfile profile, PhotoRequestTemplate t) {
    final cps = profile.checkpointsFor(t.id);
    if (cps.any((c) => c.hardToCopy || c.counterfeitWeight == Weight.decisive)) return 'HIGH';
    if (cps.any((c) => c.authenticWeight.atLeast(Weight.medium) || c.counterfeitWeight.atLeast(Weight.high))) {
      return 'MEDIUM';
    }
    return 'LOW';
  }

  static String _reason(EngineGap? gap, PhotoRequestTemplate t, bool sufficient) {
    if (sufficient) return 'Optional extra check. ${t.why}';
    if (gap == null) return t.why;
    final lead = switch (gap.type) {
      GapType.contested => 'Some details look genuine and others do not.',
      GapType.variationCheck => 'One unusual detail may be a legitimate variation.',
      GapType.corroborateCounterfeit => 'One detail looked wrong; an independent second detail is needed before calling it a replica.',
      GapType.identity => 'The exact model is not confirmed yet.',
      GapType.requiredCheck => 'Copies look the same outside; the product\'s own information screen is needed to confirm it.',
      GapType.hardToCopy => 'Copies usually match the outside design, so a hard-to-copy detail is needed.',
      GapType.independentGroups => 'Another independent detail is needed to confirm the result.',
      GapType.unclearPhoto || GapType.noAuthenticCriteria => '',
    };
    return '$lead ${t.why}'.trim();
  }
}
