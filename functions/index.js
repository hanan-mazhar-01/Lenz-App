const functions = require("firebase-functions");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

// Redeployed after IAM fix (2026-09-23): force fresh instances so warm
// containers pick up the newly-granted Firestore/Storage/Artifact Registry
// permissions instead of a cached pre-fix credential.
const db = admin.firestore();

/**
 * Callable Cloud Function: generateStructuredContent
 *
 * Proxies Gemini 3.1 Flash Lite inference requests securely behind Firebase.
 * Enforces authentication, credit checks, and atomic quota decrements for scan finalization.
 */
exports.generateStructuredContent = functions
  .runWith({
    timeoutSeconds: 120,
    memory: "512MB",
    // Bound to Secret Manager. Set/update with:
    //   firebase functions:secrets:set GEMINI_API_KEY
    // then redeploy. Never hardcode a fallback key here.
    secrets: ["GEMINI_API_KEY"],
    // Keep one instance warm at all times. This is the scan-finalization
    // and identification path the whole app depends on, so cold starts here
    // (Admin SDK + Secret Manager init, worse right after any redeploy) show
    // up to users as a hard "can't reach the server" failure rather than a
    // slow request. Small fixed idle cost, in exchange for consistent
    // latency - see BACKEND_DEPLOYMENT.md.
    minInstances: 1,
  })
  .https.onCall(async (data, context) => {
    // 0. Fail loudly (not with a bogus key) if the secret isn't configured.
    const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
    if (!GEMINI_API_KEY) {
      console.error(
        "[generateStructuredContent] GEMINI_API_KEY secret is not configured."
      );
      throw new functions.https.HttpsError(
        "failed-precondition",
        "AI service is not configured. Please contact support."
      );
    }

    // 1. Verify caller authentication
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "The function must be called while authenticated."
      );
    }

    const uid = context.auth.uid;
    const { prompt, inlineImages, requestTypeLabel, maxOutputTokens } = data;
    // Optional Gemini responseSchema (engine v2). Bounded so a caller can't
    // push an arbitrarily large object through the proxy.
    const responseSchema =
      data.responseSchema && typeof data.responseSchema === "object" &&
      JSON.stringify(data.responseSchema).length < 30000
        ? data.responseSchema
        : null;

    if (!prompt || typeof prompt !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "The function must be called with a valid 'prompt' string."
      );
    }

    const userRef = db.collection("users").doc(uid);

    // 2. Transactional credit check/decrement for scan finalization
    const isScanFinalization =
      requestTypeLabel === "multi_image_forensic_observations";

    // Tracks whether this request actually took a credit, so it can be
    // refunded if the AI call below ends up failing (see the catch around
    // step 3) - otherwise a Gemini-side outage silently burns a user's
    // limited free scans for a result they never got.
    let creditDecremented = false;

    if (isScanFinalization) {
      await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);

        const isAnon =
          context.auth.token.firebase &&
          context.auth.token.firebase.sign_in_provider === "anonymous";

        let isPremium = false;
        let scansRemaining = 5;

        if (userDoc.exists) {
          const userData = userDoc.data();
          isPremium = Boolean(userData.isPremium);
          scansRemaining =
            typeof userData.scansRemaining === "number"
              ? userData.scansRemaining
              : 5;
        } else {
          // Initialize document if it doesn't exist yet
          scansRemaining = isAnon ? 3 : 5;
          transaction.set(userRef, {
            name: context.auth.token.name || (isAnon ? "Guest Collector" : "Collector"),
            email: context.auth.token.email || "",
            planName: isAnon ? "Guest Plan" : "Free Plan",
            isPremium: false,
            scansRemaining: scansRemaining,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        // Credit cap/decrement temporarily applies to guests only - signed-in
        // free accounts are uncapped for now (paywall disabled client-side
        // too, see main_navigation_shell.dart). Left scoped to isAnon rather
        // than removed outright so re-enabling for real accounts later is a
        // one-line change back to unconditional.
        if (isAnon) {
          if (!isPremium && scansRemaining <= 0) {
            throw new functions.https.HttpsError(
              "resource-exhausted",
              "No scan credits remaining. Please upgrade to premium."
            );
          }

          if (!isPremium) {
            transaction.update(userRef, {
              scansRemaining: scansRemaining - 1,
              lastScanAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            creditDecremented = true;
          }
        }
      });
    }

    try {
      return await callGeminiAndParse({ inlineImages, prompt, maxOutputTokens, responseSchema, GEMINI_API_KEY });
    } catch (err) {
      if (creditDecremented) {
        try {
          await userRef.update({
            scansRemaining: admin.firestore.FieldValue.increment(1),
          });
          console.warn(
            `[generateStructuredContent] Refunded 1 scan credit to uid=${uid} after AI call failure.`
          );
        } catch (refundErr) {
          console.error(
            `[generateStructuredContent] Failed to refund scan credit to uid=${uid}:`,
            refundErr
          );
        }
      }
      throw err;
    }
  });

/**
 * Calls Gemini (with model failover) and parses the structured JSON response.
 * Split out from the main handler so the credit-refund catch above can wrap
 * it without duplicating the request/parsing logic.
 */
async function callGeminiAndParse({ inlineImages, prompt, maxOutputTokens, responseSchema, GEMINI_API_KEY }) {
    // 3. Construct Gemini API request payload matching client shape
    const parts = [];
    if (Array.isArray(inlineImages) && inlineImages.length > 0) {
      parts.push(...inlineImages);
    }
    parts.push({ text: prompt });

    const basePayload = {
      contents: [{ parts }],
      generationConfig: {
        responseMimeType: "application/json",
        // Determinism for repeat scans: temperature 0 always takes the most
        // likely token, and a fixed seed pins any remaining sampling. The
        // same photos should produce the same findings.
        temperature: 0,
        seed: 20260926,
        maxOutputTokens: maxOutputTokens || 2048,
        ...(responseSchema ? { responseSchema } : {}),
      },
    };

    // Gemini returns transient 429/5xx errors (e.g. "model experiencing high
    // demand") fairly often, sometimes for many minutes straight on one
    // model (observed 2026-09-23: gemini-3.1-flash-lite down ~45+ min).
    // Retry server-side, and fail over to a sibling model with a separate
    // capacity pool if the primary stays down. thinkingConfig is a
    // gemini-3.1-flash-lite-specific hint - gemini-3.5-flash-lite rejected
    // it outright with 400 INVALID_ARGUMENT, so it's added per-model, not
    // globally.
    const modelCandidates = [
      { name: "gemini-3.1-flash-lite", thinkingConfig: { thinkingBudget: 0 } },
      { name: "gemini-3.5-flash-lite", thinkingConfig: null },
    ];
    // Keep this tight: the client's own request timeout for these calls is
    // as low as 30s (see gemini_authentication_repository.dart), and the
    // observed worst case with attemptsPerModel=2 blew past that (42-77s),
    // so the client gave up and showed a false "Request Timed Out" even on
    // a call that later succeeded server-side. One quick try per model,
    // fail over fast - sustained resilience comes from the client's own
    // retry loop across separate invocations, not from padding this one.
    const attemptsPerModel = 1;
    let response;
    let usedModel = null;
    modelLoop: for (let m = 0; m < modelCandidates.length; m++) {
      const { name: modelName, thinkingConfig } = modelCandidates[m];
      const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${GEMINI_API_KEY}`;
      const payload = thinkingConfig
        ? { ...basePayload, generationConfig: { ...basePayload.generationConfig, thinkingConfig } }
        : basePayload;
      for (let attempt = 1; attempt <= attemptsPerModel; attempt++) {
        const isLastOverallAttempt = m === modelCandidates.length - 1 && attempt === attemptsPerModel;
        try {
          response = await fetch(geminiUrl, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "x-goog-api-key": GEMINI_API_KEY,
            },
            body: JSON.stringify(payload),
          });
        } catch (networkError) {
          if (isLastOverallAttempt) {
            throw new functions.https.HttpsError(
              "unavailable",
              "Failed to connect to AI analysis service: " + networkError.message
            );
          }
          console.warn(`[Gemini network error] model=${modelName} attempt ${attempt}/${attemptsPerModel}: ${networkError.message}`);
          await new Promise((resolve) => setTimeout(resolve, 800 * attempt));
          continue;
        }

        if (response.ok) {
          usedModel = modelName;
          break modelLoop;
        }

        const status = response.status;
        const isTransient = status === 429 || status >= 500;
        if (isTransient && !isLastOverallAttempt) {
          const errText = await response.text();
          console.warn(`[Gemini HTTP Error ${status}] model=${modelName} attempt ${attempt}/${attemptsPerModel}, retrying...`, errText);
          await new Promise((resolve) => setTimeout(resolve, 800 * attempt));
          continue;
        }

        const errText = await response.text();
        console.error(`[Gemini HTTP Error ${status}] model=${modelName} attempt ${attempt}/${attemptsPerModel}, giving up`, errText);

        if (status === 429) {
          throw new functions.https.HttpsError(
            "resource-exhausted",
            "AI service rate limit reached. Please retry in a moment."
          );
        } else if (status === 401 || status === 403) {
          throw new functions.https.HttpsError(
            "unauthenticated",
            "AI service authorization error."
          );
        } else if (status >= 500) {
          throw new functions.https.HttpsError(
            "unavailable",
            `AI service temporarily unavailable (status ${status}).`
          );
        } else {
          throw new functions.https.HttpsError(
            "internal",
            `AI service returned status ${status}`
          );
        }
      }
    }

    const decoded = await response.json();
    const candidates = decoded.candidates;
    if (!candidates || candidates.length === 0) {
      throw new functions.https.HttpsError(
        "internal",
        "No candidates returned by AI service."
      );
    }

    const content = candidates[0].content;
    const partList = content && content.parts;
    const textPart =
      partList && partList.length > 0 ? partList[0].text : null;

    if (!textPart || !textPart.trim()) {
      throw new functions.https.HttpsError(
        "internal",
        "Empty response content received from AI service."
      );
    }

    // Strip markdown code fences if present
    let cleanJson = textPart.trim();
    if (cleanJson.startsWith("```json")) {
      cleanJson = cleanJson.substring(7);
    } else if (cleanJson.startsWith("```")) {
      cleanJson = cleanJson.substring(3);
    }
    if (cleanJson.endsWith("```")) {
      cleanJson = cleanJson.substring(0, cleanJson.length - 3);
    }
    cleanJson = cleanJson.trim();

    try {
      const parsed = JSON.parse(cleanJson);
      // Which model actually answered. The two failover models don't give
      // identical findings, so the client records this in every report's
      // analysis log to explain any result differences.
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        parsed._meta = {
          model: usedModel,
          finishReason: candidates[0].finishReason || null,
          schemaEnforced: Boolean(responseSchema),
        };
      }
      return parsed;
    } catch (parseError) {
      console.error("Failed to parse JSON response:", cleanJson);
      throw new functions.https.HttpsError(
        "internal",
        "Malformed JSON response from AI service: " + parseError.message
      );
    }
}

/**
 * Auth onCreate Trigger: onUserCreated
 *
 * Automatically provisions users/{uid} document with default free credits.
 * Anonymous (guest) accounts get 3 scans; real accounts get 5 - matching the
 * client's own _ensureUserDocumentExists so both paths agree on defaults
 * regardless of which one wins the race to create the document first.
 */
exports.onUserCreated = functions.auth.user().onCreate(async (user) => {
  const userRef = db.collection("users").doc(user.uid);
  const doc = await userRef.get();

  if (!doc.exists) {
    // Anonymous users have no linked sign-in providers.
    const isAnon = !user.providerData || user.providerData.length === 0;
    await userRef.set({
      name: user.displayName || (isAnon ? "Guest Collector" : "Collector"),
      email: user.email || "",
      planName: isAnon ? "Guest Plan" : "Free Plan",
      isPremium: false,
      scansRemaining: isAnon ? 3 : 5,
      avatarUrl: user.photoURL || "",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
});

/**
 * Callable Cloud Function: finalizeAccountUpgrade
 *
 * Called right after a guest successfully links a real credential (email,
 * Google, or Apple). Bumps scansRemaining/planName server-side, since
 * clients are never allowed to write those fields directly (see
 * firestore.rules). Idempotent and one-directional: it only ever raises a
 * guest's balance up to the free-account minimum once, and never touches an
 * already-premium account.
 */
exports.finalizeAccountUpgrade = functions.https.onCall(async (_data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "The function must be called while authenticated."
    );
  }

  const uid = context.auth.uid;
  const userRef = db.collection("users").doc(uid);
  const FREE_PLAN_SCANS = 5;

  await db.runTransaction(async (transaction) => {
    const doc = await transaction.get(userRef);

    if (!doc.exists) {
      transaction.set(userRef, {
        name: context.auth.token.name || "Collector",
        email: context.auth.token.email || "",
        planName: "Free Plan",
        isPremium: false,
        scansRemaining: FREE_PLAN_SCANS,
        upgradedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const userData = doc.data();

    // Never touch a premium account's balance.
    if (userData.isPremium) return;

    // Already a finalized free account (not a guest anymore) - nothing to do.
    // Guarding on planName (rather than just the scan count) keeps this from
    // re-topping-up a free user's balance every time they simply log back in.
    if (userData.planName && userData.planName !== "Guest Plan") return;

    const currentScans =
      typeof userData.scansRemaining === "number" ? userData.scansRemaining : 0;

    transaction.update(userRef, {
      planName: "Free Plan",
      scansRemaining: Math.max(currentScans, FREE_PLAN_SCANS),
      upgradedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { success: true };
});

/**
 * HTTPS Webhook: revenueCatWebhook
 *
 * Listens for subscription events and updates users/{uid} premium status.
 *
 * SECURITY: this endpoint is public (any onRequest HTTPS function is, by
 * definition, reachable by anyone who has the URL). It previously trusted
 * the request body with zero verification, meaning anyone could POST
 * {"event":{"app_user_id":"<any uid>","type":"INITIAL_PURCHASE"}} and grant
 * themselves free unlimited premium. RevenueCat sends an Authorization
 * header carrying a secret you configure in the RevenueCat dashboard
 * (Project Settings -> Webhooks) - this now requires that header to match a
 * secret held in Secret Manager. Until REVENUECAT_WEBHOOK_SECRET is actually
 * set (i.e. before RevenueCat is really wired up), every request is
 * rejected outright - fail closed, not fail open.
 */
exports.revenueCatWebhook = functions
  .runWith({ secrets: ["REVENUECAT_WEBHOOK_SECRET"] })
  .https.onRequest(async (req, res) => {
  try {
    const expectedSecret = process.env.REVENUECAT_WEBHOOK_SECRET;
    if (!expectedSecret) {
      console.error(
        "[revenueCatWebhook] REVENUECAT_WEBHOOK_SECRET is not configured - rejecting all requests."
      );
      return res.status(503).send("Webhook not configured.");
    }

    const authHeader = req.get("Authorization") || "";
    const providedSecret = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (providedSecret !== expectedSecret) {
      console.error("[revenueCatWebhook] Rejected request with invalid/missing Authorization header.");
      return res.status(401).send("Unauthorized");
    }

    const event = req.body && req.body.event;
    if (!event) {
      return res.status(400).send("Missing event data");
    }

    const appUserId = event.app_user_id;
    const eventType = event.type;

    if (!appUserId) {
      return res.status(400).send("Missing app_user_id");
    }

    const userRef = db.collection("users").doc(appUserId);

    if (
      eventType === "INITIAL_PURCHASE" ||
      eventType === "RENEWAL" ||
      eventType === "PRODUCT_CHANGE"
    ) {
      await userRef.set(
        {
          isPremium: true,
          planName: "VeriCheck Premium",
          scansRemaining: 9999,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } else if (
      eventType === "CANCELLATION" ||
      eventType === "EXPIRATION"
    ) {
      await userRef.set(
        {
          isPremium: false,
          planName: "Free Plan",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    return res.status(200).json({ received: true });
  } catch (err) {
    console.error("Webhook processing error:", err);
    return res.status(500).send(err.message);
  }
});

const CLOUDINARY_ROOT_FOLDER = "lenz_replica_detector";

/**
 * Deletes every Cloudinary asset whose public_id starts with [prefix]
 * (scoped under CLOUDINARY_ROOT_FOLDER). Uses the Admin API's
 * delete_resources_by_prefix endpoint directly via fetch + Basic Auth,
 * matching this file's existing no-extra-SDK style for the Gemini call.
 */
async function deleteCloudinaryAssetsByPrefix(prefix) {
  const cloudName = process.env.CLOUDINARY_CLOUD_NAME;
  const apiKey = process.env.CLOUDINARY_API_KEY;
  const apiSecret = process.env.CLOUDINARY_API_SECRET;

  if (!cloudName || !apiKey || !apiSecret) {
    console.error("[deleteCloudinaryAssetsByPrefix] Cloudinary secrets not configured; skipping.");
    return;
  }

  const fullPrefix = `${CLOUDINARY_ROOT_FOLDER}/${prefix}`;
  const auth = Buffer.from(`${apiKey}:${apiSecret}`).toString("base64");
  const url =
    `https://api.cloudinary.com/v1_1/${cloudName}/resources/image/upload` +
    `?prefix=${encodeURIComponent(fullPrefix)}`;

  try {
    const response = await fetch(url, {
      method: "DELETE",
      headers: { Authorization: `Basic ${auth}` },
    });
    if (!response.ok) {
      const errText = await response.text();
      console.error(`[deleteCloudinaryAssetsByPrefix] Cloudinary delete failed (${response.status}): ${errText}`);
    }
  } catch (e) {
    console.error("[deleteCloudinaryAssetsByPrefix] Request error:", e);
  }
}

/**
 * Callable Cloud Function: deleteAccountData
 *
 * Deletes every image a single scan uploaded to Cloudinary. Called by the
 * client right before it deletes a report/collection item locally + in
 * Firestore, so the Cloudinary copy doesn't outlive the record pointing to
 * it. Scoped to the caller's own uid - a user can only ever delete their
 * own scan's assets, never anyone else's.
 */
exports.deleteScanAssets = functions
  .runWith({ secrets: ["CLOUDINARY_CLOUD_NAME", "CLOUDINARY_API_KEY", "CLOUDINARY_API_SECRET"] })
  .https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");
  }
  const scanId = data && data.scanId;
  if (!scanId || typeof scanId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "scanId is required.");
  }
  await deleteCloudinaryAssetsByPrefix(`${context.auth.uid}_${scanId}_`);
  return { success: true };
});

/**
 * Callable Cloud Function: deleteAccount
 *
 * Full, permanent account deletion (Apple Guideline 5.1.1(v) / GDPR "right
 * to erasure"): removes every Firestore subcollection under users/{uid},
 * the user's images on Cloudinary, and finally the Firebase Auth account
 * itself. Done entirely server-side with Admin privileges specifically so
 * deleting the Auth user never hits the client-side "requires recent
 * login" re-authentication error - Admin SDK deletion has no such
 * restriction. This is the ONLY function that deletes a Firebase Auth
 * user in this codebase; it always targets context.auth.uid, so a caller
 * can only ever delete their own account.
 */
exports.deleteAccount = functions
  .runWith({ secrets: ["CLOUDINARY_CLOUD_NAME", "CLOUDINARY_API_KEY", "CLOUDINARY_API_SECRET"] })
  .https.onCall(async (_data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");
  }

  const uid = context.auth.uid;
  const userRef = db.collection("users").doc(uid);

  async function deleteSubcollection(name) {
    const snap = await userRef.collection(name).get();
    if (snap.empty) return;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }

  try {
    await deleteSubcollection("reports");
    await deleteSubcollection("collection");
    await deleteSubcollection("categories");
    await userRef.delete();
  } catch (e) {
    console.error("[deleteAccount] Firestore cleanup error:", e);
    throw new functions.https.HttpsError("internal", "Failed to delete account data. Please try again.");
  }

  // Best-effort - don't fail the whole deletion if Cloudinary is unreachable.
  await deleteCloudinaryAssetsByPrefix(`${uid}_`);

  try {
    await admin.auth().deleteUser(uid);
  } catch (e) {
    console.error("[deleteAccount] Auth user deletion error:", e);
    throw new functions.https.HttpsError(
      "internal",
      "Account data was deleted, but the sign-in record could not be removed. Please contact support."
    );
  }

  return { success: true };
});

