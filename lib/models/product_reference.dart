/// What the final combined analysis checks the item against.
///
/// There is no external research: Gemini uses its own knowledge of the
/// identified model inside the combined call, and this class carries only
/// the app's built-in checklist for the product type (which parts to check,
/// the few documented details, and which differences no genuine version
/// has). The checklist is guidance and a safeguard, not verified
/// manufacturer data, and never the primary source of product knowledge.
library;

import '../data/evidence_profiles.dart';
import 'evidence_record.dart';

enum ClaimSpecificity {
  modelSpecific('MODEL_SPECIFIC'),
  brandSpecific('BRAND_SPECIFIC'),
  generic('GENERIC');

  final String code;
  const ClaimSpecificity(this.code);
}

/// One checklist item the combined analysis must look at.
class ReferenceClaim {
  final String id;
  final String feature;

  /// Part of the product (used for independence when no photo part is given).
  final String area;
  final String detail;

  /// SOFTWARE for device screens, CONSTRUCTION otherwise.
  final String kind;
  final ClaimSpecificity specificity;
  final bool hardToCopy;
  final String? appliesTo;

  /// A genuine unit never differs here, so a clear, variation-checked
  /// difference is decisive.
  final bool decisiveIfDifferent;

  /// The catalog checkpoint the item comes from.
  final String? checkpointId;

  const ReferenceClaim({
    required this.id,
    required this.feature,
    required this.area,
    required this.detail,
    required this.kind,
    required this.specificity,
    required this.hardToCopy,
    this.appliesTo,
    this.decisiveIfDifferent = false,
    this.checkpointId,
  });

  bool get isGeneric => specificity == ClaimSpecificity.generic;

  /// False for "what to check" items that do not document what the genuine
  /// item looks like.
  bool get documented => !detail.startsWith('What to check:');

  Map<String, dynamic> toJson() => {
        'id': id,
        'feature': feature,
        'area': area,
        'detail': detail,
        'kind': kind,
        'specificity': specificity.code,
        'hardToCopy': hardToCopy,
        if (appliesTo != null) 'appliesTo': appliesTo,
        if (decisiveIfDifferent) 'counterfeitTell': true,
        if (checkpointId != null) 'checkpointId': checkpointId,
      };
}

class ProductReference {
  final List<ReferenceClaim> claims;

  const ProductReference({this.claims = const []});

  /// The built-in checklist for the resolved profile.
  factory ProductReference.checklist(ResolvedProfile profile) {
    final claims = <ReferenceClaim>[];
    final modelProfile = profile.profile.brandHints.isNotEmpty || profile.generation != null;
    for (final c in profile.profile.checkpoints) {
      final documented = c.genuine != null && c.genuine!.trim().isNotEmpty;
      claims.add(ReferenceClaim(
        id: 'b${claims.length + 1}',
        feature: c.name,
        area: c.group.replaceAll('_', ' '),
        detail: documented ? c.genuine! : 'What to check: ${c.check}',
        kind: RegExp(r'device_info|software|about|settings').hasMatch(c.id) ? 'SOFTWARE' : 'CONSTRUCTION',
        specificity: documented && (c.generationSpecific || modelProfile) ? ClaimSpecificity.modelSpecific : ClaimSpecificity.brandSpecific,
        hardToCopy: c.hardToCopy,
        appliesTo: c.generationSpecific ? profile.generation?.label : null,
        decisiveIfDifferent: c.counterfeitWeight == Weight.decisive,
        checkpointId: c.id,
      ));
    }
    return ProductReference(claims: claims);
  }

  bool get usable => claims.isNotEmpty;

  ReferenceClaim? claim(String id) {
    for (final c in claims) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// One plain sentence for the report on what the result rests on.
  static const String basisSentence =
      "Compared with Gemini's own knowledge of this model and the app's checklist; "
      'this is a photographic assessment, not a verification by the manufacturer.';

  Map<String, dynamic> toJson() => {'claims': claims.map((c) => c.toJson()).toList()};
}
