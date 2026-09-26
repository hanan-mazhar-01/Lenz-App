/// Versioning and decision thresholds for the authenticity engine.
///
/// Every report records [engineVersion] and [promptVersion] so results from
/// different engine generations can be compared and evaluated separately.
/// Thresholds live here, not inline in the scoring code, so they can be tuned
/// against an evaluation dataset without touching the decision logic.
abstract final class AuthenticityEngineConfig {
  /// Bump when the decision logic changes.
  static const String engineVersion = '2.0';

  /// Bump whenever any prompt or response schema text changes.
  static const String promptVersion = '2.0';

  // ------------------------------------------------------------ strengths
  /// Points contributed by one finding of each strength. A weak finding is
  /// worth a quarter of a strong one, so a single weak discrepancy can never
  /// behave like real counterfeit evidence.
  static const double weakPoints = 1.0;
  static const double moderatePoints = 2.0;
  static const double strongPoints = 4.0;

  // ------------------------------------------------------ LIKELY_REPLICA
  /// Replica needs multiple *independent* counterfeit indicators: they must
  /// come from at least this many different photos/areas...
  static const int minIndependentCounterfeitAreas = 2;

  /// ...and add up to at least this many points (weak findings excluded).
  static const double minCounterfeitPoints = 6.0;

  /// ...and at least one of them must be STRONG and specific to the model.
  static const int minStrongCounterfeitFindings = 1;

  /// Below this identification confidence, model-specific comparisons are
  /// not trusted enough to call something a replica.
  static const int minIdentificationForReplica = 60;

  // ---------------------------------------------------- LIKELY_AUTHENTIC
  static const int minAuthenticIndicators = 4;
  static const int minIndependentAuthenticAreas = 3;
  static const double minAuthenticPoints = 8.0;
  static const int minIdentificationForAuthentic = 60;

  /// Share of critical angles that must have been photographed.
  static const double minCriticalCoverageForAuthentic = 0.5;

  // ------------------------------------------------------ image quality
  /// Below this, the engine does not attempt a classification at all.
  static const int imageQualityGate = 40;

  /// Below this, a photo's counterfeit findings are downgraded one strength
  /// level: blur, glare and compression mimic manufacturing defects.
  static const int lowQualityDowngradeThreshold = 60;

  static const int minImageQualityForAuthentic = 55;

  // --------------------------------------------------------- confidence
  /// Nothing reaches 100%: certainty isn't available from photographs.
  static const int confidenceCeiling = 94;

  /// Ceiling when an identity marking (serial, model code, date code, size
  /// tag) wasn't photographed: the result can't be as strong without it.
  static const int ceilingWithoutIdentityMarking = 86;

  // -------------------------------------------------------- consistency
  /// How far back earlier scans of the same product are considered.
  static const Duration consistencyWindow = Duration(days: 30);

  /// Confidence an earlier stable result must have to be protected from a
  /// flip that isn't backed by new strong evidence.
  static const int minConfidenceToProtect = 70;
}
