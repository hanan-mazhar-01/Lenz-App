import '../models/capture_guide.dart';
import '../models/evidence_record.dart';
import '../models/product_identity.dart';
import 'profiles/profile_catalog.dart';

/// How precisely the product must be identified before a checkpoint may be
/// used as counterfeit evidence, or before a profile allows an authentic
/// result.
enum ModelLevel {
  none,

  /// Brand known (e.g. brand-imitation markings).
  brand,

  /// Model family known (e.g. "Apple Watch Ultra", "Neverfull").
  family,

  /// Generation / reference known (e.g. "Series 9", "126610LN").
  generation;

  bool satisfiedBy(ProductIdentity id) => switch (this) {
        ModelLevel.none => true,
        ModelLevel.brand => id.brand.isKnown,
        ModelLevel.family => id.brand.isKnown && id.modelFamily.isKnown,
        ModelLevel.generation => id.brand.isKnown && id.modelFamily.isKnown && id.generation.isKnown,
      };
}

/// One authentication-relevant feature of a product: the unit the photo
/// analysis reports on and the engine reasons about.
class Checkpoint {
  final String id;

  /// Short plain name, shown in reports.
  final String name;

  /// Independence group. Checkpoints in one group describe the same
  /// underlying feature; they never corroborate each other.
  final String group;

  /// What to examine (sent to the model).
  final String check;

  /// Expected on a genuine item, only where it is documented well enough to
  /// state. Null means the model must rely on its own knowledge, and the
  /// resulting evidence is labelled that way.
  final String? genuine;

  /// A known replica tell, same caveat as [genuine].
  final String? replicaTell;

  /// How much a clean result can support authenticity. [Weight.none] for
  /// design features counterfeiters reliably copy (logo placement, colour
  /// accents, printed wording): matching them only identifies the item.
  final Weight authenticWeight;

  /// How much a clear mismatch can point to a replica.
  final Weight counterfeitWeight;

  /// Execution that replicas rarely get right and that can be judged from a
  /// photo. An authentic result needs at least one of these.
  final bool hardToCopy;

  /// Needs a sharp close-up; blur, glare or distance make it unreliable.
  final bool needsFineDetail;

  /// Identification level required before a mismatch counts against the item.
  final ModelLevel requires;

  /// Differs between generations; never compare across generations.
  final bool generationSpecific;

  /// Reveals which model / generation the item is (labels, device info).
  final bool identityEstablishing;

  /// Legitimate variations to rule out before calling a mismatch counterfeit.
  final String? variationNote;

  const Checkpoint({
    required this.id,
    required this.name,
    required this.group,
    required this.check,
    this.genuine,
    this.replicaTell,
    required this.authenticWeight,
    required this.counterfeitWeight,
    this.hardToCopy = false,
    this.needsFineDetail = false,
    this.requires = ModelLevel.family,
    this.generationSpecific = false,
    this.identityEstablishing = false,
    this.variationNote,
  });
}

/// A photo the app can ask for.
class PhotoRequestTemplate {
  final String id;

  /// Name of the product part, e.g. "Back of the watch".
  final String title;

  /// What to photograph, e.g. "Photograph the back of your Apple Watch.
  /// Keep the sensors and surrounding engravings clearly visible."
  final String instruction;

  /// Why this photo helps, in one short sentence.
  final String why;
  final CaptureGuideType guide;
  final CaptureTips tips;

  /// Checkpoints this photo can show.
  final List<String> checkpointIds;

  /// Default order (1 = ask first) before model-specific re-ranking.
  final int basePriority;

  /// A screenshot is acceptable (device information screens).
  final bool screenshotOk;

  /// A verified reference photo of this part for the identified model, when
  /// one ships with the app. None do yet: the bundled product images are
  /// marketing thumbnails of specific items, not verified references, so the
  /// capture screen shows a drawn framing illustration instead.
  final String? exampleAsset;

  /// Words that describe this part, used to match what a photo shows.
  final List<String> aliases;

  const PhotoRequestTemplate({
    required this.id,
    required this.title,
    required this.instruction,
    required this.why,
    required this.guide,
    this.tips = CaptureTips.standard,
    required this.checkpointIds,
    required this.basePriority,
    this.screenshotOk = false,
    this.exampleAsset,
    this.aliases = const [],
  });
}

class VerdictPolicy {
  /// Independent feature groups that must support authenticity.
  final int minAuthenticGroups;

  /// Of those, how many must be hard-to-copy execution features.
  final int minHardToCopyGroups;

  /// Identification needed before an authentic result is allowed.
  final ModelLevel identityForAuthentic;

  /// False where the app has no reliable product-specific criteria: it can
  /// still spot obvious imitation, but never calls such an item authentic.
  final bool allowsAuthentic;

  /// Checkpoints that must have a clean, reliable observation before an
  /// authentic result, e.g. a smartwatch's own model-information screen:
  /// exteriors are copied well enough that they cannot carry the result alone.
  final Set<String> requiredForAuthentic;

  /// Distinct photos the supporting evidence must come from. One photo read
  /// in one model call cannot corroborate itself (real fragrance scans,
  /// 2026-09-27, reached "authentic" from a single bottle photo).
  final int minAuthenticPhotos;

  const VerdictPolicy({
    this.minAuthenticGroups = 2,
    this.minHardToCopyGroups = 1,
    this.identityForAuthentic = ModelLevel.family,
    this.allowsAuthentic = true,
    this.requiredForAuthentic = const {},
    this.minAuthenticPhotos = 2,
  });
}

/// Generation-specific facts for products that change between generations.
class GenerationSpec {
  final String id;
  final String label;

  /// Lower-case substrings of model/generation text that select this spec.
  final List<String> hints;

  /// Facts documented for this generation. Only used when the generation is
  /// established; never applied to another generation.
  final List<String> notes;

  const GenerationSpec({
    required this.id,
    required this.label,
    required this.hints,
    required this.notes,
  });
}

class EvidenceProfile {
  final String id;
  final String name;

  /// Category codes this profile applies to.
  final Set<String> categoryCodes;

  /// Lower-case substrings of the brand that select this profile.
  final List<String> brandHints;

  /// Lower-case substrings of product type / model text that select it.
  final List<String> textHints;

  /// Higher wins when several profiles match.
  final int specificity;

  final List<Checkpoint> checkpoints;
  final List<PhotoRequestTemplate> requests;
  final VerdictPolicy policy;

  /// Traps: things that look like counterfeit evidence but usually aren't.
  final List<String> cautions;

  /// What the owner can do beyond photos. Shown as next steps; the app never
  /// claims to have done them.
  final List<String> verificationSteps;
  final List<GenerationSpec> generations;

  /// True for fallback profiles that hold no product-specific knowledge.
  final bool isGeneric;

  const EvidenceProfile({
    required this.id,
    required this.name,
    required this.categoryCodes,
    this.brandHints = const [],
    this.textHints = const [],
    this.specificity = 0,
    required this.checkpoints,
    required this.requests,
    this.policy = const VerdictPolicy(),
    this.cautions = const [],
    this.verificationSteps = const [],
    this.generations = const [],
    this.isGeneric = false,
  });

  bool get hasGenerations => generations.isNotEmpty;
}

/// A profile resolved for one identified product.
class ResolvedProfile {
  final EvidenceProfile profile;
  final ProductIdentity identity;

  /// Generation facts, only when the generation text matched a spec.
  final GenerationSpec? generation;

  const ResolvedProfile({
    required this.profile,
    required this.identity,
    this.generation,
  });

  String get id => profile.id;

  Checkpoint? checkpoint(String id) {
    for (final c in profile.checkpoints) {
      if (c.id == id) return c;
    }
    return null;
  }

  PhotoRequestTemplate? request(String id) {
    for (final r in profile.requests) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<Checkpoint> checkpointsFor(String requestId) {
    final r = request(requestId);
    if (r == null) return const [];
    return [for (final id in r.checkpointIds) ?checkpoint(id)];
  }

  Set<String> get hardToCopyGroups =>
      {for (final c in profile.checkpoints) if (c.hardToCopy) c.group};

  String get evaluatedModelLabel => identity.evaluatedModelLabel(mentionGeneration: profile.hasGenerations);

  /// Same profile, re-resolved after identity information changed.
  ResolvedProfile withIdentity(ProductIdentity newIdentity) => EvidenceProfileRegistry.resolve(newIdentity);
}

/// Registry of evidence profiles. Add a category or model by adding a
/// profile to [ProfileCatalog]; no UI or engine changes are needed.
abstract final class EvidenceProfileRegistry {
  static List<EvidenceProfile> get profiles => ProfileCatalog.all;

  static EvidenceProfile byId(String id) =>
      profiles.firstWhere((p) => p.id == id, orElse: () => ProfileCatalog.generic);

  /// Picks the most specific profile for [identity]. Unknown categories and
  /// unmatched products get the generic profile, which holds no invented
  /// product criteria.
  static ResolvedProfile resolve(ProductIdentity identity) {
    final code = identity.categoryCode.toUpperCase();
    final brand = (identity.brand.value ?? '').toLowerCase();
    final text = identity.searchText;

    EvidenceProfile? best;
    for (final p in profiles) {
      if (p.isGeneric) continue;
      if (!p.categoryCodes.contains(code)) continue;
      // Unhinted profiles are category defaults. Hinted ones need a brand or
      // product-type match.
      final hinted = p.brandHints.isNotEmpty || p.textHints.isNotEmpty;
      final brandHit = brand.isNotEmpty && p.brandHints.any(brand.contains);
      final textHit = p.textHints.any(text.contains);
      if (hinted && !brandHit && !textHit) continue;
      if (best == null || p.specificity > best.specificity) best = p;
    }
    final profile = best ?? ProfileCatalog.generic;

    GenerationSpec? gen;
    if (profile.hasGenerations) {
      // The generation text itself decides; the family name is only used
      // when no generation is stated (e.g. "Apple Watch Ultra" -> Ultra
      // family facts). This keeps "Apple Watch Series" from matching the
      // hint "se".
      final genText = (identity.generation.value ?? identity.exactModel.value ?? identity.modelFamily.value ?? '')
          .toLowerCase();
      for (final g in profile.generations) {
        if (g.hints.any(genText.contains)) {
          gen = g;
          break;
        }
      }
    }

    return ResolvedProfile(profile: profile, identity: identity, generation: gen);
  }
}
