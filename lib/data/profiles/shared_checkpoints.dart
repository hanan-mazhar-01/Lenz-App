import '../../models/evidence_record.dart';
import '../evidence_profiles.dart';

/// Checkpoints and cautions shared by several profiles.
abstract final class SharedCheckpoints {
  /// A marking that abbreviates, misspells or mimics a well-known brand
  /// ("Guci", "MK SHOES" with an unrelated logo presented as Michael Kors).
  /// The genuine brand never uses such a marking, so this rests on the
  /// brand alone, not the exact model.
  static const brandMarking = Checkpoint(
    id: 'brand_marking',
    name: 'Brand name and logo',
    group: 'brand_marking',
    check: 'Is the brand name or logo spelled and drawn exactly as the brand uses it, or is it an altered, '
        'abbreviated, misspelled or look-alike version of a well-known trademark?',
    replicaTell: 'Misspelled, abbreviated or look-alike brand marking; an unrelated logo next to a famous brand name.',
    authenticWeight: Weight.none,
    counterfeitWeight: Weight.decisive,
    requires: ModelLevel.brand,
    variationNote: 'An independent budget brand that does not imitate anyone is not a replica of anything; '
        'only a marking that imitates a specific brand counts.',
  );

  static const cautions = [
    'A detail that is not visible is NOT_VISIBLE, never INCONSISTENT. A missing serial-number photo is not evidence of anything.',
    'Lighting, glare, reflections, blur, compression, camera angle and lens distortion change how details look. If they could explain a difference, report UNCLEAR, not INCONSISTENT.',
    'Normal wear, scratches, dirt and fading are not counterfeit indicators.',
    'Colour differences between photos are usually white balance, not materials.',
    'Copied design is not authenticity evidence: logo placement, colour accents, overall shape and printed wording are what counterfeiters reproduce first. Seeing them only identifies what the item is made to look like.',
    'Do not estimate precise physical measurements (millimetres, angles) from perspective-distorted photos. Compare proportions only.',
  ];
}
