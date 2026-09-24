import 'photo_quality.dart';

/// Outcome of validating one submitted photo against the evidence item the app
/// actually asked for.
enum EvidenceVerdict {
  /// The image shows the requested area at usable quality.
  accepted,

  /// The image shows something else. Never admissible as this evidence item.
  rejectedWrongEvidence,

  /// Right area, but the image cannot be inspected reliably. The user may
  /// override, in which case the evidence is retained but flagged low quality.
  rejectedQuality,
}

/// A single image's validation record.
///
/// Photo quality and authentication usefulness are deliberately independent:
/// a flawless photo of the wrong part is 0% useful, and a mediocre photo of the
/// right part can still carry decisive evidence.
class EvidenceValidationResult {
  final String requestedEvidenceId;
  final String requestedEvidenceTitle;

  /// What the model actually saw, in its own words ("crown", "caseback", ...).
  final String evidenceTypeDetected;

  /// Whether [evidenceTypeDetected] satisfies the requested evidence item.
  final bool matchToRequestedEvidence;

  /// 0-100 confidence that the requested area is present and legible.
  final int matchConfidence;

  final PhotoQualityResult quality;

  /// 0-100 — is the image technically workable (not truncated, not unrelated)?
  final int usabilityScore;

  /// 0-100 — how much this image contributes to authenticating THIS item.
  /// Forced to 0 whenever [matchToRequestedEvidence] is false.
  final int authenticationUsefulness;

  final String reason;
  final List<String> issues;

  const EvidenceValidationResult({
    required this.requestedEvidenceId,
    required this.requestedEvidenceTitle,
    required this.evidenceTypeDetected,
    required this.matchToRequestedEvidence,
    required this.matchConfidence,
    required this.quality,
    required this.usabilityScore,
    required this.authenticationUsefulness,
    required this.reason,
    this.issues = const [],
  });

  EvidenceVerdict get verdict {
    if (!matchToRequestedEvidence || matchConfidence < 50) {
      return EvidenceVerdict.rejectedWrongEvidence;
    }
    if (quality.qualityStatus == PhotoQualityStatus.poor || usabilityScore < 40) {
      return EvidenceVerdict.rejectedQuality;
    }
    return EvidenceVerdict.accepted;
  }

  bool get isAccepted => verdict == EvidenceVerdict.accepted;

  /// Wrong-subject rejections can never be overridden into evidence (§6, §28).
  /// Quality rejections can, with the evidence flagged low quality (§50).
  bool get isOverridable => verdict == EvidenceVerdict.rejectedQuality;

  /// Short, human headline. Never technical (§21, §22).
  String get headline {
    switch (verdict) {
      case EvidenceVerdict.rejectedWrongEvidence:
        return "That's a different part";
      case EvidenceVerdict.rejectedQuality:
        if (quality.isBlurry) return 'Too blurry';
        if (quality.isTooDark) return 'Too dark';
        return 'Hard to see';
      case EvidenceVerdict.accepted:
        if (quality.qualityStatus == PhotoQualityStatus.excellent) return 'Great photo';
        return 'Good photo';
    }
  }

  String get guidance {
    final want = requestedEvidenceTitle.toLowerCase();
    switch (verdict) {
      case EvidenceVerdict.rejectedWrongEvidence:
        final seen = evidenceTypeDetected.trim().toLowerCase();
        if (seen.isEmpty || seen == 'unknown') {
          return "This doesn't look like the $want.";
        }
        return 'This photo shows the $seen, but we need the $want.';
      case EvidenceVerdict.rejectedQuality:
        if (quality.isBlurry) return "It's too blurry to check properly.";
        if (quality.isTooDark) return "It's too dark to check properly.";
        if (quality.framing > 0 && quality.framing < 45) {
          return "We can't see enough of the $want in this photo.";
        }
        return "We can't see the $want clearly enough to check it.";
      case EvidenceVerdict.accepted:
        return reason;
    }
  }

  String get callToAction {
    final want = requestedEvidenceTitle.toLowerCase();
    if (verdict == EvidenceVerdict.rejectedWrongEvidence) {
      return 'We need a clear photo of the $want.';
    }
    if (quality.isBlurry) return 'Hold steady and try again.';
    if (quality.isTooDark) return 'Move somewhere brighter and try again.';
    return 'Move a little closer and try again.';
  }

  /// Plain-English summary of how useful this photo is (§23).
  String get usefulnessLabel {
    if (!matchToRequestedEvidence) return 'Not useful here';
    if (authenticationUsefulness >= 85) return 'Very useful';
    if (authenticationUsefulness >= 60) return 'Useful';
    if (authenticationUsefulness >= 35) return 'Limited';
    return 'Not much to go on';
  }

  /// One short line the user can act on (§23).
  String get usefulnessExplanation {
    if (!matchToRequestedEvidence) {
      return "Good photo, but it doesn't show what we asked for.";
    }
    if (authenticationUsefulness >= 75 && quality.qualityScore >= 75) {
      return 'Clear photo with useful detail.';
    }
    if (authenticationUsefulness >= 75) {
      return 'Useful detail, even though the photo could be sharper.';
    }
    if (quality.qualityScore >= 75) {
      return "Good photo, but this view doesn't show enough of the detail we need.";
    }
    return 'We can only check a little from this photo.';
  }

  factory EvidenceValidationResult.fromJson(
    Map<String, dynamic> json, {
    required String requestedEvidenceId,
    required String requestedEvidenceTitle,
  }) {
    int score(dynamic raw, {int fallback = 0}) {
      if (raw is num) {
        var v = raw.toDouble();
        if (v > 0 && v <= 1.0) v = v * 100;
        return v.round().clamp(0, 100);
      }
      if (raw is String) {
        final p = double.tryParse(raw);
        if (p != null) return score(p, fallback: fallback);
      }
      return fallback;
    }

    final detected =
        (json['evidence_type_detected'] as String? ?? json['detected'] as String? ?? 'unknown').trim();

    final matchRaw = json['match_to_requested_evidence'] ?? json['matches_requested'];
    final matchConfidence = score(json['match_confidence'] ?? json['evidence_match'], fallback: -1);

    bool match;
    if (matchRaw is bool) {
      match = matchRaw;
    } else if (matchRaw is String) {
      match = matchRaw.toLowerCase() == 'true' || matchRaw.toLowerCase() == 'yes';
    } else {
      match = matchConfidence >= 50;
    }

    // The model's "match_confidence" is its confidence in whatever area it
    // detected, not necessarily in whether that area is the one requested —
    // it can come back high even when match_to_requested_evidence is false
    // (wrong part, but clearly photographed). Displayed as "Right Part %" to
    // the user, so it must never read as a strong match when the part is
    // already known to be wrong - force it down here rather than trusting
    // the model to keep the two fields consistent.
    final resolvedMatchConfidence =
        !match ? 0 : (matchConfidence >= 0 ? matchConfidence : 80);

    final quality = PhotoQualityResult.fromJson(json);
    final usability = score(json['usability_score'] ?? json['usability'], fallback: quality.qualityScore);

    // Usefulness is clamped to zero for the requested check whenever the photo
    // shows something else — a perfect photo of the wrong part proves nothing.
    var usefulness = score(
      json['authentication_usefulness'] ?? json['usefulness'],
      fallback: -1,
    );
    if (!match) {
      usefulness = 0;
    } else if (usefulness < 0) {
      usefulness = ((resolvedMatchConfidence * 0.6) + (quality.qualityScore * 0.4)).round().clamp(0, 100);
    }

    final issues = <String>[];
    if (json['issues'] is List) {
      for (final i in json['issues'] as List) {
        if (i != null && i.toString().trim().isNotEmpty) issues.add(i.toString().trim());
      }
    }

    return EvidenceValidationResult(
      requestedEvidenceId: requestedEvidenceId,
      requestedEvidenceTitle: requestedEvidenceTitle,
      evidenceTypeDetected: detected,
      matchToRequestedEvidence: match,
      matchConfidence: resolvedMatchConfidence,
      quality: quality,
      usabilityScore: usability,
      authenticationUsefulness: usefulness,
      reason: (json['reason'] as String? ?? json['explanation'] as String? ?? '').trim(),
      issues: issues,
    );
  }

  Map<String, dynamic> toJson() => {
        'requested_evidence_id': requestedEvidenceId,
        'requested_evidence_title': requestedEvidenceTitle,
        'evidence_type_detected': evidenceTypeDetected,
        'match_to_requested_evidence': matchToRequestedEvidence,
        'match_confidence': matchConfidence,
        'usability_score': usabilityScore,
        'authentication_usefulness': authenticationUsefulness,
        'reason': reason,
        'issues': issues,
        ...quality.toJson(),
      };

  factory EvidenceValidationResult.fromStoredJson(Map<String, dynamic> json) {
    return EvidenceValidationResult(
      requestedEvidenceId: json['requested_evidence_id'] as String? ?? '',
      requestedEvidenceTitle: json['requested_evidence_title'] as String? ?? '',
      evidenceTypeDetected: json['evidence_type_detected'] as String? ?? '',
      matchToRequestedEvidence: json['match_to_requested_evidence'] as bool? ?? false,
      matchConfidence: (json['match_confidence'] as num?)?.toInt() ?? 0,
      quality: PhotoQualityResult.fromStoredJson(json),
      usabilityScore: (json['usability_score'] as num?)?.toInt() ?? 0,
      authenticationUsefulness: (json['authentication_usefulness'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String? ?? '',
      issues: (json['issues'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}
