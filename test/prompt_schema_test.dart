import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/data/evidence_profiles.dart';
import 'package:replica_detector/models/evidence_record.dart';
import 'package:replica_detector/models/product_reference.dart';
import 'package:replica_detector/services/authenticity_prompts.dart';

import 'support/fixtures.dart';

/// Keys Gemini's responseSchema subset accepts. Anything else makes the API
/// reject the request (400 INVALID_ARGUMENT), which would break every scan.
const _allowedKeys = {'type', 'properties', 'required', 'enum', 'items', 'nullable', 'propertyOrdering', 'description', 'format', 'minItems', 'maxItems'};
const _types = {'OBJECT', 'ARRAY', 'STRING', 'NUMBER', 'INTEGER', 'BOOLEAN'};

void checkSchema(Map<String, dynamic> s, String path) {
  for (final k in s.keys) {
    expect(_allowedKeys, contains(k), reason: '$path: unsupported key "$k"');
  }
  expect(_types, contains(s['type']), reason: '$path: bad type ${s['type']}');
  if (s['enum'] != null) {
    final e = s['enum'] as List;
    expect(e, isNotEmpty, reason: '$path: empty enum');
    expect(e.toSet().length, e.length, reason: '$path: duplicate enum values');
  }
  if (s['type'] == 'OBJECT') {
    final props = Map<String, dynamic>.from(s['properties'] as Map);
    for (final r in (s['required'] as List? ?? const [])) {
      expect(props.keys, contains(r), reason: '$path: required "$r" missing from properties');
    }
    for (final p in (s['propertyOrdering'] as List? ?? const [])) {
      expect(props.keys, contains(p), reason: '$path: ordering "$p" not a property');
    }
    props.forEach((k, v) => checkSchema(Map<String, dynamic>.from(v as Map), '$path.$k'));
  }
  if (s['type'] == 'ARRAY') checkSchema(Map<String, dynamic>.from(s['items'] as Map), '$path[]');
}

void main() {
  final profiles = [for (final p in EvidenceProfileRegistry.profiles) EvidenceProfileRegistry.resolve(identity(category: p.categoryCodes.first, brand: 'B', family: 'M'))];

  test('every schema uses only the Gemini responseSchema subset', () {
    checkSchema(AuthenticityPrompts.identificationSchema, 'identification');
    for (final p in profiles) {
      checkSchema(AuthenticityPrompts.recommendationSchema(p), 'recommendation/${p.id}');
      checkSchema(AuthenticityPrompts.photoCheckSchema(p), 'photoCheck/${p.id}');
      checkSchema(AuthenticityPrompts.photoAnalysisSchema(p), 'photoAnalysis/${p.id}');
    }
    checkSchema(AuthenticityPrompts.finalEvaluationSchema(const []), 'final/empty');
  });

  test('schemas stay under the Cloud Function size limit (30,000 chars)', () {
    for (final p in profiles) {
      expect(jsonEncode(AuthenticityPrompts.photoAnalysisSchema(p)).length, lessThan(30000), reason: p.id);
    }
  });

  test('the photo analysis schema constrains checkpoint ids to the profile', () {
    final p = appleWatch();
    final s = AuthenticityPrompts.photoAnalysisSchema(p);
    final ids = ((s['properties'] as Map)['assessments']['items']['properties']['checkpoint_id']['enum'] as List).toSet();
    expect(ids, containsAll(['aw_sensor_construction', 'aw_device_info', 'other']));
    expect(ids, isNot(contains('mw_dial_printing')));
  });

  test('observations come before any judgement in the analysis output', () {
    final order = AuthenticityPrompts.photoAnalysisSchema(appleWatch())['propertyOrdering'] as List;
    expect(order.indexOf('observed_text'), lessThan(order.indexOf('assessments')));
    final item = (AuthenticityPrompts.photoAnalysisSchema(appleWatch())['properties'] as Map)['assessments']['items'];
    final itemOrder = item['propertyOrdering'] as List;
    expect(itemOrder.indexOf('observation'), lessThan(itemOrder.indexOf('outcome')));
  });

  test('the combined analysis schema uses only the Gemini schema subset and constrains ids', () {
    final schema = AuthenticityPrompts.combinedAnalysisSchema(imageIds: ['P1', 'P2', 'C1'], claimIds: ['r1'], requestIds: ['back_sensor']);
    checkSchema(schema, 'combined');
    final finding = ((schema['properties'] as Map)['findings'] as Map)['items'] as Map;
    expect(((finding['properties'] as Map)['claim_id'] as Map)['enum'], ['r1', 'none']);
    expect(jsonEncode(schema), isNot(contains('confidence')), reason: 'no numeric confidence is ever requested');
  });

  test('the combined prompt carries the safeguards and uses no web search', () {
    final p = AuthenticityPrompts.combinedAnalysisPrompt(
      profile: appleWatch(),
      images: const [(id: 'P1', description: 'First photo'), (id: 'C1', description: 'close-up of P1')],
      checklist: ProductReference.checklist(appleWatch()),
      earlierObservations: const [],
    );
    expect(p, contains('never CONFLICTS'));
    expect(p, contains('GENERIC_QUALITY'));
    expect(p, contains('different generation'));
    expect(p, contains('not independent evidence'));
    expect(p, contains('not a manufacturer verification'));
    expect(p, contains('No web search is available'));
    expect(p, contains('knowledge_scope'));
    expect(p, isNot(contains('CURATED REFERENCE')));
  });

  test('no prompt enables or asks for web search', () {
    final all = [
      AuthenticityPrompts.identificationPrompt,
      AuthenticityPrompts.combinedAnalysisPrompt(profile: appleWatch(), images: const [], checklist: ProductReference.checklist(appleWatch()), earlierObservations: const []),
      jsonEncode(AuthenticityPrompts.combinedAnalysisSchema(imageIds: ['P1'], claimIds: const [], requestIds: const [])),
    ].join(' ');
    expect(all, isNot(contains('google_search')));
    expect(all.toLowerCase(), isNot(contains('search google')));
  });

  test('identification and photo checks must say where the image comes from', () {
    final ident = AuthenticityPrompts.identificationSchema;
    expect(ident['required'], contains('image_source'));
    expect(((ident['properties'] as Map)['image_source'] as Map)['enum'], contains('INTERNET_IMAGE'));
    final check = AuthenticityPrompts.photoCheckSchema(appleWatch());
    expect(check['required'], contains('image_source'));
    expect(AuthenticityPrompts.identificationPrompt, contains('NOT A REAL PHOTO OF THE ITEM'));
  });

  test('identification offers only the supported categories', () {
    final codes = (AuthenticityPrompts.identificationSchema['properties'] as Map)['category_code']['enum'] as List;
    expect(codes, isNot(contains('ELECTRONICS')));
    expect(codes, isNot(contains('COSMETICS')));
    expect(codes, isNot(contains('OTHER')));
    expect(AuthenticityPrompts.identificationPrompt, contains('GENERIC / LOCAL UNBRANDED ITEM'));
    expect(AuthenticityPrompts.identificationPrompt, contains('perfume and fragrance bottles'));
  });

  group('Prompts do not contradict the engine', () {
    final analysis = AuthenticityPrompts.photoAnalysisPrompt(profile: appleWatch(), requestId: 'back_sensor', isInitialPhoto: false);

    test('alternative explanations are requested only when genuinely plausible', () {
      expect(analysis, contains('ONLY when a benign explanation is genuinely plausible'));
      expect(analysis, isNot(contains('Always fill alternative_explanation')));
    });

    test('no prompt asks for a numeric authenticity confidence', () {
      for (final text in [
        AuthenticityPrompts.identificationPrompt,
        analysis,
        AuthenticityPrompts.recommendationPrompt(profile: appleWatch(), coveredRequestIds: const {}),
        AuthenticityPrompts.finalEvaluationPrompt(profile: appleWatch(), photos: const [], mismatches: const [], supporting: const [], provisionalVerdict: 'x'),
      ]) {
        expect(text.toLowerCase(), isNot(contains('authenticity confidence')));
        expect(text.toLowerCase(), isNot(contains('authenticity_confidence')));
      }
    });

    test('absence of a detail is never an inconsistency, but a missing feature in a visible area is', () {
      expect(analysis, contains('A detail you cannot see is never INCONSISTENT'));
      expect(analysis, contains('ABSENT from a clearly visible area'));
    });

    test('generation-specific checks are marked when the generation is unknown', () {
      final unknownGen = AuthenticityPrompts.photoAnalysisPrompt(
          profile: appleWatchSeries(generation: null), requestId: 'back_sensor', isInitialPhoto: false);
      expect(unknownGen, contains('generation is NOT established: report UNCLEAR, never INCONSISTENT'));
    });

    test("only the user's own photo is sent: no generated or cropped images are described", () {
      expect(analysis, isNot(contains('IMAGE 2')));
      expect(analysis.toLowerCase(), isNot(contains('crop')));
    });

    test('manufacturer verification is never claimed', () {
      expect(analysis, contains('Never claim anything was verified with the manufacturer'));
    });

    test('the final evaluation can only weaken evidence', () {
      final f = AuthenticityPrompts.finalEvaluationPrompt(profile: appleWatch(), photos: const [], mismatches: const [], supporting: const [], provisionalVerdict: 'x');
      expect(f, contains('Never add evidence of authenticity'));
    });
  });

  test('the model cannot claim manufacturer verification through the schema', () {
    final kinds = ((AuthenticityPrompts.photoAnalysisSchema(appleWatch())['properties'] as Map)['assessments']['items']['properties']['evidence_kind']['enum'] as List);
    expect(kinds, isNot(contains('MANUFACTURER_VERIFIED')));
    expect(EvidenceKind.parse('MANUFACTURER_VERIFIED'), isNot(EvidenceKind.manufacturerVerified));
  });
}
