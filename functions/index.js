const functions = require("firebase-functions");
const admin = require("firebase-admin");

const gemini = require("./lib/gemini");
const limits = require("./lib/limits");

if (!admin.apps.length) {
  admin.initializeApp();
}

// Redeployed after IAM fix (2026-09-23): force fresh instances so warm
// containers pick up the newly-granted Firestore/Storage/Artifact Registry
// permissions instead of a cached pre-fix credential.
const db = admin.firestore();

// App Check: the Flutter app now sends App Check tokens. Enforcement stays
// off until the Android/iOS apps are registered in Firebase Console -> App
// Check (Play Integrity / App Attest) and debug tokens are added; then set
// ENFORCE_APP_CHECK=true in functions/.env and redeploy. Until then the
// verification result is only logged.
const ENFORCE_APP_CHECK = process.env.ENFORCE_APP_CHECK === "true";

function logEvent(event, fields, severity = "INFO") {
  const entry = { severity, message: event, evt: event, ...fields };
  if (severity === "ERROR") console.error(JSON.stringify(entry));
  else if (severity === "WARNING") console.warn(JSON.stringify(entry));
  else console.log(JSON.stringify(entry));
}

function httpsErrorFor(err) {
  if (err instanceof functions.https.HttpsError) return err;
  if (err instanceof limits.RequestError) return new functions.https.HttpsError(err.code, err.message);
  if (err instanceof gemini.GeminiError) {
    const map = {
      rate_limited: "resource-exhausted",
      auth: "unauthenticated",
      unavailable: "unavailable",
      network: "unavailable",
      quota_exhausted: "failed-precondition",
      bad_request: "internal",
      truncated: "internal",
      blocked: "internal",
      empty: "internal",
      malformed: "internal",
    };
    // The client checks the reason word to decide whether to retry.
    return new functions.https.HttpsError(map[err.code] || "internal", err.message, { reason: err.code });
  }
  return new functions.https.HttpsError("internal", "Unexpected server error.");
}

function requireAuth(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "The function must be called while authenticated.");
  }
}

function geminiKey() {
  const key = process.env.GEMINI_API_KEY;
  if (!key) {
    console.error("[ai] GEMINI_API_KEY secret is not configured.");
    throw new functions.https.HttpsError("failed-precondition", "AI service is not configured. Please contact support.");
  }
  return key;
}

const AI_RUNTIME = {
  timeoutSeconds: 120,
  memory: "512MB",
  // Bound to Secret Manager. Set/update with:
  //   firebase functions:secrets:set GEMINI_API_KEY
  // then redeploy. Never hardcode a fallback key here.
  secrets: ["GEMINI_API_KEY"],
  enforceAppCheck: ENFORCE_APP_CHECK,
};

/**
 * Callable Cloud Function: generateStructuredContent
 *
 * Proxies gemini-3.1-flash-lite requests behind Firebase Auth. Validates and
 * bounds every request, applies per-user rate limits, and charges scan
 * credits per scan session independently of the request label (see
 * lib/limits.js). Malformed, truncated or blocked AI responses are errors,
 * never results.
 */
exports.generateStructuredContent = functions
  .runWith({
    ...AI_RUNTIME,
    // Keep one instance warm at all times. This is the scan-finalization
    // and identification path the whole app depends on, so cold starts here
    // (Admin SDK + Secret Manager init, worse right after any redeploy) show
    // up to users as a hard "can't reach the server" failure rather than a
    // slow request. Small fixed idle cost, in exchange for consistent
    // latency - see BACKEND_DEPLOYMENT.md.
    minInstances: 1,
  })
  .https.onCall(async (data, context) => {
    const apiKey = geminiKey();
    requireAuth(context);
    const uid = context.auth.uid;
    const started = Date.now();

    let req;
    try {
      req = limits.validateGenerateRequest(data);
    } catch (e) {
      throw httpsErrorFor(e);
    }
    const cid = req.scanId || "no-scan-id";

    let admission;
    try {
      admission = await limits.admitCall({ db, admin, uid, token: context.auth.token, scanId: req.scanId, imageCount: req.images.length });
    } catch (e) {
      logEvent("ai_call_rejected", { cid, user: limits.logId(uid), label: req.label, reason: e.message }, "WARNING");
      throw httpsErrorFor(e);
    }

    try {
      const decoded = await gemini.generateContent({
        apiKey,
        parts: [...req.images, { text: req.prompt }],
        generationConfig: {
          responseMimeType: "application/json",
          // Determinism for repeat scans: temperature 0 always takes the most
          // likely token, and a fixed seed pins any remaining sampling.
          temperature: 0,
          seed: 20260926,
          maxOutputTokens: req.maxOutputTokens,
          ...(req.responseSchema ? { responseSchema: req.responseSchema } : {}),
          thinkingConfig: gemini.thinkingConfigFor(req.thinkingLevel),
        },
        timeoutMs: 100000,
      });
      const candidate = gemini.finishedCandidate(decoded);
      const parsed = gemini.parseJsonAnswer(gemini.answerText(candidate));
      const usage = gemini.usageSummary(decoded);
      parsed._meta = {
        model: gemini.MODEL,
        finishReason: candidate.finishReason || "STOP",
        schemaEnforced: Boolean(req.responseSchema),
        thinkingLevel: req.thinkingLevel || "none",
        correlationId: cid,
        creditCharged: admission.charged,
        // Token counts, so the app can record actual usage and cost.
        usage: decoded.usageMetadata || null,
      };
      logEvent("ai_call", {
        cid,
        user: limits.logId(uid),
        label: req.label,
        images: req.images.length,
        imageKB: Math.round((req.imageChars * 3) / 4 / 1024),
        thinking: req.thinkingLevel || "none",
        finish: parsed._meta.finishReason,
        ms: Date.now() - started,
        charged: admission.charged,
        appCheck: context.app ? "valid" : "missing",
        ...usage,
      });
      return parsed;
    } catch (err) {
      if (admission.charged) {
        try {
          await limits.refundCall({ db, admin, sessionRef: admission.sessionRef, userRef: admission.userRef });
          logEvent("credit_refunded", { cid, user: limits.logId(uid) }, "WARNING");
        } catch (refundErr) {
          logEvent("credit_refund_failed", { cid, user: limits.logId(uid), error: refundErr.message }, "ERROR");
        }
      }
      // Content-free: never log prompts, images or model output (they can
      // contain serial numbers read from the user's photos).
      logEvent("ai_call_failed", {
        cid,
        user: limits.logId(uid),
        label: req.label,
        reason: err.code || "unknown",
        error: String(err.message || err).slice(0, 200),
        ms: Date.now() - started,
      }, "ERROR");
      throw httpsErrorFor(err);
    }
  });

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
  const FREE_PLAN_SCANS = 3;

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

    transaction.update(userRef, {
      planName: "Free Plan",
      scansRemaining: FREE_PLAN_SCANS,
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

    const eventType = event.type;
    const grantPremium = (uid) =>
      db.collection("users").doc(uid).set(
        {
          isPremium: true,
          planName: "VeriCheck Premium",
          scansRemaining: 9999,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    const revokePremium = (uid) =>
      db.collection("users").doc(uid).set(
        {
          isPremium: false,
          planName: "Free Plan",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    // TRANSFER moves an entitlement between RevenueCat app user ids and has
    // no single app_user_id of its own - handle it before the generic
    // appUserId check below.
    if (eventType === "TRANSFER") {
      const toIds = Array.isArray(event.transferred_to) ? event.transferred_to : [];
      const fromIds = Array.isArray(event.transferred_from) ? event.transferred_from : [];
      await Promise.all([...toIds.map(grantPremium), ...fromIds.map(revokePremium)]);
      return res.status(200).json({ received: true });
    }

    const appUserId = event.app_user_id;
    if (!appUserId) {
      return res.status(400).send("Missing app_user_id");
    }

    if (
      eventType === "INITIAL_PURCHASE" ||
      eventType === "RENEWAL" ||
      eventType === "PRODUCT_CHANGE" ||
      eventType === "UNCANCELLATION"
    ) {
      await grantPremium(appUserId);
    } else if (
      eventType === "CANCELLATION" ||
      eventType === "EXPIRATION" ||
      eventType === "REFUND"
    ) {
      await revokePremium(appUserId);
    } else if (eventType === "BILLING_ISSUE" || eventType === "SUBSCRIPTION_PAUSED") {
      // Apple/RevenueCat still consider the subscription active during a
      // billing grace period or pause - don't revoke access pre-emptively.
      // An EXPIRATION event will arrive if it isn't resolved.
      logEvent("revenuecat_webhook_grace_period", { appUserId, eventType }, "WARNING");
    } else {
      logEvent("revenuecat_webhook_unhandled", { appUserId, eventType }, "WARNING");
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
    logEvent("cloudinary_delete_skipped_unconfigured", { prefix }, "ERROR");
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
      // Deliberately non-fatal (callers don't block user-facing deletion on
      // a third-party outage) - but logged at ERROR severity, not just
      // console.error, so a persistent failure is actually visible/alertable
      // instead of silently leaving orphaned images on Cloudinary forever.
      logEvent("cloudinary_delete_failed", { prefix, status: response.status, body: errText.slice(0, 300) }, "ERROR");
    }
  } catch (e) {
    logEvent("cloudinary_delete_error", { prefix, error: e.message }, "ERROR");
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
    // One immediate retry - this step runs after Firestore data is already
    // gone, so a transient failure here (not permission/not-found) would
    // otherwise leave an orphaned Auth record with nothing behind it.
    try {
      await new Promise((resolve) => setTimeout(resolve, 500));
      await admin.auth().deleteUser(uid);
    } catch (e2) {
      console.error("[deleteAccount] Auth user deletion error:", e2);
      logEvent("delete_account_orphaned_auth_user", { uid }, "ERROR");
      throw new functions.https.HttpsError(
        "internal",
        "Account data was deleted, but the sign-in record could not be removed. Please contact support."
      );
    }
  }

  return { success: true };
});

