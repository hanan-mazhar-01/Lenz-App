const crypto = require("crypto");
const functions = require("firebase-functions");
const admin = require("firebase-admin");

const gemini = require("./lib/gemini");
const limits = require("./lib/limits");
const revenuecat = require("./lib/revenuecat");
const cloudinary = require("./lib/cloudinary");
const anonymousCleanup = require("./lib/anonymous_cleanup");
const deviceGrants = require("./lib/device_grants");
const accountData = require("./lib/account_data");

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

/**
 * limits.admitCall, but before refusing a user for "no credits" ask
 * RevenueCat directly whether they hold an active `pro` entitlement. The
 * webhook is what normally sets users/{uid}.isPremium; if it hasn't arrived
 * (or isn't configured), someone who just paid would otherwise be blocked
 * on their very next scan. On a hit, persist isPremium and admit the call.
 */
const RC_LOOKUP_MIN_INTERVAL_MS = 60 * 1000;

async function admitWithEntitlementFallback(args) {
  try {
    return await limits.admitCall(args);
  } catch (e) {
    if (!(e instanceof limits.RequestError) || e.reason !== "no_credits") throw e;

    // At most one RevenueCat lookup per user per minute: a user with no
    // credits must not be able to turn scan attempts into unbounded calls
    // to RevenueCat (the refused call's rate-limit counters roll back).
    const userRef = args.db.collection("users").doc(args.uid);
    const nowMs = Date.now();
    const snap = await userRef.get();
    const last = snap.exists ? snap.data().rcCheckedAtMs : null;
    if (typeof last === "number" && nowMs - last < RC_LOOKUP_MIN_INTERVAL_MS) throw e;
    await userRef.set({ rcCheckedAtMs: nowMs }, { merge: true });

    const ent = await revenuecat.getActiveEntitlement(args.uid, {
      apiKey: process.env.REVENUECAT_SECRET_API_KEY,
      nowMs,
    });
    if (!ent.active) throw e;
    await userRef.set(
      {
        ...revenuecat.proFields(ent.expiresAtMs),
        updatedAt: args.admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    logEvent("premium_synced_from_revenuecat", { user: limits.logId(args.uid) });
    return await limits.admitCall(args);
  }
}

/** Constant-time string comparison for shared secrets. */
function secretsMatch(provided, expected) {
  const a = Buffer.from(String(provided));
  const b = Buffer.from(String(expected));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

const AI_RUNTIME = {
  timeoutSeconds: 120,
  memory: "512MB",
  // Bound to Secret Manager. Set/update with:
  //   firebase functions:secrets:set GEMINI_API_KEY
  // then redeploy. Never hardcode a fallback key here.
  // REVENUECAT_SECRET_API_KEY backs the "just paid, webhook not in yet"
  // fallback in admitWithEntitlementFallback. Set it before deploying:
  //   firebase functions:secrets:set REVENUECAT_SECRET_API_KEY
  secrets: ["GEMINI_API_KEY", "REVENUECAT_SECRET_API_KEY"],
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
      admission = await admitWithEntitlementFallback({ db, admin, uid, token: context.auth.token, scanId: req.scanId, imageCount: req.images.length, label: req.label });
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
 * Every new user starts with 0 scans. A guest's 3 scans (claimGuestScans) and
 * a real account's free scans (finalizeAccountUpgrade) are granted ONCE PER
 * DEVICE by the server (see lib/device_grants.js), so signing out and back in
 * as a guest, or with a new e-mail, on the same phone gets nothing more.
 * Matches the client's _ensureUserDocumentExists, so both paths agree on
 * defaults regardless of which one wins the race to create the document.
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
      scansRemaining: 0,
      avatarUrl: user.photoURL || "",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
});

/**
 * Callable Cloud Function: finalizeAccountUpgrade
 *
 * Called right after a guest links a real credential (email, Google, or
 * Apple) or signs in. Moves the account to the Free Plan and grants the free
 * scans ONCE PER DEVICE (the app sends a device id; only its hash is kept),
 * server-side, since clients are never allowed to write scansRemaining (see
 * firestore.rules). Idempotent; never touches a premium account.
 */
exports.finalizeAccountUpgrade = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "The function must be called while authenticated."
    );
  }

  const deviceId = data && typeof data.deviceId === "string" ? data.deviceId : null;
  const result = await deviceGrants.claimFreeScans({
    db,
    admin,
    uid: context.auth.uid,
    token: context.auth.token,
    deviceId,
  });
  logEvent("free_scans_claim", {
    user: limits.logId(context.auth.uid),
    granted: result.granted,
    usedOnDevice: result.alreadyUsedOnDevice,
    invalidDevice: result.invalidDevice,
    alreadyClaimed: result.alreadyClaimed,
  });

  return { success: true, ...result };
});

/**
 * Callable Cloud Function: claimGuestScans
 *
 * Called by the app right after "Continue as guest". Grants the 3 guest scans
 * once per device (the app sends a device id; only its hash is kept).
 */
exports.claimGuestScans = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "The function must be called while authenticated."
    );
  }
  const deviceId = data && typeof data.deviceId === "string" ? data.deviceId : null;
  const result = await deviceGrants.claimGuestScans({
    db,
    admin,
    uid: context.auth.uid,
    token: context.auth.token,
    deviceId,
  });
  logEvent("guest_scans_claim", {
    user: limits.logId(context.auth.uid),
    granted: result.granted,
    usedOnDevice: result.alreadyUsedOnDevice,
    invalidDevice: result.invalidDevice,
    alreadyClaimed: result.alreadyClaimed,
  });
  return { success: true, ...result };
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
    if (!secretsMatch(providedSecret, expectedSecret)) {
      console.error("[revenueCatWebhook] Rejected request with invalid/missing Authorization header.");
      return res.status(401).send("Unauthorized");
    }

    const event = req.body && req.body.event;
    if (!event) {
      return res.status(400).send("Missing event data");
    }

    const { writes, note } = revenuecat.planWebhookUpdates(event);
    if (note) {
      logEvent(`revenuecat_webhook_${note}`, { eventType: event.type }, note === "unhandled" ? "WARNING" : "INFO");
    }
    await Promise.all(
      writes.map(([uid, fields]) =>
        db.collection("users").doc(uid).set(
          { ...fields, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true }
        )
      )
    );

    return res.status(200).json({ received: true });
  } catch (err) {
    console.error("Webhook processing error:", err);
    return res.status(500).send(err.message);
  }
});

const CLOUDINARY_ROOT_FOLDER = cloudinary.ROOT_FOLDER;

/**
 * Callable Cloud Function: signCloudinaryUploads
 *
 * Returns one upload signature per evidence photo of a scan, so the app
 * uploads with signed requests instead of an unsigned preset shipped in the
 * binary (Guideline 1.6). The server picks the folder and public_id
 * (`{uid}_{scanId}_{evidenceId}`), so the caller can only ever write under
 * its own uid - the same prefix deleteScanAssets/deleteAccount remove.
 *
 * Request:  { scanId, evidenceIds: [string] }
 * Response: { cloudName, apiKey, folder, timestamp, uploads: { id: { publicId, signature } } }
 */
exports.signCloudinaryUploads = functions
  .runWith({
    secrets: ["CLOUDINARY_CLOUD_NAME", "CLOUDINARY_API_KEY", "CLOUDINARY_API_SECRET"],
    enforceAppCheck: ENFORCE_APP_CHECK,
  })
  .https.onCall(async (data, context) => {
    requireAuth(context);
    const cloudName = process.env.CLOUDINARY_CLOUD_NAME;
    const apiKey = process.env.CLOUDINARY_API_KEY;
    const apiSecret = process.env.CLOUDINARY_API_SECRET;
    if (!cloudName || !apiKey || !apiSecret) {
      logEvent("cloudinary_sign_unconfigured", {}, "ERROR");
      throw new functions.https.HttpsError("unavailable", "Photo storage is not available right now.");
    }
    try {
      const plan = cloudinary.planSignedUploads({
        uid: context.auth.uid,
        scanId: data && data.scanId,
        evidenceIds: data && data.evidenceIds,
        apiSecret,
      });
      return { cloudName, apiKey, ...plan };
    } catch (e) {
      throw httpsErrorFor(e);
    }
  });

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

  // Unused free scans go back to this phone's ledger before the account goes.
  try {
    await deviceGrants.releaseOnDelete({ db, uid });
  } catch (e) {
    console.error("[deleteAccount] device ledger release error:", e);
  }

  // users/{uid} with all subcollections (any size), rate_limits and scan_sessions.
  try {
    await accountData.deleteAccountData({ db, uid });
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

/**
 * Scheduled housekeeping: removes guest ("Continue as guest") sign-ins that
 * have not been used for 30 days.
 *
 * Guests keep nothing in the app, so an anonymous Firebase user that nobody
 * has opened for a month is only clutter. Rules (see lib/anonymous_cleanup.js,
 * unit tested): only users with no sign-in provider, email or phone; never a
 * paying user; the user's Firestore data goes first and the Auth user is only
 * deleted when that worked. A run handles at most 2000 users; the rest waits
 * for the next night.
 *
 * Set ANON_CLEANUP_DRY_RUN=true in functions/.env to only log what it would
 * delete.
 */
exports.cleanupAnonymousUsers = functions
  .runWith({
    timeoutSeconds: 540,
    memory: "256MB",
    secrets: ["CLOUDINARY_CLOUD_NAME", "CLOUDINARY_API_KEY", "CLOUDINARY_API_SECRET"],
  })
  .pubsub.schedule("every day 03:00")
  .timeZone("Etc/UTC")
  .onRun(async () => {
    const dryRun = process.env.ANON_CLEANUP_DRY_RUN === "true";

    async function deleteSubcollection(userRef, name) {
      let removed = 0;
      for (;;) {
        const snap = await userRef.collection(name).limit(400).get();
        if (snap.empty) return removed;
        const batch = db.batch();
        snap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        removed += snap.size;
      }
    }

    const summary = await anonymousCleanup.cleanupAnonymousUsers({
      dryRun,
      maxAgeDays: 30,
      listPage: async (pageToken) => {
        const page = await admin.auth().listUsers(1000, pageToken);
        return { users: page.users, pageToken: page.pageToken };
      },
      isPremium: async (uid) => {
        const doc = await db.collection("users").doc(uid).get();
        return doc.exists && doc.data().isPremium === true;
      },
      deleteUserData: async (uid) => {
        const userRef = db.collection("users").doc(uid);
        const reports = await deleteSubcollection(userRef, "reports");
        await deleteSubcollection(userRef, "collection");
        await deleteSubcollection(userRef, "categories");
        await userRef.delete();
        await db.collection("rate_limits").doc(uid).delete();
        await accountData.deleteQueryInPages(db, db.collection("scan_sessions").where("uid", "==", uid));
        // Only older guests ever saved reports (and so uploaded photos).
        if (reports > 0) await deleteCloudinaryAssetsByPrefix(`${uid}_`);
      },
      deleteAuthUsers: async (uids) => {
        const res = await admin.auth().deleteUsers(uids);
        return { successCount: res.successCount, failureCount: res.failureCount };
      },
    });

    logEvent("anonymous_cleanup_done", summary, summary.authFailures || summary.dataFailures ? "WARNING" : "INFO");
    return null;
  });
