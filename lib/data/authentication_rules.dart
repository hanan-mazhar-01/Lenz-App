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
  display('Display & Sensors', 'Screen and sensors'),
  lens('Lenses', 'Lenses'),
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

  /// True for photos of identity markings (serial, model code, date code,
  /// size tag). Without one, the result's confidence ceiling is lower.
  final bool identityMarking;

  const EvidenceBlueprint({
    required this.id,
    required this.title,
    required this.guide,
    required this.why,
    required this.weight,
    this.identityMarking = false,
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

  /// Category-specific traps: things that look like counterfeit evidence
  /// in photos but usually aren't. Sent to the model verbatim.
  final List<String> cautions;

  /// When true, an overlay's rules replace the category rules instead of
  /// adding to them. Needed where the base rules would actively mislead,
  /// e.g. mechanical-watch dial rules applied to an Apple Watch screen.
  final bool replacesBaseRules;

  /// Human label for the inspection profile in prompts and logs.
  final String profileName;

  const AuthenticationRuleSet({
    required this.category,
    this.brand,
    this.model,
    required this.evidenceBlueprint,
    required this.inspectionRules,
    this.cautions = const [],
    this.replacesBaseRules = false,
    this.profileName = '',
  });

  /// Evidence ids that show an identity marking.
  Set<String> get identityEvidenceIds =>
      evidenceBlueprint.where((e) => e.identityMarking).map((e) => e.id).toSet();

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
      inspectionRules: override.replacesBaseRules
          ? override.inspectionRules
          : [...inspectionRules, ...override.inspectionRules],
      cautions: override.replacesBaseRules ? override.cautions : [...cautions, ...override.cautions],
      profileName: override.profileName.isNotEmpty ? override.profileName : profileName,
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
      identityMarking: true,
    ),
  ];

  /// Apple Watch and other smartwatches: a screen, sensors and a digital
  /// crown, none of which mechanical-watch rules describe correctly.
  static const List<EvidenceBlueprint> _smartwatch = [
    EvidenceBlueprint(
      id: 'front_display',
      title: 'Front',
      guide: 'Take a photo of the front with the screen on.',
      why: "We'll check the screen shape, edges and bezel.",
      weight: EvidenceWeight.critical,
    ),
    EvidenceBlueprint(
      id: 'back_sensor',
      title: 'Back',
      guide: 'Turn the watch over and photograph the sensor on the back.',
      why: "We'll check the sensor layout and the text around it.",
      weight: EvidenceWeight.critical,
      identityMarking: true,
    ),
    EvidenceBlueprint(
      id: 'side_crown',
      title: 'Crown Side',
      guide: 'Take a close-up of the side with the crown and button.',
      why: "We'll check the crown, button and openings.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'other_side',
      title: 'Other Side',
      guide: 'Photograph the opposite side of the watch.',
      why: "We'll check the speaker openings and case edge.",
      weight: EvidenceWeight.medium,
    ),
    EvidenceBlueprint(
      id: 'band_connector',
      title: 'Band / Connector',
      guide: 'Show where the band slides into the watch.',
      why: "We'll check the band slot and release button.",
      weight: EvidenceWeight.medium,
    ),
    EvidenceBlueprint(
      id: 'about_screen',
      title: 'About Screen',
      guide: 'Open Settings > General > About and photograph the screen.',
      why: "We'll read the model details the watch reports.",
      weight: EvidenceWeight.high,
      identityMarking: true,
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
      identityMarking: true,
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
      identityMarking: true,
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
      identityMarking: true,
    ),
    EvidenceBlueprint(
      id: 'wash_tag',
      title: 'Wash Tag',
      guide: 'Take a photo of the care tag inside.',
      why: "We'll check the codes match this item.",
      weight: EvidenceWeight.high,
      identityMarking: true,
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

  // ---------------------------------------------------------------- wallets
  static const List<EvidenceBlueprint> _wallet = [
    EvidenceBlueprint(
      id: 'full_wallet',
      title: 'Full Wallet',
      guide: 'Take a photo of the whole wallet, closed.',
      why: "We'll check the overall shape and finish.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'logo',
      title: 'Logo',
      guide: 'Take a clear close-up of the logo or brand stamp.',
      why: "We'll check its shape, depth and spacing.",
      weight: EvidenceWeight.critical,
    ),
    EvidenceBlueprint(
      id: 'interior_slots',
      title: 'Inside',
      guide: 'Open it and photograph the card slots.',
      why: "We'll check how the inside is made.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'production_code',
      title: 'Stamp / Number',
      guide: 'Take a close-up of any code, stamp or "Made in" text inside.',
      why: "We'll check it matches this model.",
      weight: EvidenceWeight.critical,
      identityMarking: true,
    ),
    EvidenceBlueprint(
      id: 'edges_stitching',
      title: 'Edges / Stitching',
      guide: 'Take a close-up of an edge and its stitching.',
      why: "We'll check the edge paint and stitches.",
      weight: EvidenceWeight.medium,
    ),
    EvidenceBlueprint(
      id: 'hardware',
      title: 'Zipper / Snap',
      guide: 'Show any zipper, snap or metal part clearly.',
      why: "We'll check its shape and engraving.",
      weight: EvidenceWeight.medium,
    ),
  ];

  // ---------------------------------------------------------------- eyewear
  static const List<EvidenceBlueprint> _eyewear = [
    EvidenceBlueprint(
      id: 'front_frame',
      title: 'Front',
      guide: 'Take a photo of the glasses from the front, lying flat.',
      why: "We'll check the frame shape and lens outline.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'temple_outside',
      title: 'Side / Arm',
      guide: 'Photograph one arm from the outside, logo side up.',
      why: "We'll check the logo and arm shape.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'inside_temple_markings',
      title: 'Inside Arms',
      guide: 'Photograph the inside of both arms so the printed codes are readable.',
      why: "We'll read the model, size and 'Made in' markings.",
      weight: EvidenceWeight.critical,
      identityMarking: true,
    ),
    EvidenceBlueprint(
      id: 'hinge',
      title: 'Hinge',
      guide: 'Take a close-up of where an arm joins the front.',
      why: "We'll check the hinge and screws.",
      weight: EvidenceWeight.high,
    ),
    EvidenceBlueprint(
      id: 'bridge_nose_pads',
      title: 'Nose Area',
      guide: 'Take a close-up of the bridge and nose pads.',
      why: "We'll check how the middle is built.",
      weight: EvidenceWeight.medium,
    ),
    EvidenceBlueprint(
      id: 'lens_logo',
      title: 'Lens Logo',
      guide: 'Tilt one lens toward the light and photograph any small logo on it.',
      why: "We'll check the etched or printed lens mark.",
      weight: EvidenceWeight.critical,
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
      identityMarking: true,
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
      check: 'Analog watches: crown knurling, pusher machining and lug finishing.',
      genuineSignal: 'Machined teeth with clean edges; lugs flow smoothly into the case.',
      replicaSignal: 'Casting burrs, soft knurling, abrupt lug transitions.',
      simpleTip: 'Look at the small knob on the side. Its grooves should be sharp, not rounded.',
    ),
    InspectionRule(
      dimension: InspectionDimension.typography,
      check: 'Analog watches: dial text print quality, marker alignment and lume application.',
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

  static const List<InspectionRule> _smartwatchRules = [
    InspectionRule(
      dimension: InspectionDimension.shape,
      check: 'Case geometry: corner radius, case thickness, curvature of the glass into the case, symmetry.',
      genuineSignal: 'Case proportions and corner radius match the identified generation and size.',
      replicaSignal: 'Visibly thicker case, flat glass with a hard edge, or proportions from a different model.',
      simpleTip: 'Look at the watch from the side. The glass should curve smoothly into the case.',
    ),
    InspectionRule(
      dimension: InspectionDimension.display,
      check: 'Display: bezel width around the active area, screen shape, how the interface fills the screen.',
      genuineSignal: 'Thin, even black border; interface fills the curved screen as expected for the generation.',
      replicaSignal: 'Thick uneven bezel, rectangular non-curved screen, or an interface that is not watchOS.',
      simpleTip: 'Turn the screen on. The black border around it should be thin and even.',
    ),
    InspectionRule(
      dimension: InspectionDimension.hardware,
      check: 'Digital Crown and side button: position, proportions, crown ridges, red ring on Series models with ECG where applicable.',
      genuineSignal: 'Crown and button placed and sized as expected for the generation; clean fine ridges on the crown.',
      replicaSignal: 'Crown or button in the wrong place, oversized, loose-looking, or with coarse moulded ridges.',
      simpleTip: 'Look at the knob on the side. It should look precise, with fine even ridges.',
    ),
    InspectionRule(
      dimension: InspectionDimension.display,
      check: 'Back sensor: lens arrangement, sensor window shape, text printed around the sensor.',
      genuineSignal: 'Sensor layout matches the identified generation; any printed text is crisp and even.',
      replicaSignal: 'Sensor layout from no real generation, cheap-looking plastic back, blurry or misspelled text.',
      simpleTip: 'Turn it over. The sensor should look precise and any text should be sharp.',
    ),
    InspectionRule(
      dimension: InspectionDimension.hardware,
      check: 'Band connector slot, band release buttons, speaker and microphone openings.',
      genuineSignal: 'Clean slot edges, release buttons flush, openings neatly machined and placed as expected.',
      replicaSignal: 'Rough slot edges, missing release buttons, openings in the wrong place.',
      simpleTip: 'Check the slot where the band goes in. Its edges should be clean and even.',
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
      check: 'Inner size tag layout, font and production codes (SKU/style code).',
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
      replicaSignal: 'Coarse weave, blurred print, codes that conflict with the garment.',
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

  static const List<InspectionRule> _walletRules = [
    InspectionRule(
      dimension: InspectionDimension.stitching,
      check: 'Stitch pitch and edge paint along the outer edges and card slots.',
      genuineSignal: 'Even pitch, straight stitch lines, smooth sealed edge paint.',
      replicaSignal: 'Wandering stitch lines, frayed thread, lumpy or cracked edge paint.',
      simpleTip: 'Run a finger along the edge. It should be smooth and evenly sealed.',
    ),
    InspectionRule(
      dimension: InspectionDimension.labels,
      check: 'Heat stamp or embossed logo depth, font and alignment; interior code format.',
      genuineSignal: 'Crisp, evenly deep stamp with correct letterforms; code formatted as expected.',
      replicaSignal: 'Shallow or blurry stamp, wrong letter shapes, code in an impossible format.',
      simpleTip: 'Look at the stamped logo. It should be pressed evenly and read cleanly.',
    ),
    InspectionRule(
      dimension: InspectionDimension.hardware,
      check: 'Zipper pulls and snaps: engraving, weight, plating.',
      genuineSignal: 'Engraved brand marks, even plating, solid feel.',
      replicaSignal: 'Unmarked generic hardware where the model uses branded hardware, flaking plating.',
      simpleTip: 'Check the zipper pull or snap for a clean engraved brand mark.',
    ),
  ];

  static const List<InspectionRule> _eyewearRules = [
    InspectionRule(
      dimension: InspectionDimension.shape,
      check: 'Frame geometry and symmetry: lens shape, bridge width, brow line, temple angle.',
      genuineSignal: 'Symmetric frame whose shape matches the identified model family.',
      replicaSignal: 'Visibly asymmetric frame, or a shape that belongs to no model in the family.',
      simpleTip: 'Lay them flat. Both sides should be a perfect mirror of each other.',
    ),
    InspectionRule(
      dimension: InspectionDimension.serial,
      check: 'Inside-temple markings: model code, colour code, lens-bridge-temple size, "Made in", CE mark.',
      genuineSignal: 'Crisp, evenly printed markings in the brand\'s usual layout, consistent with the model.',
      replicaSignal: 'Smudged or uneven print, misspellings, a model code that conflicts with the frame shape.',
      simpleTip: 'Read the tiny text inside the arms. It should be sharp and evenly spaced.',
    ),
    InspectionRule(
      dimension: InspectionDimension.hardware,
      check: 'Hinges, screws and temple cores: hinge type (barrel, spring, riveted), screw finish, visible metal core.',
      genuineSignal: 'Solid multi-barrel or brand-specific hinge, clean screws, rivets where the model has them.',
      replicaSignal: 'Flimsy single-barrel hinge on a model known for a heavier one, glued rather than riveted parts.',
      simpleTip: 'Open and close the arms. The hinge should feel solid and move smoothly.',
    ),
    InspectionRule(
      dimension: InspectionDimension.lens,
      check: 'Lens logo (etched or printed), lens edge finishing and fit in the frame.',
      genuineSignal: 'Fine, even lens mark in the correct lens and position; lenses seated tightly.',
      replicaSignal: 'Thick sticker-like lens logo, mark in the wrong lens, gaps between lens and frame.',
      simpleTip: 'Tilt a lens in the light. Any small logo on it should be fine and clean.',
    ),
    InspectionRule(
      dimension: InspectionDimension.logo,
      check: 'Temple logo: plaque, print or inlay; spacing and alignment.',
      genuineSignal: 'Logo cleanly applied, level, correctly spaced for the model.',
      replicaSignal: 'Crooked or bubbled logo, wrong font, logo placed on the wrong part of the arm.',
      simpleTip: 'Look at the logo on the arm. It should be straight and neatly applied.',
    ),
  ];

  // --------------------------------------------------------------- cautions
  /// Applies to every category.
  static const List<String> _sharedCautions = [
    'A detail that is not visible is MISSING evidence, never counterfeit evidence.',
    'Lighting, glare, reflections, shadows, blur, compression artifacts, camera angle and lens distortion change how details look. Do not treat those effects as counterfeit indicators.',
    'Normal wear, scratches, dirt and fading are not counterfeit indicators.',
    'Colour differences between photos are usually white-balance, not materials.',
  ];

  static const List<String> _watchCautions = [
    'Dial glare and crystal reflections often hide or distort printing: report as AMBIGUOUS.',
    'Only apply analog-dial rules (lume, pad printing, crown knurling) to analog watches.',
  ];

  static const List<String> _smartwatchCautions = [
    'This is a smartwatch: do NOT apply mechanical-watch rules (lume, pad-printed dial text, crown knurling, rehaut, movement).',
    'Serial numbers cannot be validated against Apple from a photo. Report a visible serial only as observed text.',
    'A dark screen, screen protector or case cover hides details: report as MISSING or AMBIGUOUS.',
    'Generations differ (sensor layout, button shape, case size). Compare only against the generation you identified; if the generation is uncertain, do not count generation-specific differences as counterfeit evidence.',
  ];

  static const List<String> _bagCautions = [
    'Pattern alignment is only evidence when this specific model is known to be aligned at that seam. Do not apply generic "luxury bags are always aligned" rules.',
    'Date codes and heat stamps vary by year and factory; only a format that is impossible for the brand is counterfeit evidence.',
  ];

  static const List<String> _sneakerCautions = [
    'Slight colour differences, creasing, worn soles and dirt are not counterfeit indicators.',
    'Stitch counts and shapes vary between factories and production years of genuine pairs.',
  ];

  static const List<String> _clothingCautions = [
    'A missing or cut-out tag is MISSING evidence, not counterfeit evidence.',
    'Fabric texture and colour change dramatically with lighting and wrinkles.',
  ];

  static const List<String> _eyewearCautions = [
    'Lens tint, mirror coatings and reflections change dramatically with lighting and angle. Never treat reflection or tint differences as counterfeit indicators.',
    'If inside-temple markings are not readable, request another photo rather than judging the glasses.',
    'Prescription lenses fitted by an optician replace the original lenses, so a missing lens logo on eyeglasses is not counterfeit evidence.',
  ];

  static const List<String> _walletCautions = [
    'Many genuine small leather goods have no serial or date code; its absence is not counterfeit evidence.',
  ];

  static AuthenticationRuleSet forCategory(ProductCategory category) {
    switch (category) {
      case ProductCategory.watches:
        return const AuthenticationRuleSet(
          category: ProductCategory.watches,
          evidenceBlueprint: _watch,
          inspectionRules: [..._sharedRules, ..._watchRules],
          cautions: [..._sharedCautions, ..._watchCautions],
          profileName: 'WATCH',
        );
      case ProductCategory.bags:
        return const AuthenticationRuleSet(
          category: ProductCategory.bags,
          evidenceBlueprint: _bag,
          inspectionRules: [..._sharedRules, ..._bagRules],
          cautions: [..._sharedCautions, ..._bagCautions],
          profileName: 'HANDBAG',
        );
      case ProductCategory.sneakers:
        return const AuthenticationRuleSet(
          category: ProductCategory.sneakers,
          evidenceBlueprint: _sneaker,
          inspectionRules: [..._sharedRules, ..._sneakerRules],
          cautions: [..._sharedCautions, ..._sneakerCautions],
          profileName: 'SNEAKER/SHOE',
        );
      case ProductCategory.clothing:
        return const AuthenticationRuleSet(
          category: ProductCategory.clothing,
          evidenceBlueprint: _clothing,
          inspectionRules: [..._sharedRules, ..._clothingRules],
          cautions: [..._sharedCautions, ..._clothingCautions],
          profileName: 'CLOTHING',
        );
      case ProductCategory.wallets:
        return const AuthenticationRuleSet(
          category: ProductCategory.wallets,
          evidenceBlueprint: _wallet,
          inspectionRules: [..._sharedRules, ..._walletRules],
          cautions: [..._sharedCautions, ..._walletCautions],
          profileName: 'WALLET',
        );
      case ProductCategory.eyewear:
        return const AuthenticationRuleSet(
          category: ProductCategory.eyewear,
          evidenceBlueprint: _eyewear,
          inspectionRules: [..._sharedRules, ..._eyewearRules],
          cautions: [..._sharedCautions, ..._eyewearCautions],
          profileName: 'EYEWEAR',
        );
      case ProductCategory.accessories:
        return const AuthenticationRuleSet(
          category: ProductCategory.accessories,
          evidenceBlueprint: _accessory,
          inspectionRules: [..._sharedRules],
          cautions: _sharedCautions,
          profileName: 'ACCESSORY',
        );
    }
  }

  /// Model-specific overlays. Add entries to sharpen a given model without
  /// touching any UI code. [AuthenticationRuleSet.model] is matched against
  /// the product's name and model together.
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
    const AuthenticationRuleSet(
      category: ProductCategory.watches,
      brand: 'Apple',
      model: 'Watch',
      evidenceBlueprint: _smartwatch,
      inspectionRules: [..._sharedRules, ..._smartwatchRules],
      cautions: [..._sharedCautions, ..._smartwatchCautions],
      replacesBaseRules: true,
      profileName: 'SMARTWATCH (Apple Watch)',
    ),
  ];

  static AuthenticationRuleSet resolve({
    required ProductCategory category,
    String? brand,
    String? model,
    String? name,
  }) {
    var base = forCategory(category);
    final b = (brand ?? '').toLowerCase().trim();
    final m = '${name ?? ''} ${model ?? ''}'.toLowerCase().trim();

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
    const critical = ['serial', 'reference', 'date_code', 'datecode', 'dial', 'size_tag', 'neck_tag', 'heat_stamp', 'production', 'number', 'engrav', 'temple_marking', 'markings'];
    const high = ['logo', 'monogram', 'marking', 'hallmark', 'caseback', 'interior', 'inside', 'sole', 'bottom', 'crown', 'graphic', 'back', 'hinge', 'sensor', 'display'];
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
