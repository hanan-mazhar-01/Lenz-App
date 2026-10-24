"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { makeFake } = require("./fake_firestore");
const g = require("../lib/device_grants");

const DEVICE = "android-id-1234567890";

function setup() {
  const { db, admin } = makeFake();
  return { db, admin };
}
const claim = (env, uid, ...rest) =>
  g.claimFreeScans({ db: env.db, admin: env.admin, uid, token: { email: `${uid}@x.com` }, deviceId: rest.length ? rest[0] : DEVICE });
const balance = (env, uid) => env.db.store.get(`users/${uid}`).scansRemaining;

test("the first account on a device gets the free scans", async () => {
  const env = setup();
  const r = await claim(env, "a");
  assert.equal(r.granted, g.FREE_PLAN_SCANS);
  assert.equal(r.alreadyUsedOnDevice, false);
  assert.equal(balance(env, "a"), 3);
});

test("a second account on the same device gets none, however often it is created", async () => {
  const env = setup();
  await claim(env, "a");
  for (const uid of ["b", "c", "d"]) {
    const r = await claim(env, uid);
    assert.equal(r.granted, 0);
    assert.equal(r.alreadyUsedOnDevice, true);
    assert.equal(balance(env, uid), 0);
  }
});

test("a different device is a different grant", async () => {
  const env = setup();
  await claim(env, "a", "device-one-12345");
  const r = await claim(env, "b", "device-two-12345");
  assert.equal(r.granted, 3);
});

test("signing in again to the same account does not top it up", async () => {
  const env = setup();
  await claim(env, "a");
  env.db.store.set("users/a", { ...env.db.store.get("users/a"), scansRemaining: 1 });
  const r = await claim(env, "a");
  assert.equal(r.alreadyClaimed, true);
  assert.equal(balance(env, "a"), 1);
});

test("the same account on the device that already granted it is not 'used elsewhere'", async () => {
  const env = setup();
  await claim(env, "a");
  // flag lost / replayed for the same uid: still no second grant
  env.db.store.set("users/a", { ...env.db.store.get("users/a"), freeScansClaimed: false, upgradedAt: undefined });
  const r = await claim(env, "a");
  assert.equal(r.alreadyUsedOnDevice, false);
  assert.equal(r.granted, 3);
  assert.equal(balance(env, "a"), 3, "never 6");
});

test("a guest who links keeps unused guest scans, even when the device grant is spent", async () => {
  const env = setup();
  await claim(env, "first");
  env.db.store.set("users/guest", { planName: "Guest Plan", scansRemaining: 2, isPremium: false });
  const r = await claim(env, "guest");
  assert.equal(r.granted, 0);
  assert.equal(balance(env, "guest"), 2);
  assert.equal(env.db.store.get("users/guest").planName, "Free Plan");
});

test("a guest who links on a fresh device gets the free scans (not added on top of 3)", async () => {
  const env = setup();
  env.db.store.set("users/guest", { planName: "Guest Plan", scansRemaining: 3, isPremium: false });
  const r = await claim(env, "guest");
  assert.equal(r.granted, 3);
  assert.equal(balance(env, "guest"), 3);
});

test("a missing or malformed device id grants nothing", async () => {
  const env = setup();
  for (const bad of [undefined, null, "", "short", 42, "x".repeat(300)]) {
    const uid = `u${String(bad).length}${typeof bad}`;
    const r = await claim(env, uid, bad);
    assert.equal(r.granted, 0, String(bad));
    assert.equal(r.invalidDevice, true);
  }
  assert.equal([...env.db.store.keys()].some((k) => k.startsWith("device_grants/")), false);
});

test("a premium account is left alone", async () => {
  const env = setup();
  env.db.store.set("users/p", { planName: "Lenz Pro", isPremium: true, scansRemaining: 9999 });
  const r = await claim(env, "p");
  assert.equal(r.alreadyClaimed, true);
  assert.equal(balance(env, "p"), 9999);
});

test("an account finalised by the older version (upgradedAt set) is not granted again", async () => {
  const env = setup();
  env.db.store.set("users/old", { planName: "Free Plan", scansRemaining: 0, upgradedAt: new Date() });
  const r = await claim(env, "old");
  assert.equal(r.alreadyClaimed, true);
  assert.equal(balance(env, "old"), 0);
});

test("only a hash of the device id is stored", async () => {
  const env = setup();
  await claim(env, "a");
  const keys = [...env.db.store.keys()].filter((k) => k.startsWith("device_grants/"));
  assert.equal(keys.length, 1);
  assert.equal(keys[0].includes(DEVICE), false);
  assert.match(keys[0], /^device_grants\/[0-9a-f]{64}$/);
});

// ---------------------------------------------------------------- guests
const guestToken = { firebase: { sign_in_provider: "anonymous" } };
const claimGuest = (env, uid, ...rest) =>
  g.claimGuestScans({ db: env.db, admin: env.admin, uid, token: guestToken, deviceId: rest.length ? rest[0] : DEVICE });
function newGuest(env, uid) {
  env.db.store.set(`users/${uid}`, { planName: "Guest Plan", isPremium: false, scansRemaining: 0 });
}

test("the first guest on a device gets the guest scans", async () => {
  const env = setup();
  newGuest(env, "g1");
  const r = await claimGuest(env, "g1");
  assert.equal(r.granted, 3);
  assert.equal(balance(env, "g1"), 3);
});

test("a new guest on the same device (after signing out of an account) gets none", async () => {
  const env = setup();
  newGuest(env, "g1");
  await claimGuest(env, "g1");
  for (const uid of ["g2", "g3", "g4"]) {
    newGuest(env, uid);
    const r = await claimGuest(env, uid);
    assert.equal(r.granted, 0);
    assert.equal(r.alreadyUsedOnDevice, true);
    assert.equal(balance(env, uid), 0);
  }
});

test("a guest on another device gets the guest scans", async () => {
  const env = setup();
  newGuest(env, "g1");
  newGuest(env, "g2");
  await claimGuest(env, "g1", "device-one-12345");
  assert.equal((await claimGuest(env, "g2", "device-two-12345")).granted, 3);
});

test("claiming twice as the same guest does not give more", async () => {
  const env = setup();
  newGuest(env, "g1");
  await claimGuest(env, "g1");
  env.db.store.set("users/g1", { ...env.db.store.get("users/g1"), scansRemaining: 1 });
  const r = await claimGuest(env, "g1");
  assert.equal(r.alreadyClaimed, true);
  assert.equal(balance(env, "g1"), 1);
});

test("a guest with no readable device id gets nothing", async () => {
  const env = setup();
  newGuest(env, "g1");
  const r = await claimGuest(env, "g1", "");
  assert.equal(r.granted, 0);
  assert.equal(r.invalidDevice, true);
});

test("guest scans and the account grant are separate: guest, then account, then guest again", async () => {
  const env = setup();
  newGuest(env, "g1");
  assert.equal((await claimGuest(env, "g1")).granted, 3);
  // the guest creates an account (same uid): the account gets its free scans once
  assert.equal((await claim(env, "g1")).granted, 3);
  // signs out and tries guest again: no more guest scans
  newGuest(env, "g2");
  assert.equal((await claimGuest(env, "g2")).granted, 0);
  // and a second new e-mail on the device gets no account grant either
  assert.equal((await claim(env, "acct2")).granted, 0);
});

test("a registered account is not treated as a guest", async () => {
  const env = setup();
  env.db.store.set("users/a", { planName: "Free Plan", scansRemaining: 0 });
  const r = await claimGuest(env, "a");
  assert.equal(r.alreadyClaimed, true);
  assert.equal(balance(env, "a"), 0);
});

// ------------------------------------------------- delete and re-create
const release = (env, uid) => g.releaseOnDelete({ db: env.db, uid });

test("delete then re-create on the same phone gives back only the unused scans", async () => {
  const env = setup();
  await claim(env, "a");
  env.db.store.set("users/a", { ...env.db.store.get("users/a"), scansRemaining: 2 }); // 1 used
  assert.deepEqual(await release(env, "a"), { released: true, remaining: 2 });
  env.db.store.delete("users/a");
  const r = await claim(env, "b");
  assert.equal(r.granted, 2);
  assert.equal(balance(env, "b"), 2);
});

test("deleting an account that used all its scans gives the next account none", async () => {
  const env = setup();
  await claim(env, "a");
  env.db.store.set("users/a", { ...env.db.store.get("users/a"), scansRemaining: 0 });
  await release(env, "a");
  const r = await claim(env, "b");
  assert.equal(r.granted, 0);
  assert.equal(r.alreadyUsedOnDevice, true);
});

test("delete, re-create, delete again keeps the same total (never more than 3)", async () => {
  const env = setup();
  await claim(env, "a");
  env.db.store.set("users/a", { ...env.db.store.get("users/a"), scansRemaining: 2 });
  await release(env, "a");
  await claim(env, "b");
  env.db.store.set("users/b", { ...env.db.store.get("users/b"), scansRemaining: 1 });
  await release(env, "b");
  const r = await claim(env, "c");
  assert.equal(r.granted, 1);
  // and the leftover is spent once: a fourth account gets nothing while c still holds it
  assert.equal((await claim(env, "d")).granted, 0);
});

test("deleting an account that does not hold the device's grant does not release it", async () => {
  const env = setup();
  await claim(env, "a"); // holds the grant
  await claim(env, "b"); // got 0, does not hold it
  env.db.store.set("users/b", { ...env.db.store.get("users/b"), scansRemaining: 3 });
  assert.deepEqual(await release(env, "b"), { released: false });
  assert.equal((await claim(env, "c")).granted, 0);
});

test("a premium account's delete does not carry scans over", async () => {
  const env = setup();
  await claim(env, "a");
  env.db.store.set("users/a", { ...env.db.store.get("users/a"), isPremium: true, scansRemaining: 9999 });
  assert.deepEqual(await release(env, "a"), { released: false });
});

test("release is safe for unknown users and accounts with no device recorded", async () => {
  const env = setup();
  assert.deepEqual(await release(env, "ghost"), { released: false });
  env.db.store.set("users/x", { planName: "Free Plan", scansRemaining: 3 });
  assert.deepEqual(await release(env, "x"), { released: false });
});
