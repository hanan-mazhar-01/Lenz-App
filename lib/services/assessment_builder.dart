import '../data/evidence_profiles.dart';
import '../models/authentication_assessment.dart';
import '../models/authentication_result.dart';
import '../models/evidence_record.dart';
import '../models/product_identity.dart';
import 'evidence_decision_engine.dart';
import 'evidence_planner.dart';

/// Builds the structured assessment (§8) from the engine result. The
/// explanation is written here, from the same records the verdict came from,
/// so the words can never disagree with the verdict.
abstract final class AssessmentBuilder {
  static AuthenticationAssessment build({
    required ResolvedProfile profile,
    required List<PhotoEvidence> photos,
    required EngineResult result,
    required EvidencePlan plan,
    required String categoryLabel,
    String? geminiReasoning,
  }) {
    final id = profile.identity;
    final modelLabel = profile.evaluatedModelLabel;
    final brand = id.brand.value ?? '';

    final verdict = switch (result.verdict) {
      Verdict.likelyAuthentic => AssessmentVerdict.authenticVisual,
      Verdict.likelyReplica => AssessmentVerdict.replica,
      Verdict.inconclusive => AssessmentVerdict.unableToVerify,
    };

    final rec = plan.recommended;
    final next = rec == null
        ? null
        : NextPhotoRecommendation(
            requestId: rec.id,
            title: rec.isRetake ? 'Retake: ${rec.template.title}' : rec.template.title,
            instruction: rec.template.instruction,
            reason: rec.reason,
            optional: result.sufficient,
          );

    final steps = <String>[
      if (!result.sufficient && next != null) 'Add the ${next.title.toLowerCase()} photo: ${next.reason}',
      if (result.verdict == Verdict.likelyReplica)
        'If you bought this as genuine, contact the seller or the marketplace, and keep these photos as a record.',
      ...profile.profile.verificationSteps,
    ];

    final reliabilityNote = switch (result.verdict) {
      Verdict.likelyAuthentic => '${result.authenticGroups.length} independent features support authenticity '
          '(${result.hardToCopyGroups.length} of them hard to copy); no material differences found.',
      Verdict.likelyReplica => '${result.counterfeitGroups.length} independent feature(s) differ from the genuine model'
          '${result.decisiveCount > 0 ? ', including a difference no genuine version has' : ''}.',
      Verdict.inconclusive => result.gaps.isEmpty ? 'Not enough evidence either way.' : result.gaps.first.description,
    };

    final assessment = AuthenticationAssessment(
      productCategory: categoryLabel,
      brand: brand,
      model: [id.modelFamily.value, id.generation.value].whereType<String>().join(' ').trim(),
      modelIdentification: ModelIdentificationStatus(
        evaluatedModel: modelLabel,
        brandStatus: id.brand.status.code,
        modelStatus: id.modelFamily.status.code,
        generationStatus: id.generation.status.code,
        generation: id.generation.value,
        basis: [
          if (id.modelFamily.basis.isNotEmpty) id.modelFamily.basis,
          if (id.generation.basis.isNotEmpty && id.generation.basis != id.modelFamily.basis) id.generation.basis,
        ].join('; '),
        uncertainAttributes: id.uncertainAttributes,
      ),
      availableEvidence: [
        for (final p in photos)
          EvidencePhotoSummary(
            photoId: p.photoId,
            title: p.requestTitle,
            summary: p.summary,
            qualityNote: p.quality.fix,
          ),
      ],
      supportingObservations: result.supporting,
      contradictoryObservations: result.contradicting,
      evidenceReliability: result.strength.label,
      evidenceReliabilityNote: reliabilityNote,
      recommendedNextPhoto: next,
      sufficientEvidence: result.sufficient,
      verdict: verdict,
      explanation: (geminiReasoning != null && geminiReasoning.trim().isNotEmpty)
          ? geminiReasoning.trim()
          : explanation(result: result, modelLabel: modelLabel, brand: brand),
      remainingUncertainty: result.remainingUncertainty,
      recommendedNextSteps: _dedupe(steps),
    );
    return assessment;
  }

  static String explanation({required EngineResult result, required String modelLabel, required String brand}) {
    final subject = modelLabel == 'unidentified item' ? 'this item' : 'the $modelLabel';
    String features(List<EvidenceRecord> rs, int n) => _list(rs.take(n).map((r) {
          final what = r.interpretation.isNotEmpty ? r.interpretation : r.observation;
          return '${r.featureName.toLowerCase()} (${_trimDot(what)})';
        }));
    final verifyWith = brand.isEmpty ? 'the manufacturer' : brand;
    switch (result.verdict) {
      case Verdict.likelyAuthentic:
        return 'Your photos are visually consistent with an authentic ${subject.replaceFirst('the ', '')}. '
            '${result.authenticGroups.length} independent details matched, including ${features(result.supporting, 2)}. '
            'No material differences from the genuine model were found. '
            'This is a visual assessment only; it has not been verified with $verifyWith.';
      case Verdict.likelyReplica:
        final checked = result.contradicting.any((r) => r.variation == VariationCheck.ruledOut);
        return 'Your photos show details that differ from how $subject is made: ${features(result.contradicting, 2)}. '
            '${checked ? 'These were checked against legitimate versions of the model and none explains them. ' : ''}'
            'This is a visual assessment, not a manufacturer verification.';
      case Verdict.inconclusive:
        final b = StringBuffer('The photos do not yet establish whether $subject is genuine. ');
        if (result.gaps.isNotEmpty) b.write('${result.gaps.first.description} ');
        if (result.supporting.isNotEmpty) {
          b.write('What we could check looked consistent: ${features(result.supporting, 2)}. ');
        }
        if (result.contradicting.isNotEmpty) {
          b.write('Needs a closer look: ${features(result.contradicting, 1)}. ');
        }
        return b.toString().trim();
    }
  }

  static String _trimDot(String s) => s.trim().replaceAll(RegExp(r'[.\s]+$'), '');

  static String _list(Iterable<String> items) {
    final l = items.toList();
    if (l.isEmpty) return 'no specific details';
    if (l.length == 1) return l.first;
    return '${l.sublist(0, l.length - 1).join(', ')} and ${l.last}';
  }

  static List<String> _dedupe(List<String> input) {
    final seen = <String>{};
    return [for (final s in input) if (s.trim().isNotEmpty && seen.add(s.toLowerCase())) s];
  }

  /// Short status line for the identity card, e.g. "Model confirmed ·
  /// generation probable".
  static String identityStatusLine(ProductIdentity id, {bool mentionGeneration = false}) {
    final parts = <String>[
      'Brand ${id.brand.status.label.toLowerCase()}',
      'model ${id.modelFamily.status.label.toLowerCase()}',
      if (mentionGeneration) 'generation ${id.generation.status.label.toLowerCase()}',
    ];
    return parts.join(' · ');
  }
}
