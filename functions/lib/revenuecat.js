/**
 * RevenueCat helpers for the server's view of "is this user Pro".
 *
 * users/{uid} carries `isPremium` plus `premiumExpiresAtMs` (see
 * limits.premiumActive). Two sources keep them current:
 *  - the RevenueCat webhook (planWebhookUpdates), and
 *  - a direct lookup (getActiveEntitlement) used when a scan would otherwise
 *    be refused for "no credits", so a user who has just paid is never
 *    blocked because the webhook is late, misconfigured or not set up.
 *    The client uses the Firebase uid as its RevenueCat app user id.
 *
 * The lookup needs the RevenueCat *secret* API key (sk_...), bound from
 * Secret Manager:
 *   firebase functions:secrets:set REVENUECAT_SECRET_API_KEY
 */

const ENTITLEMENT_ID = "pro";
const API_BASE = "https://api.revenuecat.com/v1/subscribers/";
const PLAN_PRO = "Lenz Pro";
const PLAN_FREE = "Free Plan";

/**
 * When the `pro` entitlement from a v1 subscriber payload stops giving
 * access: null for lifetime/non-expiring, otherwise ms since epoch
 * (the later of expiry and any billing grace period). NaN if unreadable.
 */
function entitlementEndMs(entitlement) {
  if (entitlement.expires_date == null) return null;
  const expires = Date.parse(entitlement.expires_date);
  const grace = entitlement.grace_period_expires_date ? Date.parse(entitlement.grace_period_expires_date) : NaN;
  if (Number.isNaN(expires)) return NaN;
  return Number.isNaN(grace) ? expires : Math.max(expires, grace);
}

/** True when `entitlement` from a v1 subscriber payload is active at `nowMs`. */
function isEntitlementActive(entitlement, nowMs = Date.now()) {
  if (!entitlement) return false;
  const end = entitlementEndMs(entitlement);
  if (end === null) return true;
  return !Number.isNaN(end) && end > nowMs;
}

/**
 * Asks RevenueCat whether `uid` has an active `pro` entitlement.
 * Returns { active, expiresAtMs } (expiresAtMs null = no expiry). Never
 * throws: any failure (no key, network, non-200) is { active: false }, so
 * the caller falls back to its normal "no credits" answer.
 */
async function getActiveEntitlement(uid, { apiKey, fetchImpl = fetch, timeoutMs = 5000, nowMs = Date.now() } = {}) {
  const inactive = { active: false, expiresAtMs: null };
  if (!apiKey || !uid) return inactive;
  try {
    const res = await fetchImpl(API_BASE + encodeURIComponent(uid), {
      headers: { Authorization: `Bearer ${apiKey}`, Accept: "application/json" },
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!res.ok) return inactive;
    const body = await res.json();
    const ent = body && body.subscriber && body.subscriber.entitlements && body.subscriber.entitlements[ENTITLEMENT_ID];
    if (!isEntitlementActive(ent, nowMs)) return inactive;
    return { active: true, expiresAtMs: entitlementEndMs(ent) };
  } catch (_) {
    return inactive;
  }
}

/** Firestore fields for a user who has Pro until `expiresAtMs` (null = no expiry). */
function proFields(expiresAtMs) {
  return { isPremium: true, planName: PLAN_PRO, premiumExpiresAtMs: expiresAtMs == null ? null : expiresAtMs };
}

/**
 * Fields for a user who no longer has Pro. The free balance goes to 0:
 * free scans were used up before buying, and older grants stored 9999.
 */
function freeFields() {
  return { isPremium: false, planName: PLAN_FREE, premiumExpiresAtMs: null, scansRemaining: 0 };
}

const isRealUid = (id) => typeof id === "string" && id.length > 0 && !id.startsWith("$RCAnonymousID:");

/** ms from a webhook event field, or null when absent/unreadable. */
function eventMs(v) {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

/**
 * Decides what a RevenueCat webhook event means for users/{uid} docs.
 * Pure (no I/O) so it can be unit tested. Returns { writes: [[uid, fields]],
 * note } where note is "ignored" / "unhandled" for events that change
 * nothing.
 *
 * Access always follows the event's own expiration_at_ms rather than its
 * type: CANCELLATION only means auto-renew was turned off (the user keeps
 * Pro until the paid period ends), while a refund arrives as a
 * CANCELLATION whose expiration is already in the past.
 */
function planWebhookUpdates(event, nowMs = Date.now()) {
  const type = event && event.type;

  if (type === "TRANSFER") {
    // No expiry on transfer events; the next renewal/expiration event (or
    // the direct lookup once credits run out) settles it.
    const to = (Array.isArray(event.transferred_to) ? event.transferred_to : []).filter(isRealUid);
    const from = (Array.isArray(event.transferred_from) ? event.transferred_from : []).filter(isRealUid);
    return { writes: [...to.map((u) => [u, proFields(null)]), ...from.map((u) => [u, freeFields()])] };
  }

  const uid = event && event.app_user_id;
  if (!isRealUid(uid)) return { writes: [], note: "ignored" };

  const expiresAt = eventMs(event.expiration_at_ms);
  const proUntil = (end) => (end !== null && end <= nowMs ? [[uid, freeFields()]] : [[uid, proFields(end)]]);

  switch (type) {
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "PRODUCT_CHANGE":
    case "UNCANCELLATION":
    case "SUBSCRIPTION_EXTENDED":
    case "TEMPORARY_ENTITLEMENT_GRANT":
    case "NON_RENEWING_PURCHASE":
    case "CANCELLATION":
      return { writes: proUntil(expiresAt) };
    case "BILLING_ISSUE": {
      // Apple keeps access during the billing grace period, if one is set.
      const grace = eventMs(event.grace_period_expiration_at_ms);
      if (grace === null) return { writes: [], note: "ignored" };
      return { writes: proUntil(expiresAt === null ? grace : Math.max(expiresAt, grace)) };
    }
    case "EXPIRATION":
    case "REFUND":
      return { writes: [[uid, freeFields()]] };
    case "SUBSCRIPTION_PAUSED":
    case "TEST":
      return { writes: [], note: "ignored" };
    default:
      return { writes: [], note: "unhandled" };
  }
}

module.exports = {
  ENTITLEMENT_ID,
  PLAN_PRO,
  isEntitlementActive,
  getActiveEntitlement,
  planWebhookUpdates,
  proFields,
};
