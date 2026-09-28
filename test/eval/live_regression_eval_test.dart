// Live regression evaluation against real photos and the real Gemini API.
//
// For every case the photos are identified, checked and analysed ONCE, then
// the same evidence goes through three final stages:
//
//   v3_legacy        engine v3: text-only final evaluation + per-photo engine
//   v4_combined      engine v4: one combined multi-image analysis with
//                    Gemini's own knowledge + app checklist, validated by
//                    FinalVerdictValidator (no web search or research)
//
// and records verdicts, false-authentic / false-replica / inconclusive rates,
// and measured tokens and cost.
//
// Skipped unless both are set:
//   LENZ_EVAL_GEMINI_KEY   a Gemini API key (never commit it)
//   LENZ_EVAL_DATASET      path to a manifest JSON (docs/AUTHENTICITY_ENGINE.md)
//
//   LENZ_EVAL_GEMINI_KEY=... LENZ_EVAL_DATASET=eval_data/manifest.json \
//     flutter test test/eval/live_regression_eval_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:replica_detector/core/config/authenticity_engine_config.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/evidence_record.dart';
import 'package:replica_detector/models/evidence_validation.dart';
import 'package:replica_detector/models/product_reference.dart';
import 'package:replica_detector/repositories/gemini_authentication_repository.dart';
import 'package:replica_detector/services/api_usage.dart';
import 'package:replica_detector/services/evidence_decision_engine.dart';
import 'package:replica_detector/services/final_verdict_validator.dart';
import 'package:replica_detector/services/gemini_service.dart';

import 'regression_metrics.dart';

/// Calls Gemini directly with the same generationConfig and response checks
/// as the Cloud Function (no tools). Real usageMetadata is reported back as
/// `_meta.usage`.
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
    String? scanId,
    String? thinkingLevel,
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
        'maxOutputTokens': (maxOutputTokens ?? 2048).clamp(64, 8192),
        'responseSchema': ?responseSchema,
        'thinkingConfig': thinkingLevel != null ? {'thinkingLevel': thinkingLevel} : {'thinkingBudget': 0},
      },
    };
    for (var attempt = 1; attempt <= 4; attempt++) {
      http.Response res;
      try {
        res = await http
            .post(
              Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
              headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 150));
      } catch (_) {
        await Future.delayed(Duration(seconds: 4 * attempt));
        continue;
      }
      if (res.statusCode == 429 || res.statusCode >= 500) {
        // ignore: avoid_print
        print('  [retry] $requestTypeLabel HTTP ${res.statusCode}, attempt $attempt');
        await Future.delayed(Duration(seconds: 4 * attempt));
        continue;
      }
      if (res.statusCode != 200) throw Exception('Gemini ${res.statusCode}: ${res.body.substring(0, res.body.length.clamp(0, 300))}');
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final cand = (decoded['candidates'] as List).first as Map<String, dynamic>;
      final finish = cand['finishReason'] ?? 'STOP';
      // Same rule as the backend: anything but STOP is an error.
      if (finish != 'STOP') throw FormatException('response stopped early ($finish)');
      final text = [
        for (final p in (cand['content']['parts'] as List).cast<Map>())
          if (p['thought'] != true && p['text'] is String) p['text'] as String,
      ].join();
      final parsed = jsonDecode(text.trim()) as Map<String, dynamic>;
      return {
        ...parsed,
        '_meta': {'model': model, 'schemaEnforced': responseSchema != null, 'usage': decoded['usageMetadata'], 'finishReason': finish},
      };
    }
    throw Exception('Gemini unavailable after retries');
  }

  @override
  void close() {}
}

bool _matches(String? expected, String? actual) {
  if (expected == null || expected.isEmpty) return true;
  if (expected.contains('|')) return expected.split('|').any((e) => _matches(e, actual));
  final e = expected.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  final a = (actual ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return a.isNotEmpty && (a.contains(e) || e.contains(a));
}

const arms = ['v3_legacy', 'v4_combined'];

void main() {
  final key = Platform.environment['LENZ_EVAL_GEMINI_KEY'] ?? '';
  final datasetPath = Platform.environment['LENZ_EVAL_DATASET'] ?? '';
  final only = (Platform.environment['LENZ_EVAL_CASES'] ?? '').split(',').where((s) => s.isNotEmpty).toSet();
  final skip = key.isEmpty || datasetPath.isEmpty ? 'Set LENZ_EVAL_GEMINI_KEY and LENZ_EVAL_DATASET to run the live evaluation.' : null;

  test('live regression evaluation: engine v3 vs engine v4 on the same photos', () async {
    final model = AuthenticityEngineConfig.defaultModel;
    final manifestFile = File(datasetPath);
    final baseDir = manifestFile.parent.path;
    final manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    String resolve(String p) => p.startsWith('/') ? p : '$baseDir/$p';

    final runs = <CaseRun>[];
    final caseLogs = <Map<String, dynamic>>[];
    final usageByArm = {for (final a in ['capture', ...arms]) a: <ApiCallUsage>[]};
    final msByArm = {for (final a in arms) a: <int>[]};

    for (final raw in (manifest['cases'] as List).cast<Map>()) {
      final c = Map<String, dynamic>.from(raw);
      final caseId = c['id'] as String;
      if (only.isNotEmpty && !only.contains(caseId)) continue;
      final truth = Truth.parse(c['truth'] as String?);
      final caseWatch = Stopwatch()..start();
      final repo = GeminiAuthenticationRepository(geminiService: DirectGeminiService(key, model), finalStageMode: FinalStageMode.combined);
      GeminiAuthenticationRepository.clearRankingCache();
      final log = <String, dynamic>{
        'case': caseId,
        'truth': truth.name,
        'truth_source': c['truth_source'],
        'tags': c['tags'],
        'baseline_v2_verdict': c['baseline_v2_verdict'],
        'baseline_v3_device_verdict': c['baseline_v3_verdict'],
      };
      var mark = 0;
      List<ApiCallUsage> since() {
        final out = repo.usage.calls.sublist(mark);
        mark = repo.usage.calls.length;
        return out;
      }

      try {
        // ------------------------------------------------- identification
        final firstPath = resolve(c['first_photo'] as String);
        final ident = await repo.identifyProduct(firstPath);
        final expected = Map<String, dynamic>.from(c['expected'] as Map? ?? const {});
        if (!ident.productDetected) {
          log['identification'] = {'detected': false, 'reason': ident.reason, 'message': ident.message};
          usageByArm['capture']!.addAll(since());
          caseLogs.add(log);
          // ignore: avoid_print
          print('$caseId (${truth.name}): not scanned - ${ident.reason}');
          continue;
        }
        var ctx = repo.createContext(ident.toProduct(imageAsset: firstPath));
        final ranking = await repo.recommendEvidence(ctx);
        ctx = ctx.copyWith(ranking: ranking);
        final initial = await repo.analyzeInitialPhoto(ctx: ctx, imagePath: firstPath, itemBox: ident.itemBox);
        ctx = repo.absorbPhoto(ctx, initial);
        log['identification'] = {
          'detected': true,
          'correct': _matches(expected['category_code'] as String?, ident.resolvedCategoryCode) &&
              _matches(expected['brand'] as String?, ident.identity?.brand.value) &&
              _matches(expected['model_family'] as String?, ident.identity?.modelFamily.value),
          'profile': ctx.profile.id,
          'identity': ident.identity?.toJson(),
          'expected': expected,
        };

        // ------------------------------------ per-photo check + analysis
        final photos = <PhotoEvidence>[initial];
        final photoLog = <Map<String, dynamic>>[];
        for (final pRaw in (c['photos'] as List).cast<Map>()) {
          if (photos.length >= AuthenticityEngineConfig.maxPhotosPerScan) break;
          final p = Map<String, dynamic>.from(pRaw);
          final part = p['part'] as String?;
          final requested = part != null && ctx.profile.request(part) != null ? part : null;
          final check = await repo.checkPhoto(ctx: ctx, imagePath: resolve(p['path'] as String), requestedId: requested, existing: photos);
          final entry = <String, dynamic>{
            'path': p['path'],
            'labelled_part': part,
            'matched': check.matchedRequestId,
            'accepted': check.validation.isAccepted,
            'issues': check.quality.issues,
            'duplicate_of': check.duplicateOfPhotoId,
          };
          // The harness stands in for a user who photographed the matched
          // part (a wrong-part photo is refused in the app and retaken).
          if (!check.isDuplicate && check.matchedRequestId != 'none') {
            final ev = await repo.analyzePhoto(ctx: ctx, check: check, keptDespiteLowQuality: check.validation.verdict == EvidenceVerdict.rejectedQuality);
            photos.add(ev);
            ctx = repo.absorbPhoto(ctx, ev);
            entry['photo_id'] = ev.photoId;
          }
          photoLog.add(entry);
        }
        log['photos'] = photoLog;
        usageByArm['capture']!.addAll(since());
        final preliminary = repo.evaluate(ctx, photos);

        Map<String, dynamic> record(String arm, EngineResult r, int ms, {Map<String, dynamic>? extra}) {
          runs.add(CaseRun(caseId: caseId, strategy: arm, truth: truth, photos: photos.length, verdict: r.verdict, sufficient: r.sufficient));
          msByArm[arm]!.add(ms);
          final u = since();
          usageByArm[arm]!.addAll(u);
          return {
            'verdict': r.verdict.code,
            'strength': r.strength.name,
            'gaps': r.gaps.map((g) => g.description).toList(),
            'trace': r.trace,
            'supporting': r.supporting.map((x) => '${x.featureName} [${x.referenceSource}]').toList(),
            'contradicting': r.contradicting.map((x) => '${x.featureName}: ${x.observation}').toList(),
            'ms': ms,
            'cost_usd': u.fold<double>(0, (s, x) => s + x.costUsd),
            ...?extra,
          };
        }

        // ---------------------------------------------- engine v3
        var sw = Stopwatch()..start();
        final fin = await repo.finalEvaluation(ctx, photos, preliminary);
        log['v3_legacy'] = record('v3_legacy', repo.evaluate(ctx, photos, finalEvaluation: fin), sw.elapsedMilliseconds);

        // ------------------------------------ engine v4 (knowledge + checklist)
        sw = Stopwatch()..start();
        final checklist = ProductReference.checklist(ctx.profile);
        final comb = await repo.combinedAnalysis(ctx, photos, checklist, preliminary);
        final v4 = FinalVerdictValidator.validate(profile: ctx.profile, photos: photos, checklist: checklist, analysis: comb.analysis, preliminary: preliminary);
        log['v4_combined'] = record('v4_combined', v4, sw.elapsedMilliseconds, extra: {
          'proposed': comb.analysis.proposedVerdict,
          'reasoning': comb.analysis.reasoning,
          'images': comb.images,
          'findings': comb.analysis.findings
              .map((f) => '${f.claimId} ${f.partRequestId ?? f.area}: ${f.comparison}/${f.visibility}/${f.reliability.code}/${f.knowledgeScope}${f.hardToCopy ? '/hard' : ''}')
              .toList(),
        });
      } catch (e) {
        log['error'] = e.toString();
      }
      log['api_usage'] = repo.usage.toJson();
      caseLogs.add(log);
      String v(String arm) {
        final m = log[arm] as Map?;
        return m == null ? '-' : '${m['verdict']}${m['proposed'] != null ? ' (proposed ${m['proposed']})' : ''}';
      }

      // ignore: avoid_print
      print('$caseId (${truth.name}): v3=${v('v3_legacy')} | v4=${v('v4_combined')} '
          '| cost=\$${repo.usage.costUsd.toStringAsFixed(4)} | ${caseWatch.elapsed.inSeconds}s '
          '(v3 ${(log['v3_legacy'] as Map?)?['ms']}ms, v4 ${(log['v4_combined'] as Map?)?['ms']}ms)'
          '${log['error'] != null ? ' ERROR ${log['error']}' : ''}');
    }

    Map<String, dynamic> armSummary(String arm) {
      final r = runs.where((x) => x.strategy == arm);
      final unlabeled = r.where((x) => x.truth == Truth.unlabeled).toList();
      final u = usageByArm[arm]!;
      final ms = msByArm[arm]!;
      return {
        'all_labelled': RegressionMetrics.compute(r).toJson(),
        'owner_labelled_1080p': RegressionMetrics.compute(r.where((x) => !x.caseId.endsWith('_hires'))).toJson(),
        'labelled_by_appearance_full_res': RegressionMetrics.compute(r.where((x) => x.caseId.endsWith('_hires'))).toJson(),
        'unlabeled_cases': unlabeled.length,
        'unlabeled_verdicts': {for (final x in unlabeled) x.caseId: x.verdict.code},
        'final_stage_cost_usd_per_scan': r.isEmpty ? 0 : double.parse((u.fold<double>(0, (s, x) => s + x.costUsd) / r.length).toStringAsFixed(5)),
        'final_stage_seconds_median': ms.isEmpty ? 0 : ((ms..sort())[ms.length ~/ 2] / 1000).toStringAsFixed(1),
      };
    }

    final captureUsage = usageByArm['capture']!;
    final scanned = caseLogs.where((l) => (l['identification'] as Map?)?['detected'] == true).length;
    final out = {
      'engine_version': AuthenticityEngineConfig.engineVersion,
      'prompt_version': AuthenticityEngineConfig.promptVersion,
      'model': model,
      'final_thinking_level': AuthenticityEngineConfig.finalThinkingLevel,
      'run_at': DateTime.now().toIso8601String(),
      'dataset': manifest['description'],
      'cases': caseLogs.length,
      'scanned': scanned,
      'capture_stage_cost_usd_per_scan': scanned == 0 ? 0 : captureUsage.fold<double>(0, (s, x) => s + x.costUsd) / scanned,
      for (final a in arms) a: armSummary(a),
      'runs': runs.map((r) => r.toJson()).toList(),
      'case_logs': caseLogs,
    };
    final dir = Directory('eval_results')..createSync(recursive: true);
    final file = File('${dir.path}/v4_comparison_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
    // ignore: avoid_print
    print('\nResults written to ${file.path}');
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert({for (final a in arms) a: (out[a] as Map)..remove('unlabeled_verdicts')}));
    expect(runs, isNotEmpty);
  }, skip: skip, timeout: const Timeout(Duration(hours: 3)));

  test('recorded verdict codes are stable identifiers', () {
    expect(Verdict.values.map((v) => v.code), ['LIKELY_AUTHENTIC', 'LIKELY_REPLICA', 'INCONCLUSIVE']);
    expect(VariationCheck.ruledOut.code, 'RULED_OUT');
    expect(GapType.values, isNotEmpty);
  });
}
