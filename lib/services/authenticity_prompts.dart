import '../core/config/authenticity_engine_config.dart';
import '../data/authentication_rules.dart';
import '../data/reference_library.dart';
import '../models/evidence_finding.dart';
import '../models/product.dart';

/// All authenticity prompts and their response schemas, in one place and
/// under one version number ([AuthenticityEngineConfig.promptVersion]).
///
/// Schemas use Gemini's `responseSchema` format. The backend forwards them
/// as `generationConfig.responseSchema`, which makes Gemini emit exactly
/// these fields with exactly these enum values. The prompts also embed the
/// schema text, so older backends that ignore `responseSchema` still work.
abstract final class AuthenticityPrompts {
  static const categoryCodes = [
    'WATCH', 'HANDBAG', 'SNEAKER', 'SHOE', 'CLOTHING', 'WALLET',
    'ACCESSORY', 'SUNGLASSES', 'EYEGLASSES', 'OTHER',
  ];

  static const findingTypes = [
    'AUTHENTIC_INDICATOR', 'COUNTERFEIT_INDICATOR', 'MISSING', 'AMBIGUOUS', 'UNVERIFIABLE',
  ];

  static const strengths = ['WEAK', 'MODERATE', 'STRONG'];

  static const dimensions = [
    'BRAND_MODEL', 'DESIGN', 'MATERIAL', 'CONSTRUCTION', 'LOGO', 'TYPOGRAPHY', 'STITCHING',
    'HARDWARE', 'SHAPE', 'COLOR_TEXTURE', 'PRODUCT_SPECIFIC', 'SERIAL_MARKING', 'PACKAGING', 'OTHER',
  ];

  static const qualityIssues = [
    'LOW_RESOLUTION', 'BLUR', 'OUT_OF_FOCUS', 'TOO_DARK', 'OVEREXPOSED', 'HARSH_SHADOWS', 'GLARE',
    'OCCLUSION', 'POOR_ANGLE', 'TOO_FAR', 'PARTIAL_ITEM', 'NONE',
  ];

  // =====================================================================
  // 1. Identification (first photo)
  // =====================================================================

  static const String identificationPrompt = '''You are a strict product presence validator and identifier for an authentication system.
Before attempting to identify any brand or product, perform an IMAGE VALIDATION & PRODUCT PRESENCE evaluation.

IMAGE VALIDATION RULES:
1. USABILITY & BRIGHTNESS:
   - If the photo is pitch black, extremely dark, or has insufficient lighting:
     status="unusable_image", reason="image_too_dark", product_detected=false.
     message="Image is too dark to analyze. Please move to a brighter area and scan the item again."
   - If the photo is completely blank, solid color, empty wall, or has no visible object:
     status="unusable_image", reason="no_visible_content", product_detected=false.
     message="No visible item detected. Please point the camera at a product and try again."
   - If the photo is heavily blurred, out of focus, or obstructed:
     status="unusable_image", reason="insufficient_visual_quality", product_detected=false.
     message="The image isn't clear enough to analyze. Please capture a sharper photo with the item fully visible."

2. HUMAN DETECTION:
   - If the photo primarily contains a person, face, selfie, body, hands, or outfit without an obvious product being inspected:
     status="not_product", reason="human_detected", product_detected=false.
     message="Please scan an item such as a handbag, watch, shoe, wallet, sunglasses, or other supported product."
     DO NOT guess or invent a product or brand for a human.

3. IRRELEVANT OBJECTS:
   - Food, drinks, furniture, walls, floors, animals, vehicles, landscapes, random electronics (monitor, keyboard, cable), household clutter:
     status="not_product", reason="unsupported_object", product_detected=false.
     message="No supported item detected. Please scan a supported product."

4. PARTIAL / INSUFFICIENT EVIDENCE:
   - A product is present but heavily cropped, mostly hidden, or too distant to identify:
     status="insufficient_evidence", reason="partial_product_insufficient_evidence", product_detected=false.
     message="There isn't enough visible detail to reliably determine the item. Please capture a clearer full-view photo."

5. VALID SUPPORTED PRODUCT:
   - A handbag, watch (analog or smart), sneaker, shoe, clothing, wallet, belt, jewelry, sunglasses, eyeglasses/optical frames, or other accessory is clearly visible:
     status="product_detected", reason="valid_luxury_product", product_detected=true.
   - category_code: exactly one of WATCH, HANDBAG, SNEAKER, SHOE, CLOTHING, WALLET, ACCESSORY, SUNGLASSES, EYEGLASSES, OTHER.
     Sunglasses = tinted/mirrored lenses. Eyeglasses = clear or prescription lenses, or optical frames.
   - product_category: a short human label ("Watches", "Bags", "Sneakers", "Shoes", "Clothing", "Wallets", "Sunglasses", "Eyeglasses", "Accessories").
   - brand ONLY if a logo or unmistakable design is visible; otherwise "not_identifiable".
   - product_name, model, variant (generation/colourway/size) ONLY if clearly recognizable. If the exact model cannot be confirmed, set model=null and say so in message. NEVER invent a model, reference number, SKU or generation.
   - Classify by OBJECT TYPE, not by how expensive or genuine it looks. Many scanned items are replicas or plain-looking; that is exactly what the user is checking. A watch is a WATCH even if the brand is unclear.
   - confidence: realistic 0.0 to 0.99, for the identification only (not authenticity).

CRITICAL INVARIANTS:
- If product_detected is false: brand, model, product_name, product_category and category_code MUST be null.
- NEVER output "Unknown Luxury Item".

OUTPUT RFC-8259 JSON ONLY:
{
  "status": "product_detected | not_product | unusable_image | insufficient_evidence",
  "reason": "human_detected | unsupported_object | image_too_dark | no_visible_content | insufficient_visual_quality | partial_product_insufficient_evidence | valid_luxury_product",
  "product_detected": true,
  "category_code": "WATCH",
  "product_category": "Category label or null",
  "brand": "Brand or null",
  "product_name": "Product name or null",
  "model": "Model or null",
  "variant": "Generation / colourway / size or null",
  "confidence": 0.92,
  "visible_details": ["feature 1", "feature 2"],
  "missing_evidence": ["missing angle"],
  "message": "User-facing summary"
}''';

  static Map<String, dynamic> get identificationSchema => {
        'type': 'OBJECT',
        'properties': {
          'status': _enum(['product_detected', 'not_product', 'unusable_image', 'insufficient_evidence']),
          'reason': _enum([
            'human_detected', 'unsupported_object', 'image_too_dark', 'no_visible_content',
            'insufficient_visual_quality', 'partial_product_insufficient_evidence', 'valid_luxury_product',
          ]),
          'product_detected': {'type': 'BOOLEAN'},
          'category_code': {..._enum(categoryCodes), 'nullable': true},
          'product_category': {'type': 'STRING', 'nullable': true},
          'brand': {'type': 'STRING', 'nullable': true},
          'product_name': {'type': 'STRING', 'nullable': true},
          'model': {'type': 'STRING', 'nullable': true},
          'variant': {'type': 'STRING', 'nullable': true},
          'confidence': {'type': 'NUMBER'},
          'visible_details': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
          'missing_evidence': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
          'message': {'type': 'STRING'},
        },
        'required': ['status', 'reason', 'product_detected', 'confidence', 'message'],
        'propertyOrdering': [
          'status', 'reason', 'product_detected', 'category_code', 'product_category', 'brand',
          'product_name', 'model', 'variant', 'confidence', 'visible_details', 'missing_evidence', 'message',
        ],
      };

  // =====================================================================
  // 2. Multi-image forensic analysis (final pass)
  // =====================================================================

  static String forensicAnalysisPrompt({
    required Product product,
    required AuthenticationRuleSet rules,
    required String imageManifest,
    required String missingNote,
    required bool overviewOnly,
    ProductReference? reference,
  }) {
    final item = '${product.brand} ${product.name}${product.model.isNotEmpty ? ' (${product.model})' : ''}';
    final referenceNotes = StringBuffer();
    if (reference != null) {
      referenceNotes.writeln('DOCUMENTED CHECKPOINTS for ${reference.brand} ${reference.model} (use only if you confirm this is that model):');
      for (final f in reference.features) {
        referenceNotes.writeln('- ${f.title}: ${f.expectedDetail}');
      }
      referenceNotes.writeln('Documented replica tells:');
      for (final flaw in reference.commonReplicaFlaws) {
        referenceNotes.writeln('- $flaw');
      }
    }

    return '''You are the evidence-extraction stage of a product authentication system (prompt v${AuthenticityEngineConfig.promptVersion}).
You do NOT decide whether the item is real or fake. You extract structured, verifiable evidence; the application applies the decision rules.

All attached images show ONE physical item. Initial identification from the first photo: $item.
Inspection profile: ${rules.profileName}.

$imageManifest
Requested photos NOT supplied:
$missingNote
${overviewOnly ? '\nNOTE: none of the requested photos were supplied. Report only what the single overview photo shows; list every requested photo under missing_evidence.\n' : ''}
WORK THROUGH THESE STEPS IN ORDER:
STEP 1  Category: confirm category (${categoryCodes.join(', ')}).
STEP 2  Brand: confirm from a visible logo or unmistakable design only.
STEP 3  Model/family/variant/generation: identify ONLY if the photos support it. If not confirmable, set model=null and model_confirmed=false. Never invent a model, SKU, reference, serial, production year, factory or material.
STEP 4  Image quality: score 0-100 for how well these photos let a human inspect authentication details; list issues.
STEP 5  Observable features: for each photo, describe what is physically visible.
STEP 6  Authenticity indicators: visible details that MATCH the identified product.
STEP 7  Counterfeit indicators: visible details that CONFLICT with the identified product.
STEP 8  Missing evidence: details that matter for this product but are not visible in any photo, with the photo that would show them.
STEP 9  Contradiction check (answer honestly before classifying):
        - Is each counterfeit indicator actually visible in the image, not inferred?
        - Is it specific to this product/model, or only a generic "luxury goods" assumption?
        - Could lighting, angle, reflection, wear, lens distortion or compression explain it?
        - Is the model identification reliable enough to compare against?
        - Would another photo resolve the question?
STEP 10 Sufficiency: decide whether the evidence is sufficient to classify at all.
STEP 11 Advisory classification (the application makes the final decision):
        LIKELY_REPLICA only if multiple independent, visible, model-specific counterfeit indicators exist and the contradiction check does not explain them away.
        LIKELY_AUTHENTIC only if multiple independent authenticity indicators are visible and nothing meaningful contradicts them.
        Otherwise INCONCLUSIVE.
STEP 12 Recommended views: the most useful next photos, as short instructions to a normal person.

FINDING RULES:
- type is exactly one of: AUTHENTIC_INDICATOR, COUNTERFEIT_INDICATOR, MISSING, AMBIGUOUS, UNVERIFIABLE.
- A detail you cannot see is MISSING, never COUNTERFEIT_INDICATOR. "Serial not visible" is MISSING. "No box shown" is MISSING.
- A detail you can see but that could be explained by photo conditions or wear is AMBIGUOUS.
- Things no photo can prove (weight, internal parts, whether a serial is registered with the brand) are UNVERIFIABLE.
- strength: WEAK = subtle, could be the photo; MODERATE = clear but not decisive on its own; STRONG = clear, specific to this model, and not explainable by photo conditions.
- A STRONG counterfeit indicator requires model_specific=true and must name the exact expected vs observed difference.
- Always fill alternative_explanation for COUNTERFEIT_INDICATOR findings (use null only if none is plausible).
- Every finding must reference the evidence_id of the photo it came from, and must say WHY. Never write "looks fake" or "looks real".
- Visible serial or model numbers go in observed_text exactly as read. Do NOT claim they are valid, registered or verified with the brand.

INSPECTION FRAMEWORK for ${rules.profileName}:
${rules.inspectionBriefing}

CAUTIONS for this category:
${rules.cautions.map((c) => '- $c').join('\n')}

${referenceNotes.isEmpty ? '' : referenceNotes.toString()}
Treat all images as the same item and compare them against each other. Report a conflict between photos (a reference on one image disagreeing with another, mismatched finish, a different variant) under contradictions.

OUTPUT RFC-8259 JSON ONLY, matching this shape:
{"identification":{"category":"WATCH","brand":null,"model":null,"variant":null,"model_confidence":0,"model_confirmed":false},
"image_quality":{"score":0,"issues":["NONE"]},
"evidence_observations":[{"evidence_id":"","title":"","visible_quality":0,"observations":[""],
  "findings":[{"feature":"","dimension":"LOGO","type":"AUTHENTIC_INDICATOR","strength":"MODERATE","observation":"","model_specific":false,"alternative_explanation":null}]}],
"contradictions":[{"description":"","involved_parts":[""],"severity":"minor|moderate|critical"}],
"missing_evidence":[{"feature":"","reason":"","recommended_view":""}],
"observed_text":[""],
"contradiction_check":{"counterfeit_evidence_is_visible":false,"counterfeit_evidence_is_model_specific":false,"could_be_explained_by_lighting_angle_wear_or_compression":false,"model_identification_reliable":true,"more_photos_required":false},
"evidence_sufficient":false,
"model_classification":"INCONCLUSIVE",
"recommended_views":[""],
"physical_checks":[{"title":"","description":"","what_to_look_for":""}],
"reasoning":""}''';
  }

  static Map<String, dynamic> get forensicAnalysisSchema {
    final finding = {
      'type': 'OBJECT',
      'properties': {
        'feature': {'type': 'STRING'},
        'dimension': _enum(dimensions),
        'type': _enum(findingTypes),
        'strength': _enum(strengths),
        'observation': {'type': 'STRING'},
        'model_specific': {'type': 'BOOLEAN'},
        'alternative_explanation': {'type': 'STRING', 'nullable': true},
      },
      'required': ['feature', 'dimension', 'type', 'strength', 'observation', 'model_specific'],
      'propertyOrdering': [
        'feature', 'dimension', 'type', 'strength', 'observation', 'model_specific', 'alternative_explanation',
      ],
    };
    return {
      'type': 'OBJECT',
      'properties': {
        'identification': {
          'type': 'OBJECT',
          'properties': {
            'category': _enum(categoryCodes),
            'brand': {'type': 'STRING', 'nullable': true},
            'model': {'type': 'STRING', 'nullable': true},
            'variant': {'type': 'STRING', 'nullable': true},
            'model_confidence': {'type': 'INTEGER'},
            'model_confirmed': {'type': 'BOOLEAN'},
          },
          'required': ['category', 'model_confidence', 'model_confirmed'],
          'propertyOrdering': ['category', 'brand', 'model', 'variant', 'model_confidence', 'model_confirmed'],
        },
        'image_quality': {
          'type': 'OBJECT',
          'properties': {
            'score': {'type': 'INTEGER'},
            'issues': {'type': 'ARRAY', 'items': _enum(qualityIssues)},
          },
          'required': ['score', 'issues'],
        },
        'evidence_observations': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'evidence_id': {'type': 'STRING'},
              'title': {'type': 'STRING'},
              'visible_quality': {'type': 'INTEGER'},
              'observations': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
              'findings': {'type': 'ARRAY', 'items': finding},
            },
            'required': ['evidence_id', 'title', 'visible_quality', 'observations', 'findings'],
            'propertyOrdering': ['evidence_id', 'title', 'visible_quality', 'observations', 'findings'],
          },
        },
        'contradictions': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'description': {'type': 'STRING'},
              'involved_parts': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
              'severity': _enum(['minor', 'moderate', 'critical']),
            },
            'required': ['description', 'severity'],
          },
        },
        'missing_evidence': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'feature': {'type': 'STRING'},
              'reason': {'type': 'STRING'},
              'recommended_view': {'type': 'STRING'},
            },
            'required': ['feature', 'reason'],
          },
        },
        'observed_text': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
        'contradiction_check': {
          'type': 'OBJECT',
          'properties': {
            'counterfeit_evidence_is_visible': {'type': 'BOOLEAN'},
            'counterfeit_evidence_is_model_specific': {'type': 'BOOLEAN'},
            'could_be_explained_by_lighting_angle_wear_or_compression': {'type': 'BOOLEAN'},
            'model_identification_reliable': {'type': 'BOOLEAN'},
            'more_photos_required': {'type': 'BOOLEAN'},
          },
          'required': [
            'counterfeit_evidence_is_visible', 'counterfeit_evidence_is_model_specific',
            'could_be_explained_by_lighting_angle_wear_or_compression', 'model_identification_reliable',
            'more_photos_required',
          ],
        },
        'evidence_sufficient': {'type': 'BOOLEAN'},
        'model_classification': _enum(['LIKELY_AUTHENTIC', 'LIKELY_REPLICA', 'INCONCLUSIVE']),
        'recommended_views': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
        'physical_checks': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'title': {'type': 'STRING'},
              'description': {'type': 'STRING'},
              'what_to_look_for': {'type': 'STRING'},
            },
            'required': ['title', 'description', 'what_to_look_for'],
          },
        },
        'reasoning': {'type': 'STRING'},
      },
      'required': [
        'identification', 'image_quality', 'evidence_observations', 'contradictions', 'missing_evidence',
        'observed_text', 'contradiction_check', 'evidence_sufficient', 'model_classification',
        'recommended_views', 'physical_checks', 'reasoning',
      ],
      // Evidence first, advisory classification last: the model commits to
      // its findings before it is asked for any conclusion.
      'propertyOrdering': [
        'identification', 'image_quality', 'evidence_observations', 'contradictions', 'missing_evidence',
        'observed_text', 'contradiction_check', 'evidence_sufficient', 'model_classification',
        'recommended_views', 'physical_checks', 'reasoning',
      ],
    };
  }

  // =====================================================================
  // 3. Counterfeit verification (second pass, only before LIKELY_REPLICA)
  // =====================================================================

  static String verificationPrompt({
    required Product product,
    required List<EvidenceFinding> counterfeitFindings,
    required String imageManifest,
    required AuthenticationRuleSet rules,
  }) {
    final list = StringBuffer();
    for (var i = 0; i < counterfeitFindings.length; i++) {
      final f = counterfeitFindings[i];
      list.writeln('F$i [photo ${f.evidenceId}] ${f.feature}: ${f.observation} (claimed ${f.strength.code})');
    }
    return '''You are the independent verification stage of a product authentication system (prompt v${AuthenticityEngineConfig.promptVersion}).
A previous pass flagged the counterfeit indicators below on this item: ${product.brand} ${product.name} (${rules.profileName}).
Your job is to CHALLENGE them. A false "replica" result on a genuine item is very harmful to its owner.

$imageManifest
FLAGGED INDICATORS:
$list
For EACH indicator, look at the referenced photo again and answer:
1. Is the exact detail actually visible in the image (not inferred from something missing)?
2. Is it specific to this product/model, rather than a generic assumption about luxury goods?
3. Could lighting, angle, reflection, glare, wear, lens distortion or image compression explain it?
4. Is there another plausible explanation for a genuine item?

outcome is exactly one of:
- CONFIRMED: clearly visible, model-specific, and not explained by conditions.
- NOT_VISIBLE: the detail isn't actually visible or readable.
- EXPLAINED_BY_CONDITIONS: photo conditions or wear plausibly explain it.
- NOT_MODEL_SPECIFIC: a generic assumption, not a known fact about this model.
Only keep strength STRONG for CONFIRMED indicators that name an exact expected-vs-observed difference.

CAUTIONS:
${rules.cautions.map((c) => '- $c').join('\n')}

OUTPUT RFC-8259 JSON ONLY:
{"verifications":[{"finding_index":0,"outcome":"CONFIRMED","verified_strength":"STRONG","reason":""}],"sufficient_evidence_for_counterfeit":false,"additional_photo_needed":""}''';
  }

  static Map<String, dynamic> get verificationSchema => {
        'type': 'OBJECT',
        'properties': {
          'verifications': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'finding_index': {'type': 'INTEGER'},
                'outcome': _enum(['CONFIRMED', 'NOT_VISIBLE', 'EXPLAINED_BY_CONDITIONS', 'NOT_MODEL_SPECIFIC']),
                'verified_strength': _enum(strengths),
                'reason': {'type': 'STRING'},
              },
              'required': ['finding_index', 'outcome', 'verified_strength', 'reason'],
              'propertyOrdering': ['finding_index', 'outcome', 'verified_strength', 'reason'],
            },
          },
          'sufficient_evidence_for_counterfeit': {'type': 'BOOLEAN'},
          'additional_photo_needed': {'type': 'STRING'},
        },
        'required': ['verifications', 'sufficient_evidence_for_counterfeit'],
        'propertyOrdering': ['verifications', 'sufficient_evidence_for_counterfeit', 'additional_photo_needed'],
      };

  static Map<String, dynamic> _enum(List<String> values) => {'type': 'STRING', 'enum': values};
}
