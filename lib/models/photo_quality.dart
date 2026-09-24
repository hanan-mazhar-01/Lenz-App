/// Photo quality tiers surfaced to the user after every capture.
/// These describe the IMAGE only — never the authenticity of the item.
enum PhotoQualityStatus {
  excellent('Excellent'),
  good('Good'),
  needsImprovement('Needs Improvement'),
  poor('Poor');

  final String label;
  const PhotoQualityStatus(this.label);

  static PhotoQualityStatus fromScore(int score) {
    if (score >= 85) return PhotoQualityStatus.excellent;
    if (score >= 70) return PhotoQualityStatus.good;
    if (score >= 45) return PhotoQualityStatus.needsImprovement;
    return PhotoQualityStatus.poor;
  }

  static PhotoQualityStatus parse(String? raw, int score) {
    final s = (raw ?? '').toUpperCase();
    if (s.contains('EXCELLENT')) return PhotoQualityStatus.excellent;
    if (s.contains('NEEDS') || s.contains('IMPROV') || s.contains('FAIR')) {
      return PhotoQualityStatus.needsImprovement;
    }
    if (s.contains('POOR') || s.contains('BAD') || s.contains('UNUSABLE')) {
      return PhotoQualityStatus.poor;
    }
    if (s.contains('GOOD')) return PhotoQualityStatus.good;
    return PhotoQualityStatus.fromScore(score);
  }
}

/// Per-image technical quality measurement. Produced by the vision model for
/// every submitted photo. Never fabricated — if evaluation fails the caller
/// surfaces an error instead of inventing a number.
class PhotoQualityResult {
  final int qualityScore; // 0-100 overall image quality
  final PhotoQualityStatus qualityStatus;
  final String explanation;

  // Sub-scores, all 0-100.
  final int sharpness;
  final int lighting;
  final int framing;
  final int detail;

  final List<String> improvementTips;

  const PhotoQualityResult({
    required this.qualityScore,
    required this.qualityStatus,
    required this.explanation,
    this.sharpness = 0,
    this.lighting = 0,
    this.framing = 0,
    this.detail = 0,
    this.improvementTips = const [],
  });

  /// Whether the image is technically good enough to reason about at all.
  bool get isUsable => qualityStatus != PhotoQualityStatus.poor;

  bool get isBlurry => sharpness > 0 && sharpness < 45;
  bool get isTooDark => lighting > 0 && lighting < 45;

  /// Short, everyday one-liner describing the photo (§22).
  String get simpleSummary {
    switch (qualityStatus) {
      case PhotoQualityStatus.excellent:
        return 'Clear and easy to check';
      case PhotoQualityStatus.good:
        return 'Sharp enough to check';
      case PhotoQualityStatus.needsImprovement:
        return firstFix ?? 'Could be a bit clearer';
      case PhotoQualityStatus.poor:
        return firstFix ?? 'Hard to see';
    }
  }

  /// The single most useful thing to fix, in plain words. Null when fine.
  String? get firstFix {
    if (isBlurry) return 'Too blurry';
    if (isTooDark) return 'Too dark';
    if (framing > 0 && framing < 45) return 'Keep the whole item in frame';
    if (detail > 0 && detail < 45) return 'Move a little closer';
    if (sharpness > 0 && sharpness < 65) return 'Hold steadier';
    if (lighting > 0 && lighting < 65) return 'Try better lighting';
    return null;
  }

  static int _score(dynamic raw, {int fallback = 0}) {
    if (raw is num) {
      var v = raw.toDouble();
      if (v > 0 && v <= 1.0) v = v * 100; // tolerate 0..1 scale
      return v.round().clamp(0, 100);
    }
    if (raw is String) {
      final parsed = double.tryParse(raw);
      if (parsed != null) return _score(parsed, fallback: fallback);
    }
    return fallback;
  }

  factory PhotoQualityResult.fromJson(Map<String, dynamic> json) {
    final sharpness = _score(json['sharpness'] ?? json['sharpness_score']);
    final lighting = _score(json['lighting'] ?? json['lighting_score']);
    final framing = _score(json['framing'] ?? json['framing_score']);
    final detail = _score(json['detail'] ?? json['detail_score'] ?? json['useful_detail']);

    var score = _score(
      json['photo_quality_score'] ?? json['quality_score'] ?? json['score'],
      fallback: -1,
    );

    // If the model omitted the roll-up, derive it from the sub-scores rather
    // than guessing a pleasant-looking number.
    if (score < 0) {
      final parts = [sharpness, lighting, framing, detail].where((v) => v > 0).toList();
      score = parts.isEmpty ? 0 : (parts.reduce((a, b) => a + b) / parts.length).round();
    }

    final tips = <String>[];
    for (final key in ['improvement_tips', 'issues', 'tips']) {
      if (json[key] is List) {
        for (final t in json[key] as List) {
          if (t != null && t.toString().trim().isNotEmpty) tips.add(t.toString().trim());
        }
      }
    }

    return PhotoQualityResult(
      qualityScore: score,
      qualityStatus: PhotoQualityStatus.parse(
        json['quality_status'] as String? ?? json['status'] as String?,
        score,
      ),
      explanation: (json['reason'] as String? ?? json['explanation'] as String? ?? '').trim(),
      sharpness: sharpness,
      lighting: lighting,
      framing: framing,
      detail: detail,
      improvementTips: tips,
    );
  }

  Map<String, dynamic> toJson() => {
        'photo_quality_score': qualityScore,
        'quality_status': qualityStatus.name,
        'explanation': explanation,
        'sharpness': sharpness,
        'lighting': lighting,
        'framing': framing,
        'detail': detail,
        'improvement_tips': improvementTips,
      };

  factory PhotoQualityResult.fromStoredJson(Map<String, dynamic> json) {
    final score = _score(json['photo_quality_score'] ?? json['quality_score']);
    return PhotoQualityResult(
      qualityScore: score,
      qualityStatus: PhotoQualityStatus.parse(json['quality_status'] as String?, score),
      explanation: json['explanation'] as String? ?? '',
      sharpness: _score(json['sharpness']),
      lighting: _score(json['lighting']),
      framing: _score(json['framing']),
      detail: _score(json['detail']),
      improvementTips:
          (json['improvement_tips'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}
