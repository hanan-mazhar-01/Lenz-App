"use strict";

/**
 * Request validation, per-user rate limits and scan-credit charging for the
 * AI callables. Pure decision functions (unit-tested) plus one Firestore
 * transaction helper.
 *
 * Billing no longer trusts the client's request label. A scan session
 * (client scanId, or a 15-minute window for old clients that send none) is
 * charged once, on its first request that carries two or more photos (the
 * final combined analysis) or when it exceeds FREE_CALLS_PER_SESSION calls,
 * whichever comes first. Renaming labels or splitting requests no longer
 * avoids the charge; daily caps bound what one account can use.
 */

const crypto = require("crypto");

const LIMITS = {
  maxImages: 16,
  maxImageChars: 3500000, // base64 characters per image (~2.6 MB JPEG)
  maxTotalImageChars: 9500000, // stays under the 10 MB callable request limit
  maxPromptChars: 100000,
  maxSchemaChars: 30000,
  maxOutputTokens: 8192,
  perMinute: 40,
  perDayGuest: 150,
  perDayUser: 500,
  freeCallsPerSession: 12,
  sessionWindowMs: 15 * 60 * 1000,
  sessionTtlDays: 7,
};

const IMAGE_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);
const THINKING = new Set(["minimal", "low", "medium", "high"]);

class RequestError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code; // invalid-argument | resource-exhausted
  }
}

/** Validates and normalises a generateStructuredContent payload. Throws RequestError. */
function validateGenerateRequest(data) {
  const d = data || {};
  if (typeof d.prompt !== "string" || !d.prompt.trim()) {
    throw new RequestError("invalid-argument", "The function must be called with a valid 'prompt' string.");
  }
  if (d.prompt.length > LIMITS.maxPromptChars) throw new RequestError("invalid-argument", "Prompt is too long.");

  const images = d.inlineImages == null ? [] : d.inlineImages;
  if (!Array.isArray(images)) throw new RequestError("invalid-argument", "inlineImages must be a list.");
  if (images.length > LIMITS.maxImages) throw new RequestError("invalid-argument", `At most ${LIMITS.maxImages} images per request.`);
  let total = 0;
  const cleanImages = images.map((img) => {
    const inline = img && (img.inline_data || img.inlineData);
    const mime = inline && (inline.mime_type || inline.mimeType);
    const b64 = inline && inline.data;
    if (!inline || !IMAGE_MIME.has(mime) || typeof b64 !== "string" || !b64.length) {
      throw new RequestError("invalid-argument", "Each image must be inline JPEG, PNG or WebP data.");
    }
    if (b64.length > LIMITS.maxImageChars) throw new RequestError("invalid-argument", "An image is too large.");
    total += b64.length;
    return { inline_data: { mime_type: mime, data: b64 } };
  });
  if (total > LIMITS.maxTotalImageChars) throw new RequestError("invalid-argument", "The images are too large in total.");

  let schema = null;
  if (d.responseSchema && typeof d.responseSchema === "object") {
    if (JSON.stringify(d.responseSchema).length > LIMITS.maxSchemaChars) {
      throw new RequestError("invalid-argument", "responseSchema is too large.");
    }
    schema = d.responseSchema;
  }

  const requested = Number.isInteger(d.maxOutputTokens) ? d.maxOutputTokens : 2048;
  return {
    prompt: d.prompt,
    images: cleanImages,
    imageChars: total,
    responseSchema: schema,
    maxOutputTokens: Math.max(64, Math.min(requested, LIMITS.maxOutputTokens)),
    thinkingLevel: THINKING.has(d.thinkingLevel) ? d.thinkingLevel : null,
    label: typeof d.requestTypeLabel === "string" ? d.requestTypeLabel.slice(0, 80) : "unlabelled",
    scanId: validScanId(d.scanId),
  };
}

function validScanId(v) {
  return typeof v === "string" && /^[A-Za-z0-9_-]{6,80}$/.test(v) ? v : null;
}

function sessionKey(uid, scanId, nowMs) {
  return scanId ? `${uid}_${scanId}` : `${uid}_legacy_${Math.floor(nowMs / LIMITS.sessionWindowMs)}`;
}

function dayString(nowMs) {
  return new Date(nowMs).toISOString().slice(0, 10);
}

/**
 * Decides the rate-limit update for one call. Returns the new counters or
 * throws RequestError("resource-exhausted").
 */
function nextRateState(prev, { nowMs, isGuest }) {
  const p = prev || {};
  const minute = Math.floor(nowMs / 60000);
  const day = dayString(nowMs);
  const minuteCount = (p.minute === minute ? p.minuteCount || 0 : 0) + 1;
  const dayCount = (p.day === day ? p.dayCount || 0 : 0) + 1;
  if (minuteCount > LIMITS.perMinute) throw new RequestError("resource-exhausted", "Too many requests. Please wait a minute.");
  if (dayCount > (isGuest ? LIMITS.perDayGuest : LIMITS.perDayUser)) {
    throw new RequestError("resource-exhausted", "Daily analysis limit reached. Please try again tomorrow.");
  }
  return { minute, minuteCount, day, dayCount };
}

/** Whether this call makes the session chargeable (label-independent). */
function sessionChargeDue(session, { imageCount }) {
  if (session.charged) return false;
  return imageCount >= 2 || session.calls > LIMITS.freeCallsPerSession;
}

/**
 * One transaction: rate limit, session bookkeeping and (for guests) the
 * scan-credit check/decrement. Returns { charged, sessionRef }.
 */
async function admitCall({ db, admin, uid, token, scanId, imageCount, nowMs = Date.now() }) {
  const isGuest = Boolean(token && token.firebase && token.firebase.sign_in_provider === "anonymous");
  const userRef = db.collection("users").doc(uid);
  const rateRef = db.collection("rate_limits").doc(uid);
  const sessionRef = db.collection("scan_sessions").doc(sessionKey(uid, scanId, nowMs));
  let charged = false;

  await db.runTransaction(async (tx) => {
    const [userDoc, rateDoc, sessionDoc] = await Promise.all([tx.get(userRef), tx.get(rateRef), tx.get(sessionRef)]);
    const rate = nextRateState(rateDoc.exists ? rateDoc.data() : null, { nowMs, isGuest });

    const prev = sessionDoc.exists ? sessionDoc.data() : { calls: 0, charged: false };
    const session = {
      calls: (prev.calls || 0) + 1,
      charged: Boolean(prev.charged),
    };

    let userUpdate = null;
    if (sessionChargeDue(session, { imageCount })) {
      session.charged = true;
      charged = true;
      // Credits apply to non-premium accounts (both guests and free registered users).
      const data = userDoc.exists ? userDoc.data() : {};
      const isPremium = Boolean(data.isPremium);
      const remaining = typeof data.scansRemaining === "number" ? data.scansRemaining : 3;
      if (!isPremium) {
        if (remaining <= 0) throw new RequestError("resource-exhausted", "No scan credits remaining. Please upgrade to premium.");
        userUpdate = { scansRemaining: remaining - 1, lastScanAt: admin.firestore.FieldValue.serverTimestamp() };
        if (!userDoc.exists) {
          userUpdate = {
            name: (token && token.name) || (isGuest ? "Guest Collector" : "Collector"),
            email: (token && token.email) || "",
            planName: isGuest ? "Guest Plan" : "Free Plan",
            isPremium: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            ...userUpdate,
          };
        }
      } else {
        charged = false; // nothing to refund for premium accounts
      }
    }

    tx.set(rateRef, rate, { merge: true });
    tx.set(sessionRef, {
      uid,
      scanId: scanId || null,
      ...session,
      lastAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + LIMITS.sessionTtlDays * 86400000),
      ...(sessionDoc.exists ? {} : { createdAt: admin.firestore.FieldValue.serverTimestamp() }),
    }, { merge: true });
    if (userUpdate) tx.set(userRef, userUpdate, { merge: true });
  });

  return { charged, sessionRef, userRef, isGuest };
}

/** Gives the credit back (and un-marks the session) after a failed AI call. */
async function refundCall({ db, admin, sessionRef, userRef }) {
  await db.runTransaction(async (tx) => {
    tx.set(userRef, { scansRemaining: admin.firestore.FieldValue.increment(1) }, { merge: true });
    tx.set(sessionRef, { charged: false }, { merge: true });
  });
}

/** Stable, non-reversible id for logs (never log raw uids with content). */
function logId(uid) {
  return crypto.createHash("sha256").update(String(uid)).digest("hex").slice(0, 12);
}

module.exports = {
  LIMITS,
  RequestError,
  validateGenerateRequest,
  validScanId,
  sessionKey,
  nextRateState,
  sessionChargeDue,
  admitCall,
  refundCall,
  logId,
};
