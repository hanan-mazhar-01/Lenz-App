"use strict";
// Minimal in-memory Firestore for unit tests: collection/doc/get/set(merge)
// and runTransaction. FieldValue.increment and serverTimestamp are supported.

class Increment { constructor(n) { this.n = n; } }
class ServerTs {}

function applyMerge(prev, update) {
  const out = { ...(prev || {}) };
  for (const [k, v] of Object.entries(update)) {
    if (v instanceof Increment) out[k] = (typeof out[k] === "number" ? out[k] : 0) + v.n;
    else if (v instanceof ServerTs) out[k] = new Date();
    else out[k] = v;
  }
  return out;
}

function makeFake() {
  const store = new Map();
  const ref = (path) => ({
    path,
    async get() {
      return { exists: store.has(path), data: () => store.get(path) };
    },
    async set(v, opts) {
      store.set(path, opts && opts.merge ? applyMerge(store.get(path), v) : applyMerge({}, v));
    },
  });
  const db = {
    store,
    collection: (c) => ({ doc: (d) => ref(`${c}/${d}`) }),
    async runTransaction(fn) {
      const writes = [];
      const tx = {
        get: (r) => r.get(),
        set: (r, v, opts) => writes.push([r, v, opts]),
      };
      await fn(tx);
      for (const [r, v, opts] of writes) await r.set(v, opts);
    },
  };
  const admin = {
    firestore: {
      FieldValue: { increment: (n) => new Increment(n), serverTimestamp: () => new ServerTs() },
      Timestamp: { fromMillis: (ms) => ({ toMillis: () => ms }) },
    },
  };
  return { db, admin };
}

module.exports = { makeFake };
