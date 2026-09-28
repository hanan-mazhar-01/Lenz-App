"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const limits = require("../lib/limits");
const { makeFake } = require("./fake_firestore");

const img = (n = 10) => ({ inline_data: { mime_type: "image/jpeg", data: "A".repeat(n) } });

test("requests are validated and bounded", () => {
  const ok = limits.validateGenerateRequest({ prompt: "hi", inlineImages: [img()], maxOutputTokens: 999999, thinkingLevel: "low", scanId: "scan_123456" });
  assert.equal(ok.maxOutputTokens, limits.LIMITS.maxOutputTokens);
  assert.equal(ok.thinkingLevel, "low");
  assert.equal(ok.scanId, "scan_123456");
  assert.equal(limits.validateGenerateRequest({ prompt: "hi", thinkingLevel: "ultra" }).thinkingLevel, null);
  assert.equal(limits.validateGenerateRequest({ prompt: "hi", scanId: "../etc" }).scanId, null);
  assert.throws(() => limits.validateGenerateRequest({}), /prompt/);
  assert.throws(() => limits.validateGenerateRequest({ prompt: "x", inlineImages: [{ inline_data: { mime_type: "text/html", data: "a" } }] }), /JPEG/);
  assert.throws(() => limits.validateGenerateRequest({ prompt: "x", inlineImages: Array.from({ length: 17 }, () => img()) }), /At most/);
  assert.throws(() => limits.validateGenerateRequest({ prompt: "x", inlineImages: [img(limits.LIMITS.maxImageChars + 1)] }), /too large/);
  assert.throws(() => limits.validateGenerateRequest({ prompt: "x", inlineImages: [img(3400000), img(3400000), img(3400000)] }), /in total/);
});

test("rate limits roll over per minute and per day", () => {
  const t0 = Date.UTC(2026, 8, 27, 10, 0, 0);
  let s = null;
  for (let i = 0; i < limits.LIMITS.perMinute; i++) s = limits.nextRateState(s, { nowMs: t0, isGuest: true });
  assert.throws(() => limits.nextRateState(s, { nowMs: t0, isGuest: true }), /wait a minute/);
  s = limits.nextRateState(s, { nowMs: t0 + 61000, isGuest: true });
  assert.equal(s.minuteCount, 1);
  const tomorrow = limits.nextRateState({ ...s, dayCount: 9999 }, { nowMs: t0 + 86400000, isGuest: true });
  assert.equal(tomorrow.dayCount, 1);
  assert.throws(() => limits.nextRateState({ day: s.day, dayCount: limits.LIMITS.perDayGuest }, { nowMs: t0 + 120000, isGuest: true }), /Daily/);
});

test("charging does not depend on the request label", () => {
  assert.equal(limits.sessionChargeDue({ calls: 1, charged: false }, { imageCount: 1 }), false);
  assert.equal(limits.sessionChargeDue({ calls: 1, charged: false }, { imageCount: 7 }), true);
  assert.equal(limits.sessionChargeDue({ calls: limits.LIMITS.freeCallsPerSession + 1, charged: false }, { imageCount: 0 }), true);
  assert.equal(limits.sessionChargeDue({ calls: 30, charged: true }, { imageCount: 7 }), false);
  const t = Date.UTC(2026, 8, 27, 10, 0, 0);
  assert.equal(limits.sessionKey("u", null, t), limits.sessionKey("u", null, t + 60000));
  assert.notEqual(limits.sessionKey("u", null, t), limits.sessionKey("u", null, t + limits.LIMITS.sessionWindowMs));
});

test("a guest scan is charged once, at the multi-photo call, and refunded on failure", async () => {
  const { db, admin } = makeFake();
  db.store.set("users/g1", { scansRemaining: 3, isPremium: false });
  const token = { firebase: { sign_in_provider: "anonymous" } };
  const call = (imageCount) => limits.admitCall({ db, admin, uid: "g1", token, scanId: "scan_abcdef", imageCount });
  assert.equal((await call(1)).charged, false);
  assert.equal((await call(1)).charged, false);
  const final = await call(7);
  assert.equal(final.charged, true);
  assert.equal(db.store.get("users/g1").scansRemaining, 2);
  assert.equal((await call(7)).charged, false, "only once per session");
  await limits.refundCall({ db, admin, sessionRef: final.sessionRef, userRef: final.userRef });
  assert.equal(db.store.get("users/g1").scansRemaining, 3);
});

test("many single-photo calls in one session are charged too", async () => {
  const { db, admin } = makeFake();
  db.store.set("users/g2", { scansRemaining: 1 });
  const token = { firebase: { sign_in_provider: "anonymous" } };
  let charged = 0;
  for (let i = 0; i < limits.LIMITS.freeCallsPerSession + 1; i++) {
    if ((await limits.admitCall({ db, admin, uid: "g2", token, scanId: "scan_zzzzzz", imageCount: 1 })).charged) charged++;
  }
  assert.equal(charged, 1);
  assert.equal(db.store.get("users/g2").scansRemaining, 0);
  await assert.rejects(
    limits.admitCall({ db, admin, uid: "g2", token, scanId: "scan_other1", imageCount: 7 }),
    /No scan credits/,
  );
});

test("signed-in free accounts keep the current uncapped policy", async () => {
  const { db, admin } = makeFake();
  db.store.set("users/u1", { scansRemaining: 0 });
  const r = await limits.admitCall({ db, admin, uid: "u1", token: { firebase: { sign_in_provider: "google.com" } }, scanId: "scan_signed", imageCount: 7 });
  assert.equal(r.charged, false);
  assert.equal(db.store.get("users/u1").scansRemaining, 0);
});
