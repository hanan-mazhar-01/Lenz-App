/// Versioning and tunable settings for the authenticity engine.
///
/// Every report records [engineVersion] and [promptVersion] so results from
/// different engine generations can be compared and evaluated separately.
///
/// Engine v3 (2026-09-26) replaced the v2 point/threshold engine with
/// feature-keyed evidence assessment (see EvidenceDecisionEngine). v3 does
/// not produce numeric confidence scores: they were never calibrated against
/// independently verified data, so reports show a qualitative evidence
/// strength instead.
///
/// Engine v4 (2026-09-27): the final verdict comes from one combined
/// analysis of ALL photos together (plus in-memory detail crops), based on
/// Gemini's own knowledge of the identified product and the app checklist.
///
/// Engine v5 (2026-09-27): Gemini Chat-style authentication. Gemini independently
/// evaluates all supplied photographs together, visual evidence, reaches its own
/// direct verdict (Authentic, Replica, Not Sure) and generates detailed reasoning
/// plus concise quick summary points. Legacy arbitrary scoring overrides are removed,
/// retaining only lightweight technical validation.
abstract final class AuthenticityEngineConfig {
  /// Bump when the decision logic changes.
  static const String engineVersion = '5.0';

  /// Bump whenever any prompt or response schema text changes.
  static const String promptVersion = '5.0';

  /// Major version from which reports carry an [AuthenticationAssessment]
  /// and no numeric confidence.
  static const int structuredAssessmentMajor = 3;

  // ------------------------------------------------------------ capture
  /// Total photos per scan, including the first identification photo. The
  /// user may stop at any point from one photo upward.
  static const int maxPhotosPerScan = 6;

  /// How many times the planner may suggest retaking the same part before
  /// moving on to a different one.
  static const int maxRetakeSuggestionsPerPart = 1;

  // ------------------------------------------------------ image handling
  /// A detail smaller than this (short side, px, at full resolution)
  /// triggers a "move closer" hint.
  static const int detailMinSidePx = 384;

  /// Two photos whose 64-bit difference hashes are within this Hamming
  /// distance are treated as the same picture.
  static const int duplicateHashDistance = 6;

  /// The only model used, for every call (owner's decision, 2026-09-26).
  static const String defaultModel = 'gemini-3.1-flash-lite';

  // ------------------------------------------------------- final stage
  /// How the final verdict is made. [FinalStageMode.legacyTextOnly] (the
  /// engine v3 path) is kept only so the regression harness can compare the
  /// two on the same photos.
  static const FinalStageMode finalStageMode = FinalStageMode.combined;

  /// Thinking level for the combined analysis (verified accepted by
  /// gemini-3.1-flash-lite: minimal, low, medium, high). Other calls keep
  /// thinking off, as before.
  static const String finalThinkingLevel = 'low';
  static const int finalMaxOutputTokens = 8000;
  static const Duration finalTimeout = Duration(seconds: 110);

  /// Upper bound for the images of the combined call, in base64 characters.
  /// The callable request limit is 10 MB; the backend rejects more than 9.5M.
  static const int finalImageBudgetChars = 7500000;

  /// Close-ups cut in memory from the full-resolution photo around each
  /// detail the photo check located, sent next to the whole photo. Never
  /// saved on the device and never shown.
  static const bool finalDetailCrops = true;
  static const int maxDetailCrops = 4;
  static const int detailCropMaxSide = 1024;

  // --------------------------------------------------------------- cost
  /// USD per 1M tokens, standard paid tier, from
  /// https://ai.google.dev/gemini-api/docs/pricing (read 2026-09-26).
  /// Used only to turn measured token counts into an estimate. Re-check
  /// before relying on the figures.
  static const Map<String, ({double input, double output})> pricePerMillionTokens = {
    'gemini-3.1-flash-lite': (input: 0.25, output: 1.50),
  };

  /// Default Gemini 3 per-image token budget ("unspecified"/"high" media
  /// resolution), from https://ai.google.dev/gemini-api/docs/media-resolution.
  /// Used to estimate usage when the backend does not report token counts.
  static const int estimatedTokensPerImage = 1120;

  // -------------------------------------------------------- consistency
  /// How far back earlier scans of the same product are considered, when
  /// two scans are confirmed to be the SAME physical item (a serial/marking
  /// read off both agrees).
  static const Duration consistencyWindow = Duration(days: 30);

  /// How far back a match is considered when two scans agree on brand/model
  /// but neither has a readable serial/marking to confirm they're the same
  /// physical unit. Scoped to one sitting.
  static const Duration sameSessionWindow = Duration(hours: 3);

  /// Confidence an earlier stable v2 result must have to be protected from a
  /// flip that isn't backed by new strong evidence. v3 reports use their
  /// evidence strength instead.
  static const int minConfidenceToProtect = 70;
}

enum FinalStageMode { combined, legacyTextOnly }
