import '../../models/capture_guide.dart';

/// The short caption (at most five words) shown on the framing guide. Purely
/// presentational wording about what to frame, keyed by guide shape; it
/// states no product facts. The part's full advice stays in `CaptureTips`.
String captureGuideCaption(CaptureGuideType type) => switch (type) {
  CaptureGuideType.fullItem => 'Fit the whole item',
  CaptureGuideType.watchFaceRound => 'Fill the circle',
  CaptureGuideType.watchFaceSquare => 'Fill the frame',
  CaptureGuideType.watchBack => 'Fill the circle',
  CaptureGuideType.watchSide => 'Show the side',
  CaptureGuideType.shoeSide => 'Whole shoe in frame',
  CaptureGuideType.shoeSole => 'Whole sole in frame',
  CaptureGuideType.shoeHeel => 'Fit the heel',
  CaptureGuideType.label => 'Fit the label',
  CaptureGuideType.macro => 'Fill the square',
  CaptureGuideType.bagFull => 'Whole bag in frame',
  CaptureGuideType.bagInterior => 'Show the inside',
  CaptureGuideType.hardware => 'Fit the hardware',
  CaptureGuideType.glassesFront => 'Both lenses in frame',
  CaptureGuideType.templeArm => 'Fit the arm',
  CaptureGuideType.hinge => 'Fit the hinge',
  CaptureGuideType.screen => 'Fill with the screen',
  CaptureGuideType.bottle => 'Whole bottle in frame',
  CaptureGuideType.generic => 'Fit the part',
};
