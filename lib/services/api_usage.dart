import 'dart:convert';

import '../core/config/authenticity_engine_config.dart';

/// Token usage of one model call.
class ApiCallUsage {
  final String label;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final int images;
  final int durationMs;

  /// True when the backend did not report token counts and they were
  /// estimated from the request size.
  final bool estimated;

  const ApiCallUsage({
    required this.label,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.images,
    required this.durationMs,
    required this.estimated,
  });

  double get costUsd {
    final price = AuthenticityEngineConfig.pricePerMillionTokens[model] ??
        AuthenticityEngineConfig.pricePerMillionTokens[AuthenticityEngineConfig.defaultModel]!;
    return inputTokens / 1e6 * price.input + outputTokens / 1e6 * price.output;
  }

  /// Reads usage from a response's `_meta.usage` (Gemini `usageMetadata`
  /// forwarded by the backend), or estimates it when absent.
  factory ApiCallUsage.fromResponse({
    required String label,
    required Map<String, dynamic> response,
    required String prompt,
    required int images,
    required int durationMs,
    String? requestedModel,
  }) {
    final meta = response['_meta'] is Map ? Map<String, dynamic>.from(response['_meta'] as Map) : const <String, dynamic>{};
    final usage = meta['usage'] is Map ? Map<String, dynamic>.from(meta['usage'] as Map) : null;
    final model = (meta['model'] as String?) ?? requestedModel ?? AuthenticityEngineConfig.defaultModel;
    if (usage != null && usage['promptTokenCount'] is num) {
      final out = ((usage['candidatesTokenCount'] as num?) ?? 0).toInt() + ((usage['thoughtsTokenCount'] as num?) ?? 0).toInt();
      return ApiCallUsage(
        label: label,
        model: model,
        inputTokens: (usage['promptTokenCount'] as num).toInt(),
        outputTokens: out,
        images: images,
        durationMs: durationMs,
        estimated: false,
      );
    }
    final body = Map<String, dynamic>.from(response)..remove('_meta');
    return ApiCallUsage(
      label: label,
      model: model,
      inputTokens: images * AuthenticityEngineConfig.estimatedTokensPerImage + (prompt.length / 4).round(),
      outputTokens: (jsonEncode(body).length / 4).round(),
      images: images,
      durationMs: durationMs,
      estimated: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'model': model,
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'images': images,
        'duration_ms': durationMs,
        'estimated': estimated,
        'cost_usd': double.parse(costUsd.toStringAsFixed(6)),
      };
}

/// All model calls made for one scan.
class ApiUsageLog {
  final List<ApiCallUsage> calls = [];

  void add(ApiCallUsage u) => calls.add(u);
  void clear() => calls.clear();

  int get inputTokens => calls.fold(0, (s, c) => s + c.inputTokens);
  int get outputTokens => calls.fold(0, (s, c) => s + c.outputTokens);
  int get images => calls.fold(0, (s, c) => s + c.images);
  double get costUsd => calls.fold(0.0, (s, c) => s + c.costUsd);
  bool get anyEstimated => calls.any((c) => c.estimated);

  Map<String, dynamic> toJson() => {
        'calls': calls.map((c) => c.toJson()).toList(),
        'call_count': calls.length,
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'images_sent': images,
        'estimated_cost_usd': double.parse(costUsd.toStringAsFixed(6)),
        'token_counts_estimated': anyEstimated,
      };
}
