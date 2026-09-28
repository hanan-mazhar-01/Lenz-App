import 'dart:convert';

import '../core/config/authenticity_engine_config.dart';
import '../data/evidence_profiles.dart';
import '../models/evidence_record.dart';
import '../models/product_reference.dart';
import '../models/product_identity.dart';

/// The five instructions used by the scan pipeline, each with its own
/// response schema, under one version ([AuthenticityEngineConfig.promptVersion]):
///
/// 1. [identificationPrompt]     product recognition (first photo)
/// 2. [recommendationPrompt]     evidence recommendation (text only)
/// 3. [photoCheckPrompt]         image-quality and part check (per photo)
/// 4. [photoAnalysisPrompt]      product-specific visual analysis (per photo)
/// 5. [finalEvaluationPrompt]    final evidence evaluation (text only)
///
/// The model reports observations; the app's decision engine decides. No
/// prompt asks for a numeric authenticity confidence, and none may claim
/// manufacturer verification.
///
/// Schemas use Gemini's `responseSchema` subset (type, properties, required,
/// enum, items, nullable, propertyOrdering). The Cloud Function forwards them
/// as `generationConfig.responseSchema`.
abstract final class AuthenticityPrompts {
  /// The categories the app supports (the same as before engine v3).
  static const categoryCodes = [
    'WATCH', 'HANDBAG', 'SNEAKER', 'SHOE', 'CLOTHING', 'WALLET', 'ACCESSORY',
    'SUNGLASSES', 'EYEGLASSES',
  ];

  static const attributeStatuses = ['CONFIRMED', 'PROBABLE', 'UNKNOWN'];

  /// Where a photo comes from. Only a photo of the item itself (or, for
  /// device-information requests, a screenshot of that information) is used.
  static const imageSources = ['PHYSICAL_ITEM', 'DEVICE_SCREENSHOT', 'SCREEN_OR_PRINT', 'INTERNET_IMAGE'];
  static const identitySources = ['MARKING', 'DESIGN', 'DEVICE_REPORTED', 'NONE'];
  static const outcomes = ['CONSISTENT', 'INCONSISTENT', 'NOT_VISIBLE', 'UNCLEAR'];
  static const reliabilities = ['HIGH', 'MEDIUM', 'LOW'];
  static const bases = ['REFERENCE_PROVIDED', 'MODEL_KNOWLEDGE', 'GENERAL_PRINCIPLE', 'DEVICE_REPORTED'];
  static const evidenceKinds = ['OBSERVED_FACT', 'AI_INTERPRETATION', 'DEVICE_REPORTED'];
  static const readability = ['READABLE', 'PARTLY_READABLE', 'NOT_READABLE', 'NA'];
  static const photoIssues = [
    'BLUR', 'OUT_OF_FOCUS', 'MOTION_BLUR', 'GLARE', 'TOO_DARK', 'OVEREXPOSED', 'TOO_FAR', 'OCCLUSION',
    'PARTIAL', 'POOR_ANGLE', 'TEXT_UNREADABLE', 'NONE',
  ];

  // =====================================================================
  // 1. Product recognition
  // =====================================================================

  static final String identificationPrompt = '''You identify products for an authentication app (prompt v${AuthenticityEngineConfig.promptVersion}).
You do NOT judge authenticity here. First validate the photo, then identify the product, stating how certain each attribute is.

PHOTO VALIDATION (set status/reason and stop identifying when one applies):
0. NOT A REAL PHOTO OF THE ITEM: a photo of a computer, phone or TV screen showing a picture of the product (screen edges, pixels or moire, a browser or app interface around it), a printed picture (magazine, poster, box art), or an image from the internet (official product render or marketing photo, store listing, stock photo, watermarks or text overlays, perfect studio render): image_source="SCREEN_OR_PRINT" or "INTERNET_IMAGE", status="unusable_image", reason="not_real_photo", message="This looks like a picture from the internet or a screen, not the item itself. Please take a photo of the actual item with the camera." The item's own display (a watch face, the watch's settings screen) is part of the item: that is image_source="PHYSICAL_ITEM". An ordinary photo the user took of the item, even on a plain background, is PHYSICAL_ITEM.
1. Pitch black or far too dark: status="unusable_image", reason="image_too_dark".
2. Blank, solid colour, empty wall, no visible object: status="unusable_image", reason="no_visible_content".
3. So blurred, obstructed or out of focus that the object type cannot be told: status="unusable_image", reason="insufficient_visual_quality".
4. Mainly a person, face, body or outfit with no product being shown: status="not_product", reason="human_detected". Never invent a product for a person.
5. NOT A SUPPORTED CATEGORY: food, drinks, furniture, animals, vehicles, landscapes, household items and clutter, perfume and fragrance bottles, cosmetics, makeup and skincare, phones, earbuds, headphones, laptops, monitors, keyboards, cables and any electronics other than watches, toys, stationery, bottles and containers: status="not_product", reason="unsupported_object", message="No supported item detected. Please scan a watch, bag, shoe, clothing, wallet, eyewear or accessory."
6. GENERIC / LOCAL UNBRANDED ITEM: a supported kind of object that clearly carries no brand identity at all: no logo, brand name, monogram or signature design of any known brand, and it does not imitate one (for example a plain unbranded bag, shoe, shirt or watch from a local market): status="not_product", reason="unsupported_object", message="This looks like a generic, unbranded item. Lenz checks branded products, for example watches, bags, sneakers and eyewear from known brands." Use this ONLY when enough of the item is visible to be sure there is no branding. If the brand is simply not visible from this angle, or the item imitates a known brand (a replica), identify it normally.
7. A product is present but mostly hidden or too far to tell what kind of object it is: status="insufficient_evidence", reason="partial_product_insufficient_evidence".
For 0-7: product_detected=false and every identification field null. Always set image_source.

SUPPORTED PRODUCTS (only these): watches (analogue and smart), handbags, sneakers, shoes, clothing, wallets, belts, jewellery and other fashion accessories (scarves, caps, ties), sunglasses, eyeglasses.
Classify by OBJECT TYPE, not by how expensive or genuine it looks. Many scanned items are replicas or plain-looking; that is exactly what the user is checking. A branded or brand-imitating watch is a WATCH even when it looks cheap or worn.
status="product_detected", reason="valid_luxury_product", product_detected=true, and:
- category_code: exactly one of ${categoryCodes.join(', ')}. SUNGLASSES = tinted or mirrored lenses; EYEGLASSES = clear lenses or optical frames.
- product_category: short human label ("Watches", "Bags", "Sneakers", "Shoes", "Clothing", "Wallets", "Sunglasses", "Eyeglasses", "Accessories").
- product_type: a short noun for what the object is, e.g. "smartwatch", "mechanical watch", "sneaker", "loafer", "tote bag", "belt".
- confidence: 0.0-0.99, how sure you are of the OBJECT CATEGORY only (not brand, model or authenticity).

IDENTITY, each with a status:
- CONFIRMED: established by readable text or a marking in this photo, the device's own information screen, or a design feature that exists on this model only.
- PROBABLE: the design strongly suggests it, but another model or generation could look alike.
- UNKNOWN: not established. Use null for the value.
Fields: brand, model (the model family, e.g. "Apple Watch Ultra", "Submariner", "Air Jordan 4", "Neverfull"), generation (e.g. "Ultra 2", "Series 9", or a range such as "Series 7-9" with PROBABLE), exact_model (a reference, model number or style code, ONLY if readable in the photo). Give a short *_basis for each: the visible feature that established it.
NEVER invent a model number, reference, SKU, serial, generation or production year. If the generation cannot be told, say so with status UNKNOWN. Copied designs look like the model they copy: design alone is at most PROBABLE unless a feature is exclusive to one model.
List uncertain_attributes explicitly (e.g. "generation", "case size", "exact colourway").
visible_part: which part of the product this photo shows (e.g. "front display", "back with sensor", "side with crown", "whole shoe from the side", "interior label").
item_box_2d: [ymin, xmin, ymax, xmax] of the product in the photo, each 0-1000.
visible_characteristics: manufacturing characteristics visible (materials, finishes, construction).
distinguishing_features: visible features that could help authenticate this exact model.

OUTPUT RFC-8259 JSON ONLY matching the schema.''';

  static Map<String, dynamic> get identificationSchema {
    Map<String, dynamic> str() => {'type': 'STRING', 'nullable': true};
    return {
      'type': 'OBJECT',
      'properties': {
        'status': _enum(['product_detected', 'not_product', 'unusable_image', 'insufficient_evidence']),
        'reason': _enum([
          'human_detected', 'unsupported_object', 'image_too_dark', 'no_visible_content',
          'insufficient_visual_quality', 'partial_product_insufficient_evidence', 'valid_luxury_product', 'not_real_photo',
        ]),
        'image_source': _enum(imageSources),
        'product_detected': {'type': 'BOOLEAN'},
        'category_code': {..._enum(categoryCodes), 'nullable': true},
        'product_category': str(),
        'product_type': str(),
        'confidence': {'type': 'NUMBER'},
        'brand': str(),
        'brand_status': _enum(attributeStatuses),
        'brand_basis': str(),
        'product_name': str(),
        'model': str(),
        'model_status': _enum(attributeStatuses),
        'model_basis': str(),
        'generation': str(),
        'generation_status': _enum(attributeStatuses),
        'generation_basis': str(),
        'exact_model': str(),
        'exact_model_status': _enum(attributeStatuses),
        'variant': str(),
        'visible_part': str(),
        'item_box_2d': {'type': 'ARRAY', 'items': {'type': 'NUMBER'}, 'nullable': true},
        'visible_characteristics': _strings(),
        'distinguishing_features': _strings(),
        'uncertain_attributes': _strings(),
        'missing_evidence': _strings(),
        'message': {'type': 'STRING'},
      },
      'required': ['image_source', 'status', 'reason', 'product_detected', 'confidence', 'message'],
      'propertyOrdering': [
        'image_source', 'status', 'reason', 'product_detected', 'category_code', 'product_category', 'product_type', 'confidence',
        'brand', 'brand_status', 'brand_basis', 'product_name', 'model', 'model_status', 'model_basis',
        'generation', 'generation_status', 'generation_basis', 'exact_model', 'exact_model_status', 'variant',
        'visible_part', 'item_box_2d', 'visible_characteristics', 'distinguishing_features',
        'uncertain_attributes', 'missing_evidence', 'message',
      ],
    };
  }

  // =====================================================================
  // 2. Evidence recommendation (text only)
  // =====================================================================

  static String recommendationPrompt({
    required ResolvedProfile profile,
    required Set<String> coveredRequestIds,
  }) {
    final id = profile.identity;
    final requests = StringBuffer();
    for (final r in profile.profile.requests) {
      final cps = profile.checkpointsFor(r.id).map((c) => c.name).join('; ');
      requests.writeln('- ${r.id}: ${r.title}. Shows: $cps.${coveredRequestIds.contains(r.id) ? ' (ALREADY PHOTOGRAPHED)' : ''}');
    }
    return '''You plan which photos an authentication app should ask for next (prompt v${AuthenticityEngineConfig.promptVersion}).
Product: ${_identityText(id)}.
Evidence profile: ${profile.profile.name}.
${_generationText(profile)}
CANDIDATE PHOTOS (use only these ids):
$requests
Rank EVERY candidate photo by how well it separates a genuine example of THIS EXACT MODEL from its known counterfeits:
- discriminative_value HIGH: a feature documented to differ between genuine items of this model and common counterfeits, and hard to copy.
- MEDIUM: helpful but copied reasonably well by good counterfeits.
- LOW: mostly copied design, packaging, or not very informative for this model.
- photo_assessable: false when the feature cannot be judged reliably from an ordinary phone photo.
- model_specific_checks: up to 3 short, concrete things to look for in that photo on this exact model, ONLY if you know them for this model. Leave empty rather than guessing. Never state measurements.
- reason: one short sentence.
If the model or generation is not established, favour photos that establish it (labels, device information, model markings).
Photos already taken still get a rank, but they will not be requested again.
model_notes: at most 3 short cautions about legitimate variations of this model (generations, regional versions, editions) that must not be mistaken for counterfeit signs.
Your knowledge is labelled "AI model knowledge, not independently verified" in the app. Do not present guesses as facts.
OUTPUT RFC-8259 JSON ONLY matching the schema.''';
  }

  static Map<String, dynamic> recommendationSchema(ResolvedProfile profile) => {
        'type': 'OBJECT',
        'properties': {
          'ranked': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'request_id': _enum([for (final r in profile.profile.requests) r.id]),
                'discriminative_value': _enum(['HIGH', 'MEDIUM', 'LOW']),
                'photo_assessable': {'type': 'BOOLEAN'},
                'model_specific_checks': _strings(),
                'reason': {'type': 'STRING'},
              },
              'required': ['request_id', 'discriminative_value', 'photo_assessable', 'reason'],
              'propertyOrdering': ['request_id', 'discriminative_value', 'photo_assessable', 'model_specific_checks', 'reason'],
            },
          },
          'model_notes': _strings(),
        },
        'required': ['ranked'],
        'propertyOrdering': ['ranked', 'model_notes'],
      };

  // =====================================================================
  // 3. Image-quality and part check (per photo)
  // =====================================================================

  static String photoCheckPrompt({
    required ResolvedProfile profile,
    required PhotoRequestTemplate? requested,
    required List<String> localIssues,
    String? originHint,
  }) {
    final parts = StringBuffer();
    for (final r in profile.profile.requests) {
      parts.writeln('- ${r.id}: ${r.title}');
    }
    final asked = requested == null
        ? 'The user added this photo without a specific request.'
        : 'The user was asked for: "${requested.title}". Instruction given: "${requested.instruction}"';
    return '''You check one photo for an authentication app before it is analysed (prompt v${AuthenticityEngineConfig.promptVersion}).
Product: ${_identityText(profile.identity)}.
$asked

PARTS THE APP CAN USE (ids):
$parts
${originHint == null ? '' : 'IMAGE FILE (a hint only; decide image_source from what you see): $originHint\n'}0. image_source: PHYSICAL_ITEM when the photo shows the item itself in front of the camera (its own display, e.g. a watch face or its settings screen, is part of the item); DEVICE_SCREENSHOT for a screenshot of the item's information (e.g. the paired phone's app); SCREEN_OR_PRINT for a photo of a computer, phone or TV screen or of a printed picture showing the product (screen edges, pixels or moire, a browser or app around it); INTERNET_IMAGE for an image from the internet: official render or marketing photo, store listing, stock or professional studio photo (seamless backdrop, studio lighting, no hand, table or room, flawless surfaces), watermarks, labels, codes or coloured shapes laid over the picture. An ordinary photo the user took, even on a plain background, is PHYSICAL_ITEM.
1. part_shown: which part of the product is actually visible, in a few words (e.g. "front of the watch", "side with the crown", "a person's hand", "a table").
2. shows_product: false if the photo shows something other than this product.
3. shows_requested_part: ${requested == null ? 'true if the photo clearly shows one of the listed parts.' : 'true ONLY if "${requested.title}" is clearly visible and large enough to inspect. A good photo of a DIFFERENT part, the whole item from too far away, a blurred or covered view of the part, or an unrelated object is false. Be strict: the app asks again when this is false.'}
4. requested_part_confidence: 0-100, how clearly ${requested == null ? 'that part' : '"${requested.title}"'} is shown. Under 20 when it is not shown at all.
5. matched_request_id: the id of the listed part this photo actually shows, so the app can tell the user what they photographed. "none" if it shows no listed part.
6. detail_box_2d: [ymin, xmin, ymax, xmax] (0-1000) tightly around the key detail of the part shown (e.g. the sensor and the engraving around it, the label, the crown, the tread). The app measures focus and glare inside this region.
7. detail_readability: can the fine detail of that part (text, engraving, stitching, sensor lenses) actually be read? READABLE, PARTLY_READABLE, NOT_READABLE, or NA if the part has no fine detail.
8. issues: photo problems that limit inspection. ${localIssues.isEmpty ? '' : 'On-device checks measured: ${localIssues.join(', ')}; confirm or dismiss them from what you see.'}
9. usable: false if the photo cannot be used to inspect ${requested == null ? 'the part' : '"${requested.title}"'} (wrong part, not this product, or the part cannot be inspected). Small differences in framing or angle are fine when the part is clearly visible.
10. fix: ONE concrete sentence telling the user exactly what to do. If the wrong part was photographed, say which part to photograph instead. If the part is right but hard to see, say what to change (e.g. "Move closer so the engraving fills the frame.", "Tilt the watch slightly to remove the reflection on the sensor."). Empty if nothing needs fixing.
11. quality_score: 0-100 for how well this photo lets a person inspect the part shown.
12. reason: one short everyday sentence about the photo.
Never use words like entropy, segmentation, artefact or feature extraction.
OUTPUT RFC-8259 JSON ONLY matching the schema.''';
  }

  static Map<String, dynamic> photoCheckSchema(ResolvedProfile profile) => {
        'type': 'OBJECT',
        'properties': {
          'image_source': _enum(imageSources),
          'part_shown': {'type': 'STRING'},
          'shows_product': {'type': 'BOOLEAN'},
          'shows_requested_part': {'type': 'BOOLEAN'},
          'requested_part_confidence': {'type': 'INTEGER'},
          'matched_request_id': _enum([for (final r in profile.profile.requests) r.id, 'none']),
          'detail_box_2d': {'type': 'ARRAY', 'items': {'type': 'NUMBER'}, 'nullable': true},
          'detail_readability': _enum(readability),
          'issues': {'type': 'ARRAY', 'items': _enum(photoIssues)},
          'usable': {'type': 'BOOLEAN'},
          'fix': {'type': 'STRING'},
          'quality_score': {'type': 'INTEGER'},
          'reason': {'type': 'STRING'},
        },
        'required': [
          'image_source', 'part_shown', 'shows_product', 'shows_requested_part', 'requested_part_confidence', 'matched_request_id',
          'detail_readability', 'issues', 'usable', 'fix', 'quality_score', 'reason',
        ],
        'propertyOrdering': [
          'image_source', 'part_shown', 'shows_product', 'shows_requested_part', 'requested_part_confidence', 'matched_request_id',
          'detail_box_2d', 'detail_readability', 'issues', 'usable', 'fix', 'quality_score', 'reason',
        ],
      };

  // =====================================================================
  // 4. Product-specific visual analysis (per photo)
  // =====================================================================

  static String photoAnalysisPrompt({
    required ResolvedProfile profile,
    required String? requestId,
    required bool isInitialPhoto,
    List<String> aiChecks = const [],
  }) {
    final req = requestId == null ? null : profile.request(requestId);
    final primary = req == null ? profile.profile.checkpoints : profile.checkpointsFor(req.id);
    final primaryIds = {for (final c in primary) c.id};
    final secondary = profile.profile.checkpoints.where((c) => !primaryIds.contains(c.id)).toList();
    final generationKnown = profile.identity.generation.isKnown;

    final buf = StringBuffer();
    for (final c in primary) {
      buf.writeln('- ${c.id} | ${c.name}: ${c.check}');
      if (c.genuine != null) buf.writeln('    documented on genuine: ${c.genuine}');
      if (c.replicaTell != null) buf.writeln('    documented replica tell: ${c.replicaTell}');
      if (c.generationSpecific) {
        buf.writeln(generationKnown
            ? '    generation-specific: compare with ${profile.identity.generation.value} only.'
            : '    generation-specific and the generation is NOT established: report UNCLEAR, never INCONSISTENT.');
      }
      if (c.variationNote != null) buf.writeln('    legitimate variation: ${c.variationNote}');
    }
    final secondaryText = secondary.map((c) => '${c.id} (${c.name})').join(', ');

    return '''You are the visual-analysis stage of an authentication app (prompt v${AuthenticityEngineConfig.promptVersion}).
You report what one photo shows about specific checkpoints. The app decides the verdict; you do not.

PRODUCT BEING EVALUATED: ${_identityText(profile.identity)}.
${_generationText(profile)}
PHOTO: ${isInitialPhoto ? 'the first photo the user took (any part of the product).' : 'requested as "${req?.title ?? 'additional photo'}".'}
The attached image is the user's photo. Look closely at small text, engravings, stitching and small parts.

PRIMARY CHECKPOINTS (report each one; NOT_VISIBLE if it is not shown):
$buf${aiChecks.isEmpty ? '' : 'Model-specific points to look at (AI suggestions, unverified): ${aiChecks.join('; ')}\n'}
SECONDARY CHECKPOINTS (report only if clearly visible in this photo): $secondaryText
Use checkpoint_id "other" only for a clearly relevant detail not covered above, with a short feature name.

FOR EACH ASSESSMENT:
- observation: ONLY what is literally visible (a fact anyone could confirm from the photo).
- interpretation: what it means compared with the genuine ${profile.evaluatedModelLabel}.
- outcome:
  CONSISTENT - the visible execution matches the genuine model.
  INCONSISTENT - a clearly visible difference from the genuine model as identified above. A feature that is ABSENT from a clearly visible area where the genuine model has it (e.g. no screws where screws belong) is INCONSISTENT.
  NOT_VISIBLE - the checkpoint is not shown in this photo. A detail you cannot see is never INCONSISTENT.
  UNCLEAR - visible but cannot be judged (photo conditions, dirt, unestablished model or generation).
- reliability: HIGH = clearly visible, sharp and unambiguous; MEDIUM = visible with some limitation; LOW = hard to see. State the limitation.
- basis: REFERENCE_PROVIDED only when comparing against the documented text given above; DEVICE_REPORTED when reading values from the device's own screen; MODEL_KNOWLEDGE for your own knowledge of this model; GENERAL_PRINCIPLE for generic manufacturing quality.
- evidence_kind: OBSERVED_FACT when the conclusion needs no interpretation (exposed pins exist, the text reads X); AI_INTERPRETATION when judging quality or comparing with the model; DEVICE_REPORTED for values shown by the device itself.
- alternative_explanation: ONLY when a benign explanation is genuinely plausible (a legitimate generation or regional variant, an aftermarket or replacement part, wear, photo conditions). Otherwise null. Do not invent one out of caution.

RULES:
${profile.profile.cautions.map((c) => '- $c').join('\n')}
- BRAND IMITATION: a marking that abbreviates, misspells or mimics a well-known brand's trademark (e.g. "MK SHOES" with an unrelated logo presented as Michael Kors) is INCONSISTENT on brand_marking with HIGH reliability when clearly readable. An independent budget brand imitating no one is not.
- Read serial and model numbers into observed_text exactly. Never claim they are valid, registered or verified.
- Never claim anything was verified with the manufacturer.
- identity_evidence: fill only when THIS photo shows model information (device screen, label, model number, case-size engraving). status CONFIRMED only for readable text; source DEVICE_REPORTED for device screens (a clone can display false values), MARKING for printed/engraved text, DESIGN otherwise.
- matched_request_id: which listed photo type this photo corresponds to.
OUTPUT RFC-8259 JSON ONLY matching the schema.''';
  }

  static Map<String, dynamic> photoAnalysisSchema(ResolvedProfile profile) {
    Map<String, dynamic> str() => {'type': 'STRING', 'nullable': true};
    return {
      'type': 'OBJECT',
      'properties': {
        'photo_summary': {'type': 'STRING'},
        'matched_request_id': _enum([for (final r in profile.profile.requests) r.id, 'none']),
        'observed_text': _strings(),
        'identity_evidence': {
          'type': 'OBJECT',
          'properties': {
            'brand': str(),
            'model_family': str(),
            'generation': str(),
            'exact_model': str(),
            'status': _enum(attributeStatuses),
            'source': _enum(identitySources),
            'basis': str(),
          },
          'required': ['status', 'source'],
          'propertyOrdering': ['brand', 'model_family', 'generation', 'exact_model', 'status', 'source', 'basis'],
        },
        'assessments': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'checkpoint_id': _enum([for (final c in profile.profile.checkpoints) c.id, 'other']),
              'feature': {'type': 'STRING'},
              'observation': {'type': 'STRING'},
              'interpretation': {'type': 'STRING'},
              'outcome': _enum(outcomes),
              'reliability': _enum(reliabilities),
              'limitation': {'type': 'STRING'},
              'basis': _enum(bases),
              'evidence_kind': _enum(evidenceKinds),
              'alternative_explanation': str(),
            },
            'required': ['checkpoint_id', 'feature', 'observation', 'interpretation', 'outcome', 'reliability', 'basis', 'evidence_kind'],
            'propertyOrdering': [
              'checkpoint_id', 'feature', 'observation', 'interpretation', 'outcome', 'reliability', 'limitation',
              'basis', 'evidence_kind', 'alternative_explanation',
            ],
          },
        },
      },
      'required': ['photo_summary', 'matched_request_id', 'observed_text', 'identity_evidence', 'assessments'],
      // Observations before any judgement.
      'propertyOrdering': ['photo_summary', 'matched_request_id', 'observed_text', 'identity_evidence', 'assessments'],
    };
  }

  // =====================================================================
  // 5. Final evidence evaluation (text only)
  // =====================================================================

  static String finalEvaluationPrompt({
    required ResolvedProfile profile,
    required List<PhotoEvidence> photos,
    required List<EvidenceRecord> mismatches,
    required List<EvidenceRecord> supporting,
    required String provisionalVerdict,
  }) {
    final photoLines = StringBuffer();
    for (final p in photos) {
      photoLines.writeln('- ${p.photoId} (${p.requestTitle}): ${p.summary}'
          '${p.observedText.isEmpty ? '' : ' | text read: ${p.observedText.join(' / ')}'}'
          '${p.modelFamily.isKnown || p.generation.isKnown || p.exactModel.isKnown ? ' | identity shown: ${[p.brand.value, p.modelFamily.value, p.generation.value, p.exactModel.value].whereType<String>().join(' ')} (${p.modelFamily.source.code.toLowerCase()})' : ''}');
    }
    final mismatchLines = StringBuffer();
    for (final r in mismatches) {
      final cp = profile.checkpoint(r.featureId);
      mismatchLines.writeln('- key "${recordKey(r)}" | ${r.featureName} | photo ${r.photoId} | seen: ${r.observation} | '
          'meaning: ${r.interpretation} | reliability ${r.reliability.code}'
          '${cp?.variationNote == null ? '' : ' | known variation: ${cp!.variationNote}'}');
    }
    final supportLines = supporting.take(8).map((r) => '- ${r.featureName} (${r.photoId}): ${r.interpretation}').join('\n');

    return '''You are the final evidence-evaluation stage of an authentication app (prompt v${AuthenticityEngineConfig.promptVersion}).
You receive structured observations already extracted from the user's photos; you do not see the photos.
Product evaluated: ${_identityText(profile.identity)}.
${_generationText(profile)}${profile.identity.conflicts.isEmpty ? '' : 'Identity disagreements noted so far: ${profile.identity.conflicts.join('; ')}\n'}
PHOTOS:
$photoLines
OBSERVATIONS THAT DIFFER FROM THE GENUINE MODEL:
${mismatchLines.isEmpty ? '(none)\n' : mismatchLines}
OBSERVATIONS CONSISTENT WITH THE GENUINE MODEL (for context only):
${supportLines.isEmpty ? '(none)' : supportLines}
The app's provisional reading is: $provisionalVerdict.

TASKS:
1. cross_photo_contradictions: do the photos contradict each other (different serial or model text, different case size or material, a device screen naming a model the physical item is not)? List only real contradictions with the photo ids. identity_related=true when it is about what the product is. severity: minor (probably a reading error), moderate, critical (cannot both be true of one genuine item).
2. variation_checks: for EVERY observation listed above as differing (use its key), decide whether a legitimate variation of the genuine product explains it: another generation or edition, a regional version, a production change, an aftermarket or replacement part (bands, straps, lenses), normal wear or repair.
   LIKELY - a specific legitimate variation clearly explains it (name it).
   POSSIBLE - a legitimate variation might explain it, but it is not specific or not typical.
   RULED_OUT - no genuine version of this product has this (e.g. exposed charging pins on an Apple Watch, a misspelled brand name).
3. identity_consistent: false if the evidence shows the item cannot be the model it is being evaluated as.
4. remaining_uncertainty: up to 3 short, plain sentences on what the photos could not establish.
5. notes: one or two sentences summarising your reasoning, for the app's log.
You may only weaken or explain differences, or report contradictions. Never add evidence of authenticity, never claim manufacturer verification, never give a numeric confidence.
OUTPUT RFC-8259 JSON ONLY matching the schema.''';
  }

  static String recordKey(EvidenceRecord r) => '${r.photoId}|${r.featureId}';

  // ===========================================================================
  // 6. Final combined analysis (engine v4): all photos together, Gemini's own
  //    knowledge plus the app checklist. No web search or external research.
  // ===========================================================================

  static const combinedComparisons = ['MATCHES', 'CONFLICTS', 'UNCLEAR', 'NOT_VISIBLE'];
  static const combinedVisibility = ['CLEAR', 'PARTIAL', 'OBSCURED'];
  static const combinedBasis = ['CHECKLIST_ITEM', 'MODEL_KNOWLEDGE', 'GENERIC_QUALITY'];
  static const combinedVariation = ['LIKELY', 'POSSIBLE', 'RULED_OUT', 'NOT_APPLICABLE'];
  static const combinedVerdicts = ['AUTHENTIC', 'REPLICA', 'NOT_SURE'];
  static const combinedDetailKinds = ['MARKING', 'MATERIAL', 'CONSTRUCTION', 'LABEL', 'SOFTWARE', 'PACKAGING', 'OTHER'];
  static const combinedKnowledgeScopes = ['THIS_GENERATION', 'MODEL_FAMILY', 'BRAND_WIDE', 'NOT_SURE'];

  /// [images]: id (P1.., C1..) and what each image is, in upload order.
  /// [earlierObservations]: per-photo observations from capture, as context.
  static String combinedAnalysisPrompt({
    required ResolvedProfile profile,
    required List<({String id, String description})> images,
    required ProductReference checklist,
    required List<String> earlierObservations,
  }) {
    final imageLines = images.map((i) => '${i.id}: ${i.description}').join('\n');
    final checklistLines = checklist.claims
        .map((c) => '${c.id} ${c.area}: ${c.detail}'
            '${c.hardToCopy ? ' (hard to copy)' : ''}${c.decisiveIfDifferent ? ' (a genuine unit never differs here)' : ''}'
            '${c.appliesTo == null ? '' : ' (applies to: ${c.appliesTo})'}')
        .join('\n');
    final earlier = earlierObservations.isEmpty ? '(none)' : earlierObservations.take(24).map((o) => '- $o').join('\n');
    final requests = [for (final r in profile.profile.requests) '${r.id} (${r.title})'].join(', ');
    final generationKnown = profile.identity.generation.isKnown;

    return """You are the final authentication stage of a product-authentication app (prompt v${AuthenticityEngineConfig.promptVersion}).
You see ALL photos the user submitted for ONE item, together. Compare them with each other and with what you know about the genuine product.
ITEM AS IDENTIFIED: ${_identityText(profile.identity)}.
IMAGES (in the order attached):
$imageLines

YOUR KNOWLEDGE: use your own knowledge of this exact product and its known counterfeits. No web search is available and none is needed. ${generationKnown ? '' : 'The generation is NOT established: do not use generation-specific details unless the images themselves establish the generation. If physical features match genuine hardware across the model family, evaluate the physical evidence while representing generation uncertainty. '}Say in knowledge_scope how specific each detail from your knowledge is, and use NOT_SURE when you are not confident it applies to this item. Your knowledge is not manufacturer verification.

APP CHECKLIST (the app's own list of parts to check; documented items are guidance, not verified manufacturer data):
${checklistLines.isEmpty ? '(none)' : checklistLines}

EARLIER PER-PHOTO OBSERVATIONS (context only; check them yourself in the images; [b#] = checklist item):
$earlier

TASKS
1. findings: one finding for every checklist item that at least one image lets you check, and for other details you know tell a genuine unit of this product from copies (claim_id "none", basis MODEL_KNOWLEDGE). Give the images that show it, what is literally visible (observed) and the comparison. Several images of the same detail belong in ONE finding.
2. Rules for findings:
   - A detail that is not photographed, hidden, blurred, covered by glare or too small to read is UNCLEAR or NOT_VISIBLE, never CONFLICTS. Missing photos are never evidence of a fake.
   - MATCHES only when you can name the concrete detail that matches (text, shape, position, material, code format). Generic quality ("neat stitching", "premium feel") is basis GENERIC_QUALITY and proves nothing either way.
   - Never apply details of a different generation, edition or variant.
   - part_request_id: the part of the item the detail is on, as one of the app's photo parts ($requests) or "other". Details on the same part (e.g. logo, sub-dials and date window on a dial) are ONE part.
   - detail_kind: MARKING for printed or engraved text and logos; MATERIAL, CONSTRUCTION, LABEL, SOFTWARE, PACKAGING or OTHER otherwise.
   - hard_to_copy: true only for details counterfeits struggle to reproduce (materials such as ceramic or sapphire, real screws, sensor lenses, stitching method, hardware finish, codes that can be cross-checked). Printed or engraved text, logos and overall shape are copied well: not hard to copy.
   - counterfeit_tell: true when copies commonly differ in this detail.
   - difference_kind (CONFLICTS only): DIFFERENT when something visibly different is there (e.g. a plastic back, printed dots instead of screws); ABSENT when a detail the genuine item has is missing from a clearly photographed area. When the brand is not established, a missing logo or missing text is not a conflict. NOT_APPLICABLE for other comparisons.
   - For every CONFLICTS, consider legitimate explanations (another generation or edition, regional version, production change, replacement part such as a band, strap or lens, wear, repair, photo conditions) and set legitimate_variation; name the explanation in alternative_explanation.
   - A device screen (settings, "About") shows what the device reports about itself; a copy can show false values. Say so in alternative_explanation when a finding relies on it. A missing device screen does not block authenticity if physical hardware evidence is sufficient.
   - A close-up (C#) is the same photo as its parent image at higher resolution; it is not independent evidence.
   - Every EARLIER observation marked "looked different" needs its own finding (use its checklist id when shown): CONFLICTS if you confirm it, otherwise what you see instead and why (e.g. settled by clearer lighting/angle).
3. cross_image_contradictions: do the images disagree with each other (different serial or model text, sizes, materials, or apparently different items)? Only real contradictions.
4. identity_established: what the images show the item is; consistent_with_identification=false if it cannot be the identified model.
5. proposed_verdict:
   AUTHENTIC when the visual evidence across the submitted photographs is consistent with genuine product specifications for the identified model, showing characteristic construction, materials, and markings with no unresolved material counterfeit discrepancies. Evaluate the holistic diagnostic value of the photos provided (including 2–3 clear, informative photographs) without requiring an arbitrary photo count or missing software screenshot.
   REPLICA when there is a reliable, clearly visible discrepancy or counterfeit tell that conflicts with genuine specifications and cannot reasonably be explained by normal wear, lighting, photo angle or legitimate product variations.
   NOT_SURE when the photographs cannot reliably distinguish genuine from counterfeit, the exact model is uncertain, critical diagnostic areas are ambiguous or missing, or the visual evidence is inconclusive. Do not force a definitive answer when evidence is insufficient. This is a visual assessment, not a manufacturer verification. Never give a numeric confidence.
6. verdict_reasoning: clear, detailed explanation of what model was identified, visible details supporting or contradicting, why this verdict was reached, and limitations. Describe actual visual characteristics rather than generic statements.
7. summary_points: 2 to 3 short, concise bullet points (under 15 words each) clearly summarizing the core reasons for this verdict to display in the quick summary card.
8. unresolved: what prevents a definitive answer, each with the photo request that would resolve it (one of the photo parts above, or "none") and, if useful, a check outside the app.
9. independent_verification: at most two short suggestions for checks outside the app (for example the manufacturer's serial-number lookup), only when relevant.
OUTPUT RFC-8259 JSON ONLY matching the schema.""";
  }

  static Map<String, dynamic> combinedAnalysisSchema({
    required List<String> imageIds,
    required List<String> claimIds,
    required List<String> requestIds,
  }) =>
      {
        'type': 'OBJECT',
        'properties': {
          'identity_established': {
            'type': 'OBJECT',
            'properties': {
              'brand': {'type': 'STRING', 'nullable': true},
              'model': {'type': 'STRING', 'nullable': true},
              'generation': {'type': 'STRING', 'nullable': true},
              'variant': {'type': 'STRING', 'nullable': true},
              'basis': {'type': 'STRING'},
              'consistent_with_identification': {'type': 'BOOLEAN'},
            },
            'required': ['basis', 'consistent_with_identification'],
            'propertyOrdering': ['brand', 'model', 'generation', 'variant', 'basis', 'consistent_with_identification'],
          },
          'findings': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'claim_id': _enum([...claimIds, 'none']),
                'feature': {'type': 'STRING'},
                'area': {'type': 'STRING'},
                'part_request_id': _enum([...requestIds, 'other']),
                'image_ids': {'type': 'ARRAY', 'items': _enum(imageIds)},
                'observed': {'type': 'STRING'},
                'comparison': _enum(combinedComparisons),
                'difference_kind': _enum(['DIFFERENT', 'ABSENT', 'NOT_APPLICABLE']),
                'visibility': _enum(combinedVisibility),
                'reliability': _enum(['HIGH', 'MEDIUM', 'LOW']),
                'basis': _enum(combinedBasis),
                'knowledge_scope': _enum(combinedKnowledgeScopes),
                'detail_kind': _enum(combinedDetailKinds),
                'hard_to_copy': {'type': 'BOOLEAN'},
                'counterfeit_tell': {'type': 'BOOLEAN'},
                'alternative_explanation': {'type': 'STRING', 'nullable': true},
                'legitimate_variation': _enum(combinedVariation),
              },
              'required': [
                'claim_id', 'feature', 'area', 'part_request_id', 'image_ids', 'observed', 'comparison', 'difference_kind', 'visibility',
                'reliability', 'basis', 'knowledge_scope', 'detail_kind', 'hard_to_copy', 'counterfeit_tell', 'legitimate_variation',
              ],
              'propertyOrdering': [
                'claim_id', 'feature', 'area', 'part_request_id', 'image_ids', 'observed', 'comparison', 'difference_kind', 'visibility',
                'reliability', 'basis', 'knowledge_scope', 'detail_kind', 'hard_to_copy', 'counterfeit_tell', 'alternative_explanation',
                'legitimate_variation',
              ],
            },
          },
          'cross_image_contradictions': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'description': {'type': 'STRING'},
                'image_ids': {'type': 'ARRAY', 'items': _enum(imageIds)},
                'severity': _enum(['minor', 'moderate', 'critical']),
                'identity_related': {'type': 'BOOLEAN'},
              },
              'required': ['description', 'severity', 'identity_related'],
              'propertyOrdering': ['description', 'image_ids', 'severity', 'identity_related'],
            },
          },
          'proposed_verdict': _enum(combinedVerdicts),
          'verdict_reasoning': {'type': 'STRING'},
          'summary_points': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
          'unresolved': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'issue': {'type': 'STRING'},
                'resolving_photo': _enum([...requestIds, 'none']),
                'resolving_check': {'type': 'STRING', 'nullable': true},
              },
              'required': ['issue', 'resolving_photo'],
              'propertyOrdering': ['issue', 'resolving_photo', 'resolving_check'],
            },
          },
          'independent_verification': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
        },
        'required': ['identity_established', 'findings', 'cross_image_contradictions', 'proposed_verdict', 'verdict_reasoning', 'summary_points', 'unresolved'],
        'propertyOrdering': [
          'identity_established', 'findings', 'cross_image_contradictions', 'proposed_verdict', 'verdict_reasoning', 'summary_points', 'unresolved',
          'independent_verification',
        ],
      };

  static Map<String, dynamic> finalEvaluationSchema(List<EvidenceRecord> mismatches) => {
        'type': 'OBJECT',
        'properties': {
          'cross_photo_contradictions': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'description': {'type': 'STRING'},
                'photo_ids': _strings(),
                'severity': _enum(['minor', 'moderate', 'critical']),
                'identity_related': {'type': 'BOOLEAN'},
              },
              'required': ['description', 'severity', 'identity_related'],
              'propertyOrdering': ['description', 'photo_ids', 'severity', 'identity_related'],
            },
          },
          'variation_checks': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'key': mismatches.isEmpty ? {'type': 'STRING'} : _enum([for (final r in mismatches) recordKey(r)]),
                'legitimate_variation': _enum(['RULED_OUT', 'POSSIBLE', 'LIKELY']),
                'explanation': {'type': 'STRING'},
              },
              'required': ['key', 'legitimate_variation', 'explanation'],
              'propertyOrdering': ['key', 'legitimate_variation', 'explanation'],
            },
          },
          'identity_consistent': {'type': 'BOOLEAN'},
          'remaining_uncertainty': _strings(),
          'notes': {'type': 'STRING'},
        },
        'required': ['cross_photo_contradictions', 'variation_checks', 'identity_consistent', 'remaining_uncertainty'],
        'propertyOrdering': ['cross_photo_contradictions', 'variation_checks', 'identity_consistent', 'remaining_uncertainty', 'notes'],
      };

  // =====================================================================
  // helpers
  // =====================================================================

  static String _identityText(ProductIdentity id) {
    String attr(String label, IdentityAttribute a) =>
        a.isKnown ? '$label ${a.value} [${a.status.code}${a.basis.isEmpty ? '' : ': ${a.basis}'}]' : '$label not established';
    return [
      'category ${id.categoryCode}${id.productType.isEmpty ? '' : ' (${id.productType})'}',
      attr('brand', id.brand),
      attr('model', id.modelFamily),
      attr('generation', id.generation),
      if (id.exactModel.isKnown) attr('model number', id.exactModel),
    ].join('; ');
  }

  static String _generationText(ResolvedProfile p) {
    if (p.generation == null) return '';
    final established = p.identity.generation.status == AttributeStatus.confirmed ||
        p.generation!.id == 'ultra' && p.identity.modelFamily.isKnown;
    return 'Documented facts for ${p.generation!.label}${established ? '' : ' (generation not confirmed: use only facts shared by the whole family)'}:\n'
        '${p.generation!.notes.map((n) => '- $n').join('\n')}\n';
  }

  static Map<String, dynamic> _enum(List<String> values) => {'type': 'STRING', 'enum': values};
  static Map<String, dynamic> _strings() => {'type': 'ARRAY', 'items': {'type': 'STRING'}};

  /// Compact JSON for logs.
  static String compact(Object o) => jsonEncode(o);
}
