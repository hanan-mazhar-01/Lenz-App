# Authenticity Engine v4

Engine version `4.1`, prompt version `4.2`, both recorded on every report
(`lib/core/config/authenticity_engine_config.dart`). Reports from engine v3
and earlier still load and display as before. The screens are unchanged
(original screens plus the camera capture screen); all changes are in the
pipeline, the backend and the report data.

## Flow

```
first photo ─► on-device check (dark / blank / corrupt), native decode
            ─► 1. product recognition (Gemini, schema-enforced)
                  brand / model / generation / model number with certainty;
                  unsupported categories and generic unbranded items refused
            ─► evidence profile resolved (which photos to ask for)
            ─► 2. evidence recommendation + 4. analysis of first photo
                  │
  each photo ─┤  on-device focus / motion / glare / duplicate checks
              ├─ 3. quality and part check (Gemini): wrong part refused
              ├─ 4. per-photo analysis against the profile checklist
              └─ checklist moves on (per-photo engine, as in v3)
                  │
  finish ─────► 6. ONE combined analysis: all photos together + in-memory
                  close-ups + app checklist + earlier per-photo
                  observations; Gemini uses its own knowledge of the
                  identified product (no web search); thinking level "low"
            ─► FinalVerdictValidator: explicit rules decide whether the
                  proposed verdict is supported; otherwise "Not sure"
            ─► structured assessment ─► consistency service ─► report
```

No Google Search, grounding or other external research is used anywhere
(removed in 4.1 at the owner's request; the `researchProductReference`
function was deleted from Firebase). The Gemini proxy never sends `tools`.

| Piece | File |
|---|---|
| Versions, model, limits, prices, final-stage settings | `lib/core/config/authenticity_engine_config.dart` |
| App checklist for the final stage | `lib/models/product_reference.dart` |
| Combined-analysis prompt and schema | `lib/services/authenticity_prompts.dart` |
| Final verdict rules | `lib/services/final_verdict_validator.dart` |
| In-memory detail crops | `lib/services/detail_cropper.dart`, `lib/services/native_image_decoder.dart` |
| Per-photo engine and planner (capture stage) | `lib/services/evidence_decision_engine.dart`, `evidence_planner.dart` |
| Profiles: which photos to ask for, checklist items | `lib/data/profiles/` |
| Pipeline wiring, correlation id, diagnostics | `lib/repositories/gemini_authentication_repository.dart` |
| Backend: proxy, limits, billing | `functions/index.js`, `functions/lib/{gemini,limits}.js` |
| Backend tests | `functions/test/*.test.js` (`npm test` in `functions/`) |

## Knowledge used

Gemini 3.1 Flash-Lite's own knowledge of the identified product, stated per
finding with a scope (this generation, model family, brand-wide, or not
sure). The app checklist (from the evidence profile) lists the parts to check,
the few documented genuine details, and the parts no genuine version differs
in (catalog "decisive" checkpoints); it is guidance and a safeguard, not
verified manufacturer data. The former four-product `ReferenceLibrary` was
removed. Reports say: "Compared with Gemini's own knowledge of this model and
the app's checklist; this is a photographic assessment, not a verification by
the manufacturer."

## Final verdict (FinalVerdictValidator)

Gemini sees every photo at once (first photo first, then evidence photos at
1536 px, 1024 px if the request would exceed 7.5 MB) plus up to four
close-ups cut in memory from the full-resolution photo around the detail the
photo check located. A close-up is only made when it shows the detail with at
least 1.3x more pixels than the whole photo does; it is never saved or shown
and never counts as a separate photo. For each checklist item and each other
distinguishing detail it knows, it reports the images, what is visible,
MATCHES / CONFLICTS / UNCLEAR / NOT_VISIBLE, visibility, reliability, the
photo part, detail kind, whether copies struggle with it (hard to copy) or
commonly get it wrong (counterfeit tell), its knowledge scope and the
legitimate-variation check; plus contradictions between photos, the identity
the photos establish, unresolved issues with the photo that would resolve
them, and a proposed verdict with its reasoning. The validator then applies
these rules:

* Findings: an obscured or not-visible detail is never evidence either way; a
  partly visible one is at most medium reliability; a blurry photo lowers
  reliability; a conflict the model attributes to photo conditions loses one
  level; a likely legitimate variation makes it unclear, a possible one makes
  it weak; generic quality ("neat stitching") is never proof of
  authenticity; knowledge Gemini is not sure applies, or that is specific to
  a generation that is not established, does not count.
* Independence: findings are grouped by physical part, i.e. the app's photo
  part (logo, sub-dials and date window on a dial are one part); a close-up
  counts as its parent photo.
* Printed or engraved text, logos and device screens never serve as the
  hard-to-copy match.
* A missing detail counts against the item only when the brand is known, the
  area is clearly photographed and the checklist documents that the genuine
  item has it.
* Unknown brand: no verdict either way; the report asks for a photo of the
  logo or label.
* **Replica**: a decisive checklist difference (clearly visible, high
  reliability, variations ruled out) or material differences on two
  independent parts. A difference known only from Gemini's knowledge is
  never decisive on its own. A decisive difference against two hard-to-copy
  matches is "contested" (Not sure).
* **Authentic** (a photographic assessment, never manufacturer verification):
  nothing material against, no serious per-photo difference left unsettled,
  the photos agree on the model, three independent specific matches on
  different parts, at least one hard to copy, seen in two or more photos.
* Gemini's proposal must agree with the rules; otherwise the result is "Not
  sure" and the report says what is missing. The rules never turn a "not
  sure" proposal into a verdict. API errors, malformed, truncated or blocked
  answers are errors with retry, never results.
* No numeric confidence is produced; reports show Strong / Moderate / Limited.

The per-photo engine (v3 rules, profile checklist) still drives the photo
checklist during capture. Its serious differences are passed to the combined
call, which must confirm or settle each one; an unsettled one blocks
Authentic. The v3 final stage (`FinalStageMode.legacyTextOnly`) is kept only
for side-by-side evaluation.

Removed as hard requirements: the profile's "required checks" (e.g. the
device screen for smartwatches) and the fixed identity level per category.

## Pictures of pictures are refused

The identification and every photo check report `image_source`:
PHYSICAL_ITEM (the item itself, including its own display), DEVICE_SCREENSHOT
(allowed only for device-information requests), SCREEN_OR_PRINT (a photo of a
computer, phone or TV screen or of a printed picture) or INTERNET_IMAGE (a
render, marketing, listing, stock or studio photo, or overlays). The last two
are refused: the first photo with reason `not_real_photo` ("This is a
picture, not the item"), an evidence photo as the wrong evidence, never
usable as evidence. A hint from the original file's metadata goes with the
request (`lib/services/image_origin.dart`: no camera information, or an
editing tool such as Lightroom), read before any EXIF stripping; it is only
a hint, so real photos from messaging apps are still accepted.

Live check (2026-09-27): the owner's screen photos and internet images of an
Apple Watch were refused at both steps; real camera photos, and the same real
photos with their metadata removed, were accepted.

## Report numbers

The report screen's three tiles and the evidence lines are computed per scan
(none of them is a probability that the verdict is right):

* **Photo quality**: average of the on-device measurements of each photo
  (focus of the sharpest region, exposure, glare, resolution).
* **Analysis confidence**: share of the details checked in the final
  analysis that could be judged clearly (matched or differed with at least
  medium reliability), one per feature and part.
* **Item identified**: how completely the item is identified: brand 40,
  model 35 and, for products with generations, generation 25; full points
  when CONFIRMED, half when PROBABLE.
* **Evidence line** (per photo): the same judged share for that photo's
  details; the badge stays the status word.

The camera screen's indicator counts the checklist photos taken out of the
checklist; the first (identification) photo counts as evidence but never
fills a checklist item, so the checklist starts empty.

## On-device image processing

Each photo is decoded once, at full resolution, by the platform decoder
(`lib/services/native_image_decoder.dart`) and kept as two sizes: 1024 px for
the quality checks and the identification / photo-check uploads, 1536 px
for the analysis upload. Both are area-averaged with the same source windows
as `img.copyResize(interpolation: average)`, so the calibrated focus, motion
and glare thresholds are unchanged. The platform decoder is never asked to
resize, because its filter is softer (whole-photo focus came out about 30%
lower). Upload sizes are prepared in the background while the on-device check
and the photo-check call run.

Before this change the pure-Dart decoder opened every full-resolution photo
four times. On the test phone (Helio P35, debug build, 8 MP photos) each
decode took about 10 s, so a photo waited about 40 s on the phone versus
about 5 to 8 s for its Gemini calls (Cloud Function logs, 2026-09-26).
On 175 real photos the new path gives the same quality issues as the old one.
On a desktop, the on-device work per 8 MP photo went from 6.4 s to 1.0 s.
JPEGs with an EXIF rotation flag, and any decode error, fall back to the
Dart decoder.

## Supported categories

Only the categories the app supported before engine v3 are scanned: watches
(analogue and smart), handbags, sneakers, shoes, clothing, wallets, belts,
jewellery and other fashion accessories, sunglasses and eyeglasses
(category codes `WATCH HANDBAG SNEAKER SHOE CLOTHING WALLET ACCESSORY
SUNGLASSES EYEGLASSES`). Two layers enforce this:

- The identification prompt refuses other objects (perfume, cosmetics,
  phones, earbuds and other electronics, household items...) and generic
  local items with no brand identity at all, as `not_product` /
  `unsupported_object`. An item whose brand is merely not visible from this
  angle, or that imitates a known brand (a replica), is identified normally.
- `ProductIdentification.fromJson` refuses any detected product whose code is
  outside `supportedCategoryCodes`, or an "accessory" whose type names a
  fragrance, cosmetic or gadget, even if the model let it through.

Live check (2026-09-27, 13 real photos): all 11 watches and shoes, including
the replica Ultra, the "MK" replica sneaker and the genuine smart band with no
visible brand, were identified; both fragrances were refused. No real photo
of a generic local item was available, so the unbranded-item rule has only
been checked through unit tests.

## Adding a category or model

Add an `EvidenceProfile` to `lib/data/profiles/` and list it in
`ProfileCatalog.all`. If the identification step needs a new category code,
add it to `AuthenticityPrompts.categoryCodes`,
`ProductIdentification.categoryCodes` and
`ProductIdentification.supportedCategoryCodes`, and to the supported list in
the identification prompt. For generation-specific facts, add
`GenerationSpec`s. No engine, planner or UI changes are needed. Only state
genuine / replica details you can document; otherwise leave them null and the
evidence is labelled as AI model knowledge.

## Model and configuration

Every call uses `gemini-3.1-flash-lite`. Thinking stays off (`thinkingBudget
0`) for identification, photo checks and per-photo analysis; the combined
analysis uses `thinkingLevel: low`. All four levels (minimal, low, medium, high)
were verified to be accepted by this model. The backend treats any finish
reason other than STOP (token limit, safety, recitation) as an error and
never logs prompts, images or model output.

## Security and billing (backend)

* Requests are validated and bounded: at most 16 images, JPEG/PNG/WebP only,
  3.5M base64 characters per image and 9.5M in total, prompts up to 100k
  characters, schemas up to 30k, output tokens up to 8192, thinking level
  from an allow-list.
* Rate limits per user: 40 requests a minute, 150 a day for guests and 500
  for accounts.
* Scan credits no longer depend on the request label: a scan session (the
  app's correlation id; a 15-minute window for old clients) is charged once,
  at its first request with two or more photos or when it exceeds 12
  requests. Credits are refunded when the AI call fails. As before, only
  guest accounts are capped.
* Firestore rules: a client can no longer delete its own `users/{uid}`
  document (deleting and re-creating it reset the scan credits);
  `rate_limits` and `scan_sessions` are server-only.
* App Check: the app did not include the App Check SDK, so no token was ever
  sent ("app: MISSING" in the logs) and the function did not enforce it. The
  app now activates App Check (debug provider in debug builds, Play
  Integrity / App Attest in release). Enforcement is controlled by
  `ENFORCE_APP_CHECK` in `functions/.env` and stays off until the apps are
  registered in the console.
* Logs are structured and content-free: correlation id (the scan id), hashed
  user id, request label, images and size, thinking level, finish reason,
  tokens, duration, whether a credit was charged, App Check status. In the
  app, diagnostics (identification, photo quality, findings per comparison,
  the validator trace with Gemini's verdict reasoning, and the reason for
  every "Not sure") are printed only in debug builds.

## Deploying

Deployed on 2026-09-27: `generateStructuredContent` (validation, limits,
label-independent billing, no tools) and `firestore.rules`;
`researchProductReference` deleted. To redeploy:

```sh
cd functions && npm test && cd ..
firebase deploy --only functions:generateStructuredContent,firestore:rules
```

Optional, in the Firebase / Google Cloud console:

* Firestore TTL policy on `scan_sessions.expiresAt` (cleanup).
* App Check: register the Android app (Play Integrity, SHA-256 of the release
  key) and the iOS app (App Attest), add the debug token printed in the debug
  app's log, then set `ENFORCE_APP_CHECK=true` in `functions/.env` and deploy
  again.
* The current `GEMINI_API_KEY` (secret version 4) is a free-tier key: Google
  may use free-tier prompts and photos to improve its products, and rate
  limits are low. Version 3 is the paid key; after topping up its prepaid
  credits, destroy version 4 (or set the paid key again) and redeploy.

## Cost (Gemini 3.1 Flash-Lite, paid tier)

Input $0.25 and output (including thinking) $1.50 per million tokens (paid
tier; free of charge on the free tier). No search costs.

Measured per call (live evaluation, 24 scans, 2026-09-27):

| Call | Mean cost | Median time |
|---|---|---|
| Identification | $0.0012 | 3.1 s |
| Photo check (per photo) | $0.0007 | 2.2 s |
| Per-photo analysis (per photo) | $0.0016 | 3.6 s |
| Final stage v3 (text only) | $0.0007 | 2.3 s |
| Final stage v4 (combined, about 5 images) | $0.0039 | 5.9 s |

A complete scan with about five photos costs about $0.012 before the final
stage; the v4 final stage adds about $0.003 over v3.

## Live regression evaluation

`test/eval/live_regression_eval_test.dart` identifies, checks and analyses
each case's photos once, then runs two final stages on the same evidence:
v3 (text-only) and v4 (combined multi-image analysis with Gemini's own
knowledge and the app checklist), and writes
`eval_results/v4_comparison_<ts>.json`. Cases can be selected or split across
processes with `LENZ_EVAL_CASES=id1,id2,...`; `eval_data/merge_results.py
<since-epoch>` merges shard files.

```sh
LENZ_EVAL_GEMINI_KEY=... LENZ_EVAL_DATASET=eval_data/manifest.json \
  flutter test test/eval/live_regression_eval_test.dart
```

Dataset (`eval_data/`, git-ignored, rebuilt from the owner's device reports
by `eval_data/build_manifest.py`): real scans labelled by the owner: the
replica Apple Watch Ultra (4 scans at 1080x1920 plus 3 full-resolution scans
of the same item, identified by its cream back and four printed marks and
checked visually), the replica "MK SHOES" sneaker (2 scans) and a genuine
smart band (3 scans). Only three physical items: this is not a representative
or independently verified dataset, and the numbers must not be read as
general accuracy.

Engine 4.1 (no web search), 2026-09-27, 12 labelled scans:

| Final stage | Correct | False authentic | False replica | Not sure |
|---|---|---|---|---|
| v3 (text only) | 9 | 0 | 0 | 3 |
| v4.1 (combined, own knowledge) | 9 | 0 | 0 | 3 |

All nine replica scans were called replica by both. The three genuine band
scans stay "not sure": their photos show no brand or model, so no verdict is
allowed. On one of them Gemini proposed REPLICA only because no branding was
visible; the validator rejected that proposal (a missing logo on an unknown
brand proves nothing). On this dataset v4.1 is not more accurate than v3; its
gains are the combined view of all photos, the explanation of each verdict
and the safeguards listed above.

Earlier engine 4.0 runs (with live research, since removed) found and fixed
two failures: the replica Ultra came out Authentic when research listed only
details copies imitate and the combined call ignored the per-photo "cream
plastic back" finding (fixed: checklist decisive parts always included,
unsettled per-photo differences block Authentic, text is never the
hard-to-copy match); and a genuine unbranded-looking band came out Replica
from "no logo" (fixed: unknown-brand and missing-detail rules). Results move
by about one case between runs with the same code.
