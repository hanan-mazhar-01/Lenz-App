import 'product.dart';

class GuideStep {
  final int stepNumber;
  final String title;
  final String description;
  final String imageAsset;
  final String authenticSignal;
  final String replicaSignal;

  const GuideStep({
    required this.stepNumber,
    required this.title,
    required this.description,
    required this.imageAsset,
    required this.authenticSignal,
    required this.replicaSignal,
  });
}

class GuideArticle {
  final String id;
  final String title;
  final String subtitle;
  final ProductCategory category;
  final int readTimeMinutes;
  final String difficulty;
  final String imageAsset;
  final String summary;
  final List<GuideStep> steps;
  final List<String> redFlags;
  final String proTip;

  const GuideArticle({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.readTimeMinutes,
    required this.difficulty,
    required this.imageAsset,
    required this.summary,
    required this.steps,
    required this.redFlags,
    required this.proTip,
  });
}

