"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const c = require("../lib/anonymous_cleanup");

const NOW = Date.parse("2026-11-01T00:00:00Z");
const daysAgo = (d) => new Date(NOW - d * c.DAY_MS).toUTCString();

function anon(uid, ageDays, extra = {}) {
  return {
    uid,
    providerData: [],
    metadata: { creationTime: daysAgo(ageDays), lastSignInTime: daysAgo(ageDays), lastRefreshTime: daysAgo(ageDays) },
    ...extra,
  };
}

function harness(users, { premium = [], failData = [] } = {}) {
  const calls = { data: [], auth: [] };
  return {
    calls,
    opts: {
      nowMs: NOW,
      listPage: async (token) => {
        // two pages to exercise paging
        if (!token) return { users: users.slice(0, 2), pageToken: "p2" };
        return { users: users.slice(2) };
      },
      isPremium: async (uid) => premium.includes(uid),
      deleteUserData: async (uid) => {
        if (failData.includes(uid)) throw new Error("firestore down");
        calls.data.push(uid);
      },
      deleteAuthUsers: async (uids) => {
        calls.auth.push(...uids);
        return { successCount: uids.length, failureCount: 0 };
      },
    },
  };
}

test("anonymous means no provider, no email, no phone", () => {
  assert.equal(c.isAnonymousRecord({ providerData: [] }), true);
  assert.equal(c.isAnonymousRecord({ providerData: [{ providerId: "google.com" }] }), false);
  assert.equal(c.isAnonymousRecord({ providerData: [], email: "a@b.c" }), false);
  assert.equal(c.isAnonymousRecord({ providerData: [], phoneNumber: "+100" }), false);
  assert.equal(c.isAnonymousRecord({}), true);
});

test("a user is stale only past the cut-off, by its latest activity", () => {
  assert.equal(c.isStaleAnonymous(anon("a", 31), NOW, 30), true);
  assert.equal(c.isStaleAnonymous(anon("a", 29), NOW, 30), false);
  // created long ago but refreshed yesterday: still in use
  const active = anon("b", 90);
  active.metadata.lastRefreshTime = daysAgo(1);
  assert.equal(c.isStaleAnonymous(active, NOW, 30), false);
});

test("a user whose age cannot be read is kept", () => {
  assert.equal(c.isStaleAnonymous({ uid: "x", providerData: [], metadata: {} }, NOW, 30), false);
  assert.equal(c.isStaleAnonymous({ uid: "x", providerData: [] }, NOW, 30), false);
});

test("deletes only old anonymous users, across pages, and never signed-in ones", async () => {
  const users = [
    anon("old1", 60),
    anon("fresh", 3),
    { ...anon("real", 400), providerData: [{ providerId: "password" }], email: "me@x.com" },
    anon("old2", 45),
  ];
  const h = harness(users);
  const s = await c.cleanupAnonymousUsers(h.opts);
  assert.deepEqual(h.calls.data.sort(), ["old1", "old2"]);
  assert.deepEqual(h.calls.auth.sort(), ["old1", "old2"]);
  assert.equal(s.scanned, 4);
  assert.equal(s.deleted, 2);
  assert.equal(s.stale, 2);
});

test("a paying anonymous user is never deleted", async () => {
  const h = harness([anon("payer", 90), anon("old", 90)], { premium: ["payer"] });
  const s = await c.cleanupAnonymousUsers(h.opts);
  assert.deepEqual(h.calls.auth, ["old"]);
  assert.equal(s.skippedPremium, 1);
});

test("if the data cannot be deleted the Auth user is kept for the next run", async () => {
  const h = harness([anon("bad", 90), anon("good", 90)], { failData: ["bad"] });
  const s = await c.cleanupAnonymousUsers(h.opts);
  assert.deepEqual(h.calls.auth, ["good"]);
  assert.equal(s.dataFailures, 1);
  assert.equal(s.deleted, 1);
});

test("dry run deletes nothing and reports what it would delete", async () => {
  const h = harness([anon("old1", 60), anon("old2", 60), anon("fresh", 1)]);
  const s = await c.cleanupAnonymousUsers({ ...h.opts, dryRun: true });
  assert.deepEqual(h.calls.data, []);
  assert.deepEqual(h.calls.auth, []);
  assert.equal(s.wouldDelete, 2);
  assert.equal(s.deleted, 0);
});

test("a run is capped, and the rest waits for the next run", async () => {
  const users = [anon("a", 60), anon("b", 60), anon("c", 60), anon("d", 60)];
  const h = harness(users);
  const s = await c.cleanupAnonymousUsers({ ...h.opts, maxDeletes: 2 });
  assert.equal(h.calls.auth.length, 2);
  assert.equal(s.capped, true);
  assert.equal(s.stale, 4);
});

test("an invalid age falls back to 30 days; a tiny age is raised to the minimum", async () => {
  const h1 = harness([anon("young", 3), anon("a", 5), anon("b", 20)]);
  const s1 = await c.cleanupAnonymousUsers({ ...h1.opts, maxAgeDays: 0 });
  assert.equal(s1.maxAgeDays, c.DEFAULT_AGE_DAYS);
  assert.deepEqual(h1.calls.auth, []); // nobody is 30+ days old

  const h2 = harness([anon("young", 3), anon("a", 5), anon("b", 20)]);
  const s2 = await c.cleanupAnonymousUsers({ ...h2.opts, maxAgeDays: 2 });
  assert.equal(s2.maxAgeDays, c.MIN_AGE_DAYS);
  assert.deepEqual(h2.calls.auth, ["b"]); // 3 and 5 days old are inside the 7-day floor
});
