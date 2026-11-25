"use strict";

/**
 * Removes everything Firestore keeps about one account:
 *  - users/{uid} and every subcollection under it (reports, collection,
 *    categories, and any added later), via the Admin SDK's recursiveDelete,
 *    which pages through any number of documents (a plain batch is capped
 *    at 500 writes),
 *  - rate_limits/{uid},
 *  - every scan_sessions document of this uid (paged).
 *
 * Throws if a step fails, so callers can stop before deleting the Auth user.
 */

const PAGE_SIZE = 400;

/** Deletes every document matching [query], PAGE_SIZE at a time. Returns the count. */
async function deleteQueryInPages(db, query, pageSize = PAGE_SIZE) {
  let removed = 0;
  for (;;) {
    const snap = await query.limit(pageSize).get();
    if (snap.empty) return removed;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    removed += snap.size;
    if (snap.size < pageSize) return removed;
  }
}

async function deleteAccountData({ db, uid }) {
  if (!uid || typeof uid !== "string") throw new Error("deleteAccountData: uid required");
  const userRef = db.collection("users").doc(uid);
  await db.recursiveDelete(userRef);
  await db.collection("rate_limits").doc(uid).delete();
  const sessions = await deleteQueryInPages(db, db.collection("scan_sessions").where("uid", "==", uid));
  return { sessions };
}

module.exports = { deleteAccountData, deleteQueryInPages, PAGE_SIZE };
