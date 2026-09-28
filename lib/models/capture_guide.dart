/// Shape of the on-camera framing overlay for a requested photo.
///
/// Overlays are framing aids only. No computer-vision alignment check runs
/// against them, and capture is always allowed.
enum CaptureGuideType {
  /// Whole object, large frame.
  fullItem,

  /// Round watch face or dial.
  watchFaceRound,

  /// Rounded-rectangle smartwatch face (Apple Watch style).
  watchFaceSquare,

  /// Back of a watch with a central sensor or caseback ring.
  watchBack,

  /// Side profile of a watch case with the crown.
  watchSide,

  /// Shoe seen from the side.
  shoeSide,

  /// Outsole, full length.
  shoeSole,

  /// Heel seen from behind.
  shoeHeel,

  /// Small label, tag or printed text.
  label,

  /// Macro square for stitching, engraving or a hallmark.
  macro,

  /// Whole handbag.
  bagFull,

  /// Inside a bag (tall frame).
  bagInterior,

  /// Small hardware: zip pull, clasp, buckle.
  hardware,

  /// Glasses seen from the front, lying flat.
  glassesFront,

  /// Long thin frame for a temple arm.
  templeArm,

  /// Hinge or small joint.
  hinge,

  /// A device screen or a screenshot.
  screen,

  /// Bottle (fragrance, cosmetics).
  bottle,

  /// Anything else.
  generic;

  static CaptureGuideType parse(String? raw) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return CaptureGuideType.generic;
  }
}

/// Distance, focus and lighting advice for one requested photo.
class CaptureTips {
  final String distance;
  final String focus;
  final String lighting;

  const CaptureTips({
    required this.distance,
    required this.focus,
    required this.lighting,
  });

  static const standard = CaptureTips(
    distance: 'Fill most of the guide with the part.',
    focus: 'Tap the screen on the part to focus, then hold still.',
    lighting: 'Use soft, even light. Avoid direct sun and flash glare.',
  );

  static const closeUp = CaptureTips(
    distance: 'Move close until the detail fills the guide. Use zoom if the camera cannot focus that near.',
    focus: 'Tap on the detail to focus and wait a moment before taking the photo.',
    lighting: 'Light from the side shows engravings and stitching best. Tilt to remove glare.',
  );

  static const text = CaptureTips(
    distance: 'Move close enough that every letter is readable on your screen.',
    focus: 'Tap on the text to focus. Hold the phone parallel to the label.',
    lighting: 'Even light without reflections on the text.',
  );

  static const screenInfo = CaptureTips(
    distance: 'A screenshot is best. Otherwise fill the frame with the screen.',
    focus: 'Make sure every line of text is sharp and readable.',
    lighting: 'Turn screen brightness up and avoid reflections on the glass.',
  );

  static const fullView = CaptureTips(
    distance: 'Step back so the whole item fits inside the guide.',
    focus: 'Tap the item to focus.',
    lighting: 'Plain background and even light, without strong shadows.',
  );

  List<String> get asList => [distance, focus, lighting];

  Map<String, dynamic> toJson() => {'distance': distance, 'focus': focus, 'lighting': lighting};

  factory CaptureTips.fromJson(Map<String, dynamic>? json) {
    if (json == null) return CaptureTips.standard;
    return CaptureTips(
      distance: json['distance'] as String? ?? CaptureTips.standard.distance,
      focus: json['focus'] as String? ?? CaptureTips.standard.focus,
      lighting: json['lighting'] as String? ?? CaptureTips.standard.lighting,
    );
  }
}
