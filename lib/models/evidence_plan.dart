import 'evidence.dart';

class EvidenceRequirement {
  final String id;
  final String title;
  final String guide;
  final String reason;
  final bool required;
  final EvidenceWeight weight;

  const EvidenceRequirement({
    required this.id,
    required this.title,
    required this.guide,
    required this.reason,
    this.required = true,
    this.weight = EvidenceWeight.medium,
  });

  factory EvidenceRequirement.fromJson(Map<String, dynamic> json) {
    final rawId = (json['id'] as String? ?? '').trim();
    final title = (json['title'] as String? ?? 'Detail Photo').trim();
    return EvidenceRequirement(
      id: rawId.isNotEmpty ? rawId : _slug(title),
      title: title,
      guide: (json['guide'] as String? ?? 'Capture this angle clearly in good lighting.').trim(),
      reason: (json['reason'] as String? ?? '').trim(),
      required: json['required'] as bool? ?? true,
      weight: EvidenceWeight.parse(json['weight'] as String? ?? json['importance'] as String?),
    );
  }

  static String _slug(String input) {
    final s = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'evidence' : s;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'guide': guide,
        'reason': reason,
        'required': required,
        'weight': weight.name,
      };

  EvidenceItem toEvidenceItem({required int index, String imageAsset = ''}) {
    return EvidenceItem(
      id: id,
      index: index,
      title: title,
      guide: guide,
      reason: reason,
      isRequired: required,
      weight: weight,
      imageAsset: imageAsset,
      score: 0,
      status: EvidenceStatus.pending,
      whyCorrect: reason.isNotEmpty ? reason : null,
      whatToLookFor: reason.isNotEmpty ? [reason] : const [],
    );
  }
}

class EvidencePlan {
  final List<EvidenceRequirement> requiredEvidence;

  const EvidencePlan({required this.requiredEvidence});

  factory EvidencePlan.fromJson(Map<String, dynamic> json) {
    final list = <EvidenceRequirement>[];
    final rawList = json['requiredEvidence'] ?? json['required_evidence'] ?? json['evidence_plan'];
    if (rawList is List) {
      final seenIds = <String>{};
      for (final item in rawList) {
        Map<String, dynamic>? map;
        if (item is Map<String, dynamic>) {
          map = item;
        } else if (item is Map) {
          map = Map<String, dynamic>.from(item);
        }
        if (map == null) continue;

        var req = EvidenceRequirement.fromJson(map);
        // Guarantee unique ids so captured photos can never collide.
        if (!seenIds.add(req.id)) {
          var n = 2;
          while (!seenIds.add('${req.id}_$n')) {
            n++;
          }
          req = EvidenceRequirement(
            id: '${req.id}_$n',
            title: req.title,
            guide: req.guide,
            reason: req.reason,
            required: req.required,
            weight: req.weight,
          );
        }
        list.add(req);
      }
    }
    return EvidencePlan(requiredEvidence: list);
  }

  Map<String, dynamic> toJson() => {
        'requiredEvidence': requiredEvidence.map((e) => e.toJson()).toList(),
      };
}
