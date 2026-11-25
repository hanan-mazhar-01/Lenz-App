"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const rc = require("../lib/revenuecat");

const NOW = Date.parse("2026-11-25T12:00:00Z");
const DAY = 86400000;
const fakeFetch = (status, body) => async () => ({ ok: status === 200, status, json: async () => body });
const subscriber = (pro) => ({ subscriber: { entitlements: pro ? { pro } : {} } });

test("active, expired, lifetime and grace-period entitlements", () => {
  assert.equal(rc.isEntitlementActive({ expires_date: "2026-12-25T00:00:00Z" }, NOW), true);
  assert.equal(rc.isEntitlementActive({ expires_date: "2026-11-01T00:00:00Z" }, NOW), false);
  assert.equal(rc.isEntitlementActive({ expires_date: null }, NOW), true);
  assert.equal(
    rc.isEntitlementActive({ expires_date: "2026-11-20T00:00:00Z", grace_period_expires_date: "2026-11-30T00:00:00Z" }, NOW),
    true
  );
  assert.equal(rc.isEntitlementActive(undefined, NOW), false);
});

test("getActiveEntitlement returns the expiry of the pro entitlement", async () => {
  const active = subscriber({ expires_date: "2026-12-25T00:00:00Z" });
  assert.deepEqual(
    await rc.getActiveEntitlement("u1", { apiKey: "sk_x", fetchImpl: fakeFetch(200, active), nowMs: NOW }),
    { active: true, expiresAtMs: Date.parse("2026-12-25T00:00:00Z") }
  );
  const lifetime = subscriber({ expires_date: null });
  assert.deepEqual(
    await rc.getActiveEntitlement("u1", { apiKey: "sk_x", fetchImpl: fakeFetch(200, lifetime), nowMs: NOW }),
    { active: true, expiresAtMs: null }
  );
  const none = await rc.getActiveEntitlement("u1", { apiKey: "sk_x", fetchImpl: fakeFetch(200, subscriber(null)), nowMs: NOW });
  assert.equal(none.active, false);
});

test("getActiveEntitlement fails closed and never throws", async () => {
  const active = subscriber({ expires_date: null });
  assert.equal((await rc.getActiveEntitlement("u1", { apiKey: "", fetchImpl: fakeFetch(200, active) })).active, false);
  assert.equal((await rc.getActiveEntitlement("u1", { apiKey: "sk_x", fetchImpl: fakeFetch(500, active) })).active, false);
  const boom = async () => { throw new Error("network down"); };
  assert.equal((await rc.getActiveEntitlement("u1", { apiKey: "sk_x", fetchImpl: boom })).active, false);
});

test("sends the secret key and escapes the uid", async () => {
  let seen;
  const spy = async (url, opts) => { seen = { url, opts }; return { ok: true, json: async () => subscriber(null) }; };
  await rc.getActiveEntitlement("a/b", { apiKey: "sk_x", fetchImpl: spy });
  assert.equal(seen.url, "https://api.revenuecat.com/v1/subscribers/a%2Fb");
  assert.equal(seen.opts.headers.Authorization, "Bearer sk_x");
});

// ── Webhook planning ─────────────────────────────────────────────────────

const ev = (type, extra = {}) => ({ type, app_user_id: "u1", ...extra });
const only = (plan) => {
  assert.equal(plan.writes.length, 1);
  assert.equal(plan.writes[0][0], "u1");
  return plan.writes[0][1];
};

test("purchase and renewal grant Pro until the event's expiry, with no fake credits", () => {
  for (const type of ["INITIAL_PURCHASE", "RENEWAL", "PRODUCT_CHANGE", "UNCANCELLATION", "SUBSCRIPTION_EXTENDED"]) {
    const f = only(rc.planWebhookUpdates(ev(type, { expiration_at_ms: NOW + 30 * DAY }), NOW));
    assert.equal(f.isPremium, true, type);
    assert.equal(f.planName, "Lenz Pro");
    assert.equal(f.premiumExpiresAtMs, NOW + 30 * DAY);
    assert.equal("scansRemaining" in f, false, "no 9999 credits");
  }
});

test("CANCELLATION (auto-renew off) keeps Pro until the paid period ends", () => {
  const f = only(rc.planWebhookUpdates(ev("CANCELLATION", { expiration_at_ms: NOW + 10 * DAY }), NOW));
  assert.equal(f.isPremium, true);
  assert.equal(f.premiumExpiresAtMs, NOW + 10 * DAY);
});

test("a refund (CANCELLATION already expired), EXPIRATION and REFUND remove Pro and free credits", () => {
  for (const e of [
    ev("CANCELLATION", { expiration_at_ms: NOW - 1000, cancel_reason: "CUSTOMER_SUPPORT" }),
    ev("EXPIRATION", { expiration_at_ms: NOW - 1000 }),
    ev("REFUND"),
  ]) {
    const f = only(rc.planWebhookUpdates(e, NOW));
    assert.equal(f.isPremium, false, e.type);
    assert.equal(f.scansRemaining, 0);
    assert.equal(f.premiumExpiresAtMs, null);
  }
});

test("BILLING_ISSUE keeps Pro through the grace period, otherwise changes nothing", () => {
  const f = only(rc.planWebhookUpdates(ev("BILLING_ISSUE", { expiration_at_ms: NOW - DAY, grace_period_expiration_at_ms: NOW + 6 * DAY }), NOW));
  assert.equal(f.isPremium, true);
  assert.equal(f.premiumExpiresAtMs, NOW + 6 * DAY);
  assert.deepEqual(rc.planWebhookUpdates(ev("BILLING_ISSUE"), NOW).writes, []);
});

test("TRANSFER moves Pro between real users and skips RevenueCat anonymous ids", () => {
  const plan = rc.planWebhookUpdates(
    { type: "TRANSFER", transferred_from: ["old", "$RCAnonymousID:abc"], transferred_to: ["new", "$RCAnonymousID:def"] },
    NOW
  );
  assert.deepEqual(plan.writes.map(([u, f]) => [u, f.isPremium]), [["new", true], ["old", false]]);
});

test("anonymous ids and unknown events write nothing", () => {
  assert.deepEqual(rc.planWebhookUpdates({ type: "RENEWAL", app_user_id: "$RCAnonymousID:x" }, NOW).writes, []);
  assert.equal(rc.planWebhookUpdates(ev("SOMETHING_NEW"), NOW).note, "unhandled");
  assert.equal(rc.planWebhookUpdates(ev("TEST"), NOW).note, "ignored");
});
