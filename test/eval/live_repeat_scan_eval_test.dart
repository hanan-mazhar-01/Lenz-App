// Live evaluation against real photos and the real Gemini API (§32-35).
//
// Runs the app's actual pipeline (same prompts, schemas, engine and
// consistency logic) on a labelled dataset, scanning every item several
// times, and writes the §33 metrics to eval_results/.
//
// Skipped unless both are set:
//   LENZ_EVAL_GEMINI_KEY   a Gemini API key (never commit it)
//   LENZ_EVAL_DATASET      path to a manifest JSON (see docs/AUTHENTICITY_ENGINE.md)
// Optional:
//   LENZ_EVAL_REPEATS      scans per item (default 10)
//   LENZ_EVAL_MODEL        default gemini-3.1-flash-lite (what production uses first)
//
//   LENZ_EVAL_GEMINI_KEY=... LENZ_EVAL_DATASET=eval/manifest.json \
//     flutter test test/eval/live_repeat_scan_eval_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:replica_detector/core/config/authenticity_engine_config.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/repositories/gemini_authentication_repository.dart';
import 'package:replica_detector/services/gemini_service.dart';
import 'package:replica_detector/services/scan_consistency_service.dart';

import 'eval_metrics.dart';

/// Calls Gemini directly with the same generationConfig as the Cloud
/// Function, so results match production.
class DirectGeminiService implements GeminiService {
  final String apiKey;
  final String model;
  DirectGeminiService(this.apiKey, this.model);

  @override
  Future<Map<String, dynamic>> generateStructuredContent({
    required String prompt,
    List<Map<String, dynamic>>? inlineImages,
    String? requestTypeLabel,
    int? maxOutputTokens,
    Duration? timeout,
    Map<String, dynamic>? responseSchema,
  }) async {
    final body = {
      'contents': [
        {
          'parts': [...?inlineImages, {'text': prompt}],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'temperature': 0,
        'seed': 20260926,
        'maxOutputTokens': maxOutputTokens ?? 2048,
        'responseSchema': ?responseSchema,
        if (model == 'gemini-3.1-flash-lite') 'thinkingConfig': {'thinkingBudget': 0},
      },
    };
    for (var attempt = 1; attempt <= 3; attempt++) {
      final res = await http
          .post(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
            body: jsonEncode(body),
          )
          .timeout(timeout ?? const Duration(seconds: 90));
      if (res.statusCode == 429 || res.statusCode >= 500) {
        await Future.delayed(Duration(seconds: 3 * attempt));
        continue;
      }
      if (res.statusCode != 200) throw Exception('Gemini ${res.statusCode}: ${res.body}');
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final text = ((decoded['candidates'] as List).first['content']['parts'] as List).first['text'] as String;
      final parsed = jsonDecode(text.trim()) as Map<String, dynamic>;
      return {...parsed, '_meta': {'model': model, 'schemaEnforced': responseSchema != null}};
    }
    throw Exception('Gemini unavailable after retries');
  }

  @override
  void close() {}
}

void main() {
  final key = Platform.environment['LENZ_EVAL_GEMINI_KEY'] ?? '';
  final datasetPath = Platform.environment['LENZ_EVAL_DATASET'] ?? '';
  final skip = key.isEmpty || datasetPath.isEmpty
      ? 'Set LENZ_EVAL_GEMINI_KEY and LENZ_EVAL_DATASET to run the live evaluation.'
      : null;

  test('live repeat-scan evaluation', () async {
    final repeats = int.tryParse(Platform.environment['LENZ_EVAL_REPEATS'] ?? '') ?? 10;
    final model = Platform.environment['LENZ_EVAL_MODEL'] ?? 'gemini-3.1-flash-lite';
    final manifestFile = File(datasetPath);
    final baseDir = manifestFile.parent.path;
    final manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final repo = GeminiAuthenticationRepository(geminiService: DirectGeminiService(key, model));

    final scans = <EvalScan>[];
    final logs = <Map<String, dynamic>>[];

    for (final raw in (manifest['items'] as List).cast<Map>()) {
      final entry = Map<String, dynamic>.from(raw);
      final category = ProductCategory.values.firstWhere(
        (c) => c.name == entry['category'],
        orElse: () => ProductCategory.accessories,
      );
      final product = Product(
        id: entry['id'] as String,
        name: entry['name'] as String? ?? '',
        brand: entry['brand'] as String? ?? '',
        model: entry['model'] as String? ?? '',
        category: category,
        categoryCode: entry['category_code'] as String?,
        imageAsset: '',
        identificationConfidence: 0.9,
      );
      final images = (entry['images'] as Map).map(
        (k, v) => MapEntry(k.toString(), v.toString().startsWith('/') ? v.toString() : '$baseDir/$v'),
      );
      final plan = await repo.getRequiredEvidence(product);
      final history = <AuthenticationReport>[];

      for (var r = 1; r <= repeats; r++) {
        // A fresh repository cache per scan so nothing is reused between runs.
        repo.clearScanCaches();
        repo.imagePrep.clearCache();
        final scored = await repo.finalizeReport(
          product: product,
          evidenceItems: plan,
          capturedImages: images,
          identificationConfidence: 90,
          scanId: '${product.id}_$r',
        );
        final shown = ScanConsistencyService.reconcile(report: scored, history: history);
        history.add(shown);
        scans.add(EvalScan(
          itemId: product.id,
          category: product.categoryCode ?? category.name,
          genuine: entry['truth'] == 'GENUINE',
          repeat: r,
          rawVerdict: scored.verdict,
          shownVerdict: shown.verdict,
          confidence: shown.authenticationConfidence,
        ));
        logs.add({...shown.analysisLog, 'raw_response': '<see analysis log in app>'});
        // ignore: avoid_print
        print('${product.id} #$r raw=${scored.verdict.code} shown=${shown.verdict.code} '
            '${shown.authenticationConfidence}%');
      }
    }

    final out = {
      'engine_version': AuthenticityEngineConfig.engineVersion,
      'prompt_version': AuthenticityEngineConfig.promptVersion,
      'model': model,
      'repeats_per_item': repeats,
      'run_at': DateTime.now().toIso8601String(),
      'metrics_raw_per_scan': EvalMetrics.compute(scans, shown: false).toJson(),
      'metrics_shown_with_consistency': EvalMetrics.compute(scans).toJson(),
      'scans': scans.map((s) => s.toJson()).toList(),
      'analysis_logs': logs,
    };
    final dir = Directory('eval_results')..createSync(recursive: true);
    final file = File('${dir.path}/eval_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
    // ignore: avoid_print
    print('\nMetrics written to ${file.path}\n${const JsonEncoder.withIndent('  ').convert(out['metrics_shown_with_consistency'])}');
  }, skip: skip, timeout: const Timeout(Duration(hours: 2)));
}
