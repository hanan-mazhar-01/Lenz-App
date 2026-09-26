# Authenticity Engine v2

Engine version `2.0`, prompt version `2.0`, both recorded on every report
(`lib/core/config/authenticity_engine_config.dart`).

## Flow

```
first photo ──► local quality check ──► Gemini identification (schema-enforced)
                                           │  category_code incl. SUNGLASSES / EYEGLASSES / WALLET
                                           ▼
             deterministic checklist from the category/model rule set
                                           │
             per-photo validation (right area? usable?)
                                           ▼
   all photos ──► Gemini forensic pass (12 steps, typed findings, schema-enforced)
                                           ▼
              scoring engine: normalize findings ──► decision hierarchy
                                           │
                         LIKELY_REPLICA? ──► Gemini verification pass (challenges each finding)
                                           ▼                         └─► re-score
              repeat-scan consistency vs. earlier scans of the same product
                                           ▼
                                report + analysis log
```

| Piece | File |
|---|---|
| Thresholds and versions | `lib/core/config/authenticity_engine_config.dart` |
| Prompts and JSON schemas | `lib/services/authenticity_prompts.dart` |
| Category rules, checklists, cautions | `lib/data/authentication_rules.dart` |
| Typed findings, absence rules | `lib/models/evidence_finding.dart` |
| Decision logic | `lib/services/authentication_scoring_engine.dart` |
| Repeat-scan consistency | `lib/services/scan_consistency_service.dart` |
| Local image quality | `lib/services/image_quality_checker.dart` |
| Pipeline wiring and logging | `lib/repositories/gemini_authentication_repository.dart` |
| Backend (temperature 0, seed, schema) | `functions/index.js` |

## Adding a category

1. Add a `ProductCategory` value and map its code in `ProductIdentification.categoryForCode`.
2. Add a blueprint (mark identity-marking photos with `identityMarking: true`),
   inspection rules and cautions in `AuthenticationRules.forCategory`.
3. For a model that needs different rules, add a `modelOverlays` entry
   (`replacesBaseRules: true` if the category rules would mislead, as for Apple Watch).

No prompt, engine or UI changes are needed.

## Live evaluation (§32-33)

Build a dataset folder with a `manifest.json`:

```json
{
  "items": [
    {
      "id": "aw_s9_genuine_01",
      "truth": "GENUINE",
      "category": "watches",
      "category_code": "WATCH",
      "brand": "Apple",
      "name": "Apple Watch Series 9",
      "model": "Series 9 45mm",
      "images": {
        "front_display": "aw_s9_genuine_01/front.jpg",
        "back_sensor": "aw_s9_genuine_01/back.jpg",
        "side_crown": "aw_s9_genuine_01/side.jpg"
      }
    }
  ]
}
```

`images` keys are the evidence ids from the category checklist (see
`AuthenticationRules`). Include genuine and replica items for every category,
and photograph each item under varied lighting, backgrounds, angles, distances,
cameras, slight blur and partial occlusion. Most importantly, include several
photo sets of the same physical item.

Run it (the key is only read from the environment; never commit it):

```sh
LENZ_EVAL_GEMINI_KEY=... LENZ_EVAL_DATASET=/path/to/manifest.json LENZ_EVAL_REPEATS=10 \
  flutter test test/eval/live_repeat_scan_eval_test.dart
```

Results go to `eval_results/eval_<timestamp>.json`: false positive rate
(genuine called replica), false negative rate, precision, recall, inconclusive
rate, repeat-scan consistency, authentic↔replica flip rate, expected
calibration error, per category, both per scan and with consistency applied.

Suggested release gates: flip rate 0, false positive rate under 2%, and
replicas passed as authentic under 5%. Tune the thresholds in
`AuthenticityEngineConfig` against the dataset, then bump `engineVersion`.

## Deploying

The app works against the current backend, but the determinism and
schema enforcement only take effect after:

```sh
firebase deploy --only functions:generateStructuredContent
```
