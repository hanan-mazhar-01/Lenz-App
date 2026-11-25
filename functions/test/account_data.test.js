"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { deleteAccountData, deleteQueryInPages } = require("../lib/account_data");

// In-memory store keyed by full document path, enough for this module:
// doc refs, top-level where("field","==",v).limit(n).get(), batches with a
// 500-write cap, and recursiveDelete on a document.
function makeDb() {
  const store = new Map();
  let batchCommits = 0;
  const docRef = (path) => ({
    path,
    async delete() { store.delete(path); },
    collection: (name) => collRef(`${path}/${name}`),
  });
  const collRef = (path) => ({
    doc: (id) => docRef(`${path}/${id}`),
    where: (field, op, value) => queryRef(path, field, value),
  });
  const queryRef = (path, field, value, lim = Infinity) => ({
    limit: (n) => queryRef(path, field, value, n),
    async get() {
      const docs = [...store.entries()]
        .filter(([p, d]) => p.startsWith(`${path}/`) && p.split("/").length === path.split("/").length + 1 && d[field] === value)
        .slice(0, lim)
        .map(([p]) => ({ ref: docRef(p) }));
      return { empty: docs.length === 0, size: docs.length, docs };
    },
  });
  const db = {
    store,
    get batchCommits() { return batchCommits; },
    collection: (name) => collRef(name),
    batch() {
      const ops = [];
      return {
        delete: (ref) => ops.push(ref),
        async commit() {
          if (ops.length > 500) throw new Error("batch over 500 writes");
          batchCommits++;
          for (const r of ops) store.delete(r.path);
        },
      };
    },
    async recursiveDelete(ref) {
      for (const p of [...store.keys()]) if (p === ref.path || p.startsWith(`${ref.path}/`)) store.delete(p);
    },
  };
  return db;
}

test("deletes the user doc with every subcollection, however many documents", async () => {
  const db = makeDb();
  db.store.set("users/u1", { name: "A" });
  for (let i = 0; i < 1200; i++) db.store.set(`users/u1/reports/r${i}`, {});
  db.store.set("users/u1/collection/c1", {});
  db.store.set("users/u1/somethingNew/x", {});
  db.store.set("users/u2", { name: "B" });
  db.store.set("users/u2/reports/r1", {});

  await deleteAccountData({ db, uid: "u1" });

  assert.equal([...db.store.keys()].filter((k) => k.startsWith("users/u1")).length, 0);
  assert.ok(db.store.has("users/u2"));
  assert.ok(db.store.has("users/u2/reports/r1"));
});

test("removes rate_limits and all scan_sessions of the user only", async () => {
  const db = makeDb();
  db.store.set("rate_limits/u1", { day: 3 });
  db.store.set("rate_limits/u2", { day: 1 });
  for (let i = 0; i < 950; i++) db.store.set(`scan_sessions/u1_s${i}`, { uid: "u1" });
  db.store.set("scan_sessions/u2_s1", { uid: "u2" });

  const { sessions } = await deleteAccountData({ db, uid: "u1" });

  assert.equal(sessions, 950);
  assert.ok(!db.store.has("rate_limits/u1"));
  assert.ok(db.store.has("rate_limits/u2"));
  assert.equal([...db.store.keys()].filter((k) => k.startsWith("scan_sessions/u1_")).length, 0);
  assert.ok(db.store.has("scan_sessions/u2_s1"));
});

test("deleteQueryInPages stays under the 500-write batch limit", async () => {
  const db = makeDb();
  for (let i = 0; i < 1001; i++) db.store.set(`scan_sessions/x${i}`, { uid: "u9" });
  const removed = await deleteQueryInPages(db, db.collection("scan_sessions").where("uid", "==", "u9"));
  assert.equal(removed, 1001);
  assert.equal(db.batchCommits, 3);
});

test("refuses to run without a uid", async () => {
  await assert.rejects(deleteAccountData({ db: makeDb(), uid: "" }));
});
