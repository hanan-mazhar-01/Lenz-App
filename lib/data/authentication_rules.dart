import '../models/evidence.dart';
import '../models/product.dart';

/// The inspection dimensions the engine reasons about internally (§18).
/// These names are for prompts and rules — they are never shown to the user.
enum InspectionDimension {
  logo('Logo', 'Logo'),
  typography('Typography', 'Lettering'),
  stitching('Stitching', 'Stitching'),
  material('Material & Finish', 'Material and finish'),
  shape('Shape & Proportions', 'Shape'),
  hardware('Hardware', 'Metal parts'),
  serial('Serial / Reference', 'Numbers and engraving'),
  labels('Labels & Tags', 'Tags and labels'),
  packaging('Packaging', 'Box and papers');

  /// Internal label used in model prompts.
  final String label;

  /// Plain-English name shown to the user.
  final String simpleLabel;

  const InspectionDimension(this.label, this.simpleLabel);
}

/// One data-driven inspection instruction.
///
/// [check], [genuineSignal] and [replicaSignal] are the strict, technical form
/// that goes to the model. [simpleTip] is the same idea rewritten for a person
/// holding the item — the UI only ever shows that one (§25, §26).
class InspectionRule {
  final InspectionDimension dimension;
  final String check;
  final String genuineSignal;
  final String replicaSignal;
  final String simpleTip;

  const InspectionRule({
    required this.dimension,
    required this.check,
    required this.genuineSignal,
    required this.replicaSignal,
    required this.simpleTip,
  });
}

/// Shape of the on-camera framing guide for an evidence step (§14).
enum CaptureFrame {
  /// Large frame for the whole object.
  fullItem(0.82, 1.15),

  /// Round guide — watch dials, caseback, buttons.
  circle(0.62, 1.0),

  /// Small landscape frame — tags, labels, serial plates.
  smallRect(0.7, 0.55),

  /// Tall frame — bag interiors, garment fronts.
  tall(0.62, 1.3),

  /// Tight square for a macro detail — stitching, engraving.
  closeUp(0.52, 1.0);

  /// Fraction of the screen width the guide should span.
  final double widthFactor;

  /// Height relative to the guide's width.
  final double aspect;

  const CaptureFrame(this.widthFactor, this.aspect);

  /// Picks a guide from the evidence id so AI-invented steps still get a
  /// sensible frame.
  static CaptureFrame forEvidence(String evidenceId, {String title = ''}) {
    final s = '$evidenceId $title'.toLowerCase();
    if (s.contains('full') || s.contains('whole') || s.contains('overview')) {
      return CaptureFrame.fullItem;
    }
    if (s.contains('dial') || s.contains('crown') || s.contains('caseback') ||
        s.contains('back of') || s.contains('button') || s.contains('bezel')) {
      return CaptureFrame.circle;
    }
    if (s.contains('tag') || s.contains('label') || s.contains('serial') ||
        s.contains('number') || s.contains('code') || s.contains('box')) {
      return CaptureFrame.smallRect;
    }
    if (s.contains('inside') || s.contains('interior') || s.contains('garment') ||
        s.contains('front')) {
      return CaptureFrame.tall;
    }
    return CaptureFrame.closeUp;
  }
}

/// A requested photo, written the way the user reads it.
class EvidenceBlueprint {
  /// Internal id. Technical naming is fine here — it is never displayed.
  final String id;

  /// Short, instantly understandable title (§11).
  final String title;

  /// One short sentence: what to do (§12).
  final String guide;

  /// One short sentence: why we want it (§13).
  final String why;

  final EvidenceWeight weight;

  const EvidenceBlueprint({
    required this.id,
    required this.title,
    required this.guide,
    required this.why,
    required this.weight,
  });

  EvidenceItem toEvidenceItem(int index) => EvidenceItem(
        id: id,
        index: index,
        title: title,
        guide: guide,
        reason: why,
        isRequired: weight == EvidenceWeight.critical || weight == EvidenceWeight.high,
        weight: weight,
        status: EvidenceStatus.pending,
        whyCorrect: why,
        whatToLookFor: [why],
      );
}

/// A resolved set of rules for a category, optionally narrowed by brand/model.
class AuthenticationRuleSet {
  final ProductCategory category;
  final String? brand;
  final String? model;
  final List<EvidenceBlueprint> evidenceBlueprint;
  final List<InspectionRule> inspectionRules;

  const AuthenticationRuleSet({
    required this.category,
    this.brand,
    this.model,
    required this.evidenceBlueprint,
    required this.inspectionRules,
  });

  List<String> get criticalEvidenceIds => evidenceBlueprint
      .where((e) => e.weight == EvidenceWeight.critical)
      .map((e) => e.id)
      .toList();

  List<String> get highImportanceEvidenceIds =>
      evidenceBlueprint.where((e) => e.weight == EvidenceWeight.high).map((e) => e.id).toList();

  /// The strict briefing handed to the vision model. Stays technical on
  /// purpose — the user never sees this (§26, §32).
  String get inspectionBriefing {
    final buffer = StringBuffer();
    final byDimension = <InspectionDimension, List<InspectionRule>>{};
    for (final r in inspectionRules) {
      byDimension.putIfAbsent(r.dimension, () => []).add(r);
    }
    byDimension.forEach((dim, rules) {
      buffer.writeln('${dim.label.toUpperCase()}:');
      for (final r in rules) {
        buffer.writeln('- ${r.check}');
        buffer.writeln('  expected on genuine: ${r.genuineSignal}');
        buffer.writeln('  common on replicas: ${r.replicaSignal}');
      }
    });
    return buffer.toString().trim();
  }

  AuthenticationRuleSet mergedWith(AuthenticationRuleSet override) {
    return AuthenticationRuleSet(
      category: override.category,
      brand: override.brand ?? brand,
      model: override.model ?? model,
      evidenceBlueprint:
          override.evidenceBlueprint.isNotEmpty ? override.evidenceBlueprint : evidenceBlueprint,
      inspectionRules: [...inspectionRules, ...override.inspectionRules],
    );
  }

  EvidenceWeight weightFor(String evidenceId) {
    final id = evidenceId.toLowerCase();
    for (final b in evidenceBlueprint) {
      if (b.id.toLowerCase() == id) return b.weight;
    }
    return AuthenticationRules.inferWeight(evidenceId);
  }
}

/// Registry of category and model rule sets. Extend by adding entries here —
/// no new screens or branches are required (§20).
abstract final class AuthenticationRules {
  // ---------------------------------------------------------------- watches
  static const List<EvidenceBlueprint> _watch = [
    EvidenceBlueprint(
      id: 'full_watch',
      title: 'Full Watch',
      guide: 'Take a photo of the whole watch.',
      why: "We'll check the overall shape and proportions.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'dial',
      title: 'Dial',
      guide: 'Take a close-up of the front of the watch.',
      why: "We'll check the text, markers and hands.",
      weight: EvidenceWeight.critical,
    ),
    EvidenceBlueprint(
      id: 'crown',
      title: 'Crown',
      guide: 'Take a close-up of the small knob on the side.',
      why: "We'll check its shape and finish.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'caseback',
      title: 'Back',
      guide: 'Turn the watch over and take a photo of the back.',
      why: "We'll check the finish and any markings.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'bracelet_clasp',
      title: 'Bracelet / Clasp',
      guide: 'Show the strap and the clasp clearly.',
      why: "We'll check how well it's made.",
      weight: EvidenceWeight.medium,
    ),
    EvidenceBlueprint(
      id: 'reference_serial',
      title: 'Number / Engraving',
      guide: 'Take a close-up of any number or engraving on the watch.',
      why: "We'll check it matches this model.",
      weight: EvidenceWeight.critical,
    ),
  ];

  // ------------------------------------------------------------------- bags
  static const List<EvidenceBlueprint> _bag = [
    EvidenceBlueprint(
      id: 'full_bag',
      title: 'Full Bag',
      guide: 'Take a photo of the whole bag.',
      why: "We'll check the overall shape.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'logo_monogram',
      title: 'Logo',
      guide: 'Take a clear close-up of the logo.',
      why: "We'll check its shape, position and details.",
      weight: EvidenceWeight.critical,
    ),
    EvidenceBlueprint(
      id: 'interior',
      title: 'Inside',
      guide: 'Open the bag and take a photo of the inside.',
      why: "We'll check the lining and how it's made.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'production_code',
      title: 'Tag / Number',
      guide: 'Take a close-up of the tag or number inside.',
      why: "We'll check it matches this model.",
      weight: EvidenceWeight.critical,
    ),
    EvidenceBlueprint(
      id: 'stitching',
      title: 'Stitching',
      guide: 'Take a close-up of the stitching.',
      why: "We'll check the stitches are even.",
      weight: EvidenceWeight.medium,
    ),
    EvidenceBlueprint(
      id: 'hardware',
      title: 'Zipper / Hardware',
      guide: 'Show the zipper and metal parts clearly.',
      why: "We'll check their shape and finish.",
      weight: EvidenceWeight.medium,
    ),
  ];

  // --------------------------------------------------------------- sneakers
  static const List<EvidenceBlueprint> _sneaker = [
    EvidenceBlueprint(
      id: 'full_shoe',
      title: 'Full Shoe',
      guide: 'Take a photo of the whole shoe from the side.',
      why: "We'll check the overall shape.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'logo',
      title: 'Logo',
      guide: 'Take a close-up of the logo.',
      why: "We'll check its shape and position.",
      weight: EvidenceWeight.critical,
    ),
    EvidenceBlueprint(
      id: 'size_tag',
      title: 'Size Tag',
      guide: 'Take a photo of the tag inside the shoe.',
      why: "We'll check the text and numbers.",
      weight: EvidenceWeight.critical,
    ),
    EvidenceBlueprint(
      id: 'stitching',
      title: 'Stitching',
      guide: 'Take a close-up of the stitching.',
      why: "We'll check the stitches are even.",
      weight: EvidenceWeight.medium,
    ),
    EvidenceBlueprint(
      id: 'sole',
      title: 'Bottom',
      guide: 'Turn the shoe over and show the bottom.',
      why: "We'll check the pattern and shape.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'box_label',
      title: 'Box Label',
      guide: 'Take a photo of the label on the box.',
      why: "We'll check it matches the shoe.",
      weight: EvidenceWeight.low,
    ),
  ];

  // --------------------------------------------------------------- clothing
  static const List<EvidenceBlueprint> _clothing = [
    EvidenceBlueprint(
      id: 'full_garment',
      title: 'Full Item',
      guide: 'Lay it flat and take a photo of the whole item.',
      why: "We'll check the overall cut and shape.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'front_graphic',
      title: 'Logo / Design',
      guide: 'Take a clear photo of the logo or main design.',
      why: "We'll check its shape and detail.",
      weight: EvidenceWeight.critical,
    ),
    EvidenceBlueprint(
      id: 'neck_tag',
      title: 'Neck Tag',
      guide: 'Take a photo of the tag near the neck.',
      why: "We'll check the text and stitching.",
      weight: EvidenceWeight.critical,
    ),
    EvidenceBlueprint(
      id: 'wash_tag',
      title: 'Wash Tag',
      guide: 'Take a photo of the care tag inside.',
      why: "We'll check the codes match this item.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'stitching',
      title: 'Stitching',
      guide: 'Take a close-up of the stitching on a hem or sleeve.',
      why: "We'll check the stitches are even.",
      weight: EvidenceWeight.medium,
    ),
    EvidenceBlueprint(
      id: 'print_embroidery',
      title: 'Print / Embroidery',
      guide: 'Take a very close photo of the print or embroidery.',
      why: "We'll check how cleanly it's done.",
      weight: EvidenceWeight.medium,
    ),
  ];

  // ------------------------------------------------------------ accessories
  static const List<EvidenceBlueprint> _accessory = [
    EvidenceBlueprint(
      id: 'full_item',
      title: 'Full Item',
      guide: 'Take a photo of the whole item.',
      why: "We'll check the overall shape.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'brand_marking',
      title: 'Logo',
      guide: 'Take a close-up of the logo or brand name.',
      why: "We'll check its shape and details.",
      weight: EvidenceWeight.critical,
    ),
    EvidenceBlueprint(
      id: 'serial_code',
      title: 'Number / Engraving',
      guide: 'Take a close-up of any number or engraving.',
      why: "We'll check it matches this model.",
      weight: EvidenceWeight.critical,
    ),
    EvidenceBlueprint(
      id: 'material_finish',
      title: 'Close-up',
      guide: 'Take a close-up showing the surface and finish.',
      why: "We'll check the material quality.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'hardware',
      title: 'Clasp / Metal Parts',
      guide: 'Show any clasp, screw or metal parts clearly.',
      why: "We'll check their shape and finish.",
      weight: EvidenceWeight.medium,
    ),
    EvidenceBlueprint(
      id: 'packaging',
      title: 'Box / Papers',
      guide: 'Take a photo of the box or papers, if you have them.',
      why: "A small extra check — not essential.",
      weight: EvidenceWeight.low,
    ),
  ];

  // ------------------------------------------------ inspection rule library
  static const List<InspectionRule> _sharedRules = [
    InspectionRule(
      dimension: InspectionDimension.logo,
      check: 'Logo shape, placement, proportions, spacing and finishing.',
      genuineSignal: 'Even margins, consistent stroke weight, crisp terminations.',
      replicaSignal: 'Drifting baseline, uneven stroke weight, rounded or bled edges.',
      simpleTip: 'Look at the logo. The edges should be sharp and the spacing even.',
    ),
    InspectionRule(
      dimension: InspectionDimension.typography,
      check: 'Character shapes, kerning, weight and alignment of all printed text.',
      genuineSignal: 'Uniform kerning, sharp counters, consistent baseline.',
      replicaSignal: 'Cramped or loose kerning, thickened strokes, wrong glyph shapes.',
      simpleTip: 'Read the small text closely. Letters should be crisp and evenly spaced.',
    ),
    InspectionRule(
      dimension: InspectionDimension.material,
      check: 'Texture, surface consistency and finishing quality.',
      genuineSignal: 'Even grain, controlled sheen, no tooling residue.',
      replicaSignal: 'Repeating synthetic grain, uneven gloss, visible mould lines.',
      simpleTip: 'Feel the surface. It should look and feel even all over, not plasticky.',
    ),
    InspectionRule(
      dimension: InspectionDimension.shape,
      check: 'Silhouette, component relationships and alignment.',
      genuineSignal: 'Symmetric assembly with tight, even panel gaps.',
      replicaSignal: 'Asymmetry, proud edges, inconsistent gaps.',
      simpleTip: 'Check both sides match and the gaps between parts are even.',
    ),
    InspectionRule(
      dimension: InspectionDimension.serial,
      check: 'Serial/reference placement, formatting, typography and agreement with other evidence.',
      genuineSignal: 'Correct format for the model, consistent depth, agrees with other angles.',
      replicaSignal: 'Wrong length or format, shallow etch, contradicts another photo.',
      simpleTip: 'Look at the engraving. The letters should be clean, even and the same depth.',
    ),
  ];

  static const List<InspectionRule> _watchRules = [
    InspectionRule(
      dimension: InspectionDimension.hardware,
      check: 'Crown knurling, pusher machining and lug finishing.',
      genuineSignal: 'Machined teeth with clean edges; lugs flow smoothly into the case.',
      replicaSignal: 'Casting burrs, soft knurling, abrupt lug transitions.',
      simpleTip: 'Look at the small knob on the side. Its grooves should be sharp, not rounded.',
    ),
    InspectionRule(
      dimension: InspectionDimension.typography,
      check: 'Dial text print quality, marker alignment and lume application.',
      genuineSignal: 'Pad-printed text with sharp serifs; lume evenly filled to marker edges.',
      replicaSignal: 'Bleeding or grainy text; lume overflowing or pooled unevenly.',
      simpleTip: 'Look at the front. The text should be sharp and the markers evenly placed.',
    ),
    InspectionRule(
      dimension: InspectionDimension.material,
      check: 'Bracelet link solidity, end-link fit and clasp action.',
      genuineSignal: 'Solid links with no rattle; end links sit flush to the case.',
      replicaSignal: 'Hollow links, visible gaps at the lugs, loose clasp latching.',
      simpleTip: 'Shake the strap gently. It should feel solid with no rattle or gaps.',
    ),
  ];

  static const List<InspectionRule> _bagRules = [
    InspectionRule(
      dimension: InspectionDimension.stitching,
      check: 'Stitch pitch, thread angle, tension and edge finishing.',
      genuineSignal: 'Consistent pitch with a slight uniform diagonal; sealed edge paint.',
      replicaSignal: 'Variable pitch, loose or frayed thread, cracked or thick edge paint.',
      simpleTip: 'Check the stitches are evenly spaced with no loose threads.',
    ),
    InspectionRule(
      dimension: InspectionDimension.hardware,
      check: 'Zipper action, plating depth and engraving relief.',
      genuineSignal: 'Heavy hardware, even plating, crisply engraved marks.',
      replicaSignal: 'Light hollow hardware, thin plating, shallow or fuzzy engraving.',
      simpleTip: 'Hold the zipper. It should feel heavy and run smoothly.',
    ),
    InspectionRule(
      dimension: InspectionDimension.labels,
      check: 'Interior heat stamp and date code typography, placement and impression.',
      genuineSignal: 'Even impression depth with correctly spaced characters.',
      replicaSignal: 'Uneven depth, drifting alignment, wrong character shapes.',
      simpleTip: 'Look at the stamp inside. It should be pressed evenly, not patchy.',
    ),
  ];

  static const List<InspectionRule> _sneakerRules = [
    InspectionRule(
      dimension: InspectionDimension.stitching,
      check: 'Stitch density on the eyestay and quarter panel.',
      genuineSignal: 'Even stitches per inch with consistent tension.',
      replicaSignal: 'Loose or doubled stitching, frayed thread ends, punched-through holes.',
      simpleTip: 'Check the stitches around the laces are even and tight.',
    ),
    InspectionRule(
      dimension: InspectionDimension.labels,
      check: 'Inner size tag layout, font and production codes.',
      genuineSignal: 'Crisp thermal print with correct code structure for the model.',
      replicaSignal: 'Thickened or stamped-looking font, wrong code layout.',
      simpleTip: 'Look at the tag inside. The printing should be sharp, not thick or smudged.',
    ),
    InspectionRule(
      dimension: InspectionDimension.shape,
      check: 'Toe box curvature, midsole profile and tread geometry.',
      genuineSignal: 'Smooth upward toe curve, crisp moulded tread detail.',
      replicaSignal: 'Boxy or over-padded toe, soft or misaligned tread pattern.',
      simpleTip: 'Look at the toe from the side. It should curve up smoothly, not look boxy.',
    ),
  ];

  static const List<InspectionRule> _clothingRules = [
    InspectionRule(
      dimension: InspectionDimension.labels,
      check: 'Neck and care label weave, print and code structure.',
      genuineSignal: 'Tightly woven label, sharp print, codes matching the garment.',
      replicaSignal: 'Coarse weave, blurred print, generic or missing codes.',
      simpleTip: 'Check the neck tag. It should be tightly woven with clear printing.',
    ),
    InspectionRule(
      dimension: InspectionDimension.stitching,
      check: 'Hem and sleeve stitch type and density.',
      genuineSignal: 'Even chain or coverstitch with consistent tension.',
      replicaSignal: 'Skipped stitches, puckered seams, single-stitch where double expected.',
      simpleTip: 'Check the hems. The stitching should be even with no puckering.',
    ),
    InspectionRule(
      dimension: InspectionDimension.logo,
      check: 'Print registration and embroidery stitch direction.',
      genuineSignal: 'Perfect colour registration, dense uniform embroidery.',
      replicaSignal: 'Offset colour layers, sparse embroidery with visible backing.',
      simpleTip: 'Look closely at the print. Colours should line up with no blurry edges.',
    ),
  ];

  static AuthenticationRuleSet forCategory(ProductCategory category) {
    switch (category) {
      case ProductCategory.watches:
        return AuthenticationRuleSet(
          category: category,
          evidenceBlueprint: _watch,
          inspectionRules: const [..._sharedRules, ..._watchRules],
        );
      case ProductCategory.bags:
        return AuthenticationRuleSet(
          category: category,
          evidenceBlueprint: _bag,
          inspectionRules: const [..._sharedRules, ..._bagRules],
        );
      case ProductCategory.sneakers:
        return AuthenticationRuleSet(
          category: category,
          evidenceBlueprint: _sneaker,
          inspectionRules: const [..._sharedRules, ..._sneakerRules],
        );
      case ProductCategory.clothing:
        return AuthenticationRuleSet(
          category: category,
          evidenceBlueprint: _clothing,
          inspectionRules: const [..._sharedRules, ..._clothingRules],
        );
      case ProductCategory.accessories:
        return AuthenticationRuleSet(
          category: category,
          evidenceBlueprint: _accessory,
          inspectionRules: const [..._sharedRules],
        );
    }
  }

  /// Model-specific overlays. Add entries to sharpen a given model without
  /// touching any UI code.
  static final List<AuthenticationRuleSet> modelOverlays = [
    const AuthenticationRuleSet(
      category: ProductCategory.watches,
      brand: 'Rolex',
      model: 'Submariner',
      evidenceBlueprint: [],
      inspectionRules: [
        InspectionRule(
          dimension: InspectionDimension.serial,
          check: 'Rehaut engraving alignment relative to the minute track.',
          genuineSignal: 'Engraving precisely indexed to the markers with a coronet at 12:00.',
          replicaSignal: 'Engraving rotated or unevenly spaced against the minute track.',
          simpleTip:
              'Look at the thin ring just inside the glass. Its tiny text should line up with the markers.',
        ),
        InspectionRule(
          dimension: InspectionDimension.hardware,
          check: 'Triplock crown dot configuration under the coronet.',
          genuineSignal: 'Three evenly spaced dots beneath a cleanly formed coronet.',
          replicaSignal: 'Malformed coronet or irregular dot spacing.',
          simpleTip: 'Look at the knob on the side. There should be three neat dots under the crown symbol.',
        ),
      ],
    ),
  ];

  static AuthenticationRuleSet resolve({
    required ProductCategory category,
    String? brand,
    String? model,
  }) {
    var base = forCategory(category);
    final b = (brand ?? '').toLowerCase().trim();
    final m = (model ?? '').toLowerCase().trim();

    for (final overlay in modelOverlays) {
      if (overlay.category != category) continue;
      final ob = (overlay.brand ?? '').toLowerCase();
      final om = (overlay.model ?? '').toLowerCase();
      final brandMatches = ob.isEmpty || b.contains(ob);
      final modelMatches = om.isEmpty || m.contains(om) || b.contains(om);
      if (brandMatches && modelMatches) {
        base = base.mergedWith(overlay);
      }
    }
    return base;
  }

  /// Keyword weighting for evidence ids the model invents that aren't in a
  /// blueprint. Errs toward treating identity evidence as important and
  /// supporting material as minor.
  static EvidenceWeight inferWeight(String evidenceId) {
    final id = evidenceId.toLowerCase();
    const critical = ['serial', 'reference', 'date_code', 'datecode', 'dial', 'size_tag', 'neck_tag', 'heat_stamp', 'production', 'number', 'engrav'];
    const high = ['logo', 'monogram', 'marking', 'hallmark', 'caseback', 'interior', 'inside', 'sole', 'bottom', 'crown', 'graphic', 'back'];
    const low = ['box', 'packaging', 'paper', 'receipt', 'dustbag', 'dust_bag', 'card'];

    for (final k in low) {
      if (id.contains(k)) return EvidenceWeight.low;
    }
    for (final k in critical) {
      if (id.contains(k)) return EvidenceWeight.critical;
    }
    for (final k in high) {
      if (id.contains(k)) return EvidenceWeight.high;
    }
    return EvidenceWeight.medium;
  }
}
