import '../core/config/authenticity_engine_config.dart';
import '../models/authentication_result.dart';
import '../models/product.dart';

/// Keeps repeat scans of the same product stable (§17-19).
///
/// Previous results are *context*, not truth:
/// - A new scan may only flip a stable earlier verdict when it brings new
///   strong evidence. Otherwise the new scan is shown as "Unable to Verify"
///   and the earlier result stands as the session assessment.
/// - Strong counterfeit evidence can always override an earlier authentic
///   result, and repeated strong evidence overrides it immediately.
abstract final class ScanConsistencyService {
  /// Words that identify nothing about a specific product.
  static const _genericWords = {
    'the', 'a', 'an', 'and', 'with', 'standard', 'unknown', 'model', 'edition', 'luxury', 'item',
    'watch', 'watches', 'bag', 'bags', 'shoe', 'shoes', 'sneaker', 'sneakers', 'sunglasses',
    'glasses', 'eyeglasses', 'wallet', 'men', 'mens', 'women', 'womens', 'unisex',
  };

  /// Semantic, product-level fingerprint:
  /// `CATEGORY|brand|model-family#marking1,marking2`.
  ///
  /// Built from what the product *is* (category, brand, model family) and
  /// any markings read off it, never from pixels, so different angles and
  /// lighting of the same item produce the same key.
  static String fingerprint(Product product, {String? analysedModel, List<String> observedText = const []}) {
    final category = product.categoryCode ?? product.category.name.toUpperCase();
    final brand = _norm(product.brand);
    final familySource = (analysedModel != null && analysedModel.trim().isNotEmpty)
        ? analysedModel
        : '${product.name} ${product.model}';
    final brandTokens = brand.split(' ').toSet();
    final family = _norm(familySource)
        .split(' ')
        .where((t) => t.isNotEmpty && !_genericWords.contains(t) && !brandTokens.contains(t))
        .take(3)
        .join('-');
    final markings = markingTokens(observedText).toList()..sort();
    return '$category|$brand|$family#${markings.join(',')}';
  }

  /// Tokens from observed text that are distinctive enough to tell two
  /// physical items apart (serial-like: 4+ characters containing a digit).
  static Set<String> markingTokens(List<String> observedText) => {
        for (final t in observedText)
          for (final tok in t.toUpperCase().split(RegExp(r'[^A-Z0-9]+')))
            if (tok.length >= 4 && RegExp(r'\d').hasMatch(tok)) tok,
      };

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static String _productKey(String fp) => fp.split('#').first;

  static Set<String> _markings(String fp) {
    final parts = fp.split('#');
    if (parts.length < 2 || parts[1].isEmpty) return {};
    return parts[1].split(',').toSet();
  }

  /// Same product model, and not provably a different physical item.
  /// If both scans read serial-like markings and none of them match, they
  /// are different items even if they are the same model.
  static bool isSameProduct(String a, String b) {
    if (_productKey(a) != _productKey(b)) return false;
    final ma = _markings(a), mb = _markings(b);
    if (ma.isNotEmpty && mb.isNotEmpty && ma.intersection(mb).isEmpty) return false;
    return true;
  }

  /// Reconciles [report] (already scored on its own evidence) with earlier
  /// scans of the same product in [history].
  static AuthenticationReport reconcile({
    required AuthenticationReport report,
    required List<AuthenticationReport> history,
    DateTime? now,
  }) {
    final fp = report.fingerprint;
    final raw = ConsistencyInfo(rawVerdict: report.verdict, rawConfidence: report.authenticationConfidence);
    if (fp == null) return report.copyWith(consistency: raw);

    final clock = now ?? DateTime.now();
    final matches = history
        .where((r) =>
            r.id != report.id &&
            r.fingerprint != null &&
            // Results from engine v1 came from the logic being replaced and
            // must not anchor new results.
            _isV2(r) &&
            clock.difference(r.timestamp) <= AuthenticityEngineConfig.consistencyWindow &&
            isSameProduct(fp, r.fingerprint!))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (matches.isEmpty) return report.copyWith(consistency: raw);

    // The most recent confident, decisive result that was actually shown.
    AuthenticationReport? stable;
    for (final r in matches) {
      if (r.verdict != Verdict.inconclusive &&
          r.authenticationConfidence >= AuthenticityEngineConfig.minConfidenceToProtect) {
        stable = r;
        break;
      }
    }

    var verdict = report.verdict;
    var confidence = report.authenticationConfidence;
    var flipPrevented = false;
    var note = '';

    if (stable != null && verdict != Verdict.inconclusive && verdict != stable.verdict) {
      final allowed = switch (verdict) {
        Verdict.likelyReplica => _replicaOverrideAllowed(report, matches),
        Verdict.likelyAuthentic => _authenticOverrideAllowed(report, stable),
        Verdict.inconclusive => true,
      };
      if (allowed) {
        note = stable.verdict == Verdict.likelyAuthentic
            ? 'An earlier scan of this item appeared authentic. This scan found new strong evidence that changes that result.'
            : 'An earlier scan of this item looked like a replica. This scan clearly shows the details that were flagged, and they look right.';
      } else {
        flipPrevented = true;
        verdict = Verdict.inconclusive;
        confidence = confidence.clamp(20, 60);
        note = stable.verdict == Verdict.likelyAuthentic
            ? 'An earlier scan of this item appeared authentic. This scan did not find strong enough new evidence to change that, so it is shown as unable to verify.'
            : 'An earlier scan of this item found strong replica evidence. This scan did not clearly show the flagged details again, so it is shown as unable to verify.';
      }
    } else if (stable != null && verdict == Verdict.inconclusive) {
      note = 'This scan alone was not conclusive. An earlier scan of this item ${stable.verdict == Verdict.likelyAuthentic ? 'appeared authentic' : 'looked like a replica'}.';
    }

    final session = _sessionVerdict(
      current: verdict,
      currentRaw: report.verdict,
      currentStrong: _strongCount(report),
      matches: matches,
    );

    final info = ConsistencyInfo(
      rawVerdict: report.verdict,
      rawConfidence: report.authenticationConfidence,
      previousReportId: matches.first.id,
      previousVerdict: matches.first.verdict,
      previousConfidence: matches.first.authenticationConfidence,
      flipPrevented: flipPrevented,
      sessionVerdict: session,
      sessionScanCount: matches.length + 1,
      note: note,
    );

    return report.copyWith(
      verdict: verdict,
      overallScore: confidence,
      authenticationConfidence: confidence,
      consistency: info,
      rationale: note.isEmpty ? report.rationale : '${report.rationale} $note',
      quickSummaryPoints: note.isEmpty ? report.quickSummaryPoints : [note, ...report.quickSummaryPoints],
      analysisLog: {...report.analysisLog, 'consistency': info.toJson()},
    );
  }

  static bool _isV2(AuthenticationReport r) {
    final major = int.tryParse(r.engineVersion.split('.').first) ?? 1;
    return major >= 2;
  }

  static int _strongCount(AuthenticationReport r) =>
      (r.analysisLog['strongCounterfeitCount'] as num?)?.toInt() ?? 0;

  static Set<String> _ids(AuthenticationReport r, String key) =>
      ((r.analysisLog[key] as List?) ?? const []).map((e) => e.toString().toLowerCase()).toSet();

  /// Authentic -> replica needs new strong evidence: either two or more
  /// strong, verified counterfeit findings in this scan, or strong evidence
  /// repeated across consecutive scans.
  static bool _replicaOverrideAllowed(AuthenticationReport report, List<AuthenticationReport> matches) {
    if (_strongCount(report) >= 2) return true;
    final previous = matches.first;
    final previousRaw = previous.consistency?.rawVerdict ?? previous.verdict;
    return previousRaw == Verdict.likelyReplica && _strongCount(previous) >= 1;
  }

  /// Replica -> authentic needs this scan to clearly show the details that
  /// were flagged before, and find them consistent.
  static bool _authenticOverrideAllowed(AuthenticationReport report, AuthenticationReport stable) {
    final flagged = _ids(stable, 'flaggedEvidenceIds');
    if (flagged.isEmpty) return false;
    final nowAuthentic = _ids(report, 'authenticEvidenceIds');
    return flagged.every(nowAuthentic.contains);
  }

  /// Session-level assessment (§18). Repeated strong replica evidence wins;
  /// otherwise the most recent decisive result that was shown stands, and
  /// inconclusive scans don't erase it.
  static Verdict _sessionVerdict({
    required Verdict current,
    required Verdict currentRaw,
    required int currentStrong,
    required List<AuthenticationReport> matches,
  }) {
    var strongReplicaScans = currentRaw == Verdict.likelyReplica && currentStrong >= 1 ? 1 : 0;
    for (final r in matches) {
      final rawV = r.consistency?.rawVerdict ?? r.verdict;
      if (rawV == Verdict.likelyReplica && _strongCount(r) >= 1) strongReplicaScans++;
    }
    if (strongReplicaScans >= 2) return Verdict.likelyReplica;
    if (current != Verdict.inconclusive) return current;
    for (final r in matches) {
      if (r.verdict != Verdict.inconclusive) return r.verdict;
    }
    return Verdict.inconclusive;
  }
}
