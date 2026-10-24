"use strict";
// Housekeeping for guest ("Continue as guest") sign-ins.
//
// Every guest creates an anonymous Firebase Auth user. Guests keep nothing in
// the app any more, so an anonymous user that has not been seen for a long
// time is just clutter. This module decides which ones are safe to remove and
// drives the deletion through injected functions, so it can be unit tested
// without Firebase.
//
// Safety rules (a user is only ever deleted when ALL hold):
//   * it is anonymous: no sign-in provider, no email, no phone number;
//   * it has a readable activity time and is older than the cut-off;
//   * it is not a paying user (users/{uid}.isPremium is not true);
//   * its Firestore data was deleted first (otherwise the Auth user stays so
//     the data is not orphaned and the next run retries).

const DAY_MS = 24 * 60 * 60 * 1000;

/** Never go below this, whatever the configuration says. */
const MIN_AGE_DAYS = 7;
const DEFAULT_AGE_DAYS = 30;
const DEFAULT_MAX_DELETES = 2000;
const AUTH_DELETE_CHUNK = 1000; // admin.auth().deleteUsers limit

function parseTime(value) {
  if (!value) return null;
  const ms = typeof value === "number" ? value : Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

/** An anonymous user has no way to sign in again except from its own device. */
function isAnonymousRecord(user) {
  const providers = Array.isArray(user.providerData) ? user.providerData : [];
  return providers.length === 0 && !user.email && !user.phoneNumber;
}

/** Most recent sign-in, token refresh or creation time, in ms; null if none is readable. */
function lastActivityMs(user) {
  const meta = user.metadata || {};
  const times = [meta.lastSignInTime, meta.lastRefreshTime, meta.creationTime]
    .map(parseTime)
    .filter((t) => t !== null);
  return times.length ? Math.max(...times) : null;
}

function isStaleAnonymous(user, nowMs, maxAgeDays) {
  if (!isAnonymousRecord(user)) return false;
  const last = lastActivityMs(user);
  if (last === null) return false; // cannot tell how old: keep it
  return nowMs - last > maxAgeDays * DAY_MS;
}

function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}

/**
 * @param {object} o
 * @param {(pageToken?: string) => Promise<{users: object[], pageToken?: string}>} o.listPage
 * @param {(uid: string) => Promise<boolean>} o.isPremium
 * @param {(uid: string) => Promise<void>} o.deleteUserData   removes Firestore / storage data
 * @param {(uids: string[]) => Promise<{successCount: number, failureCount: number}>} o.deleteAuthUsers
 * @param {number} [o.nowMs]
 * @param {number} [o.maxAgeDays]
 * @param {number} [o.maxDeletes]  upper bound per run
 * @param {boolean} [o.dryRun]     count only, delete nothing
 */
async function cleanupAnonymousUsers({
  listPage,
  isPremium,
  deleteUserData,
  deleteAuthUsers,
  nowMs = Date.now(),
  maxAgeDays = DEFAULT_AGE_DAYS,
  maxDeletes = DEFAULT_MAX_DELETES,
  dryRun = false,
}) {
  const ageDays = Math.max(MIN_AGE_DAYS, Number(maxAgeDays) || DEFAULT_AGE_DAYS);
  const summary = {
    scanned: 0,
    anonymous: 0,
    stale: 0,
    skippedPremium: 0,
    dataFailures: 0,
    deleted: 0,
    authFailures: 0,
    dryRun: !!dryRun,
    maxAgeDays: ageDays,
    capped: false,
  };

  const candidates = [];
  let pageToken;
  do {
    const page = await listPage(pageToken);
    for (const user of page.users || []) {
      summary.scanned++;
      if (isAnonymousRecord(user)) summary.anonymous++;
      if (!isStaleAnonymous(user, nowMs, ageDays)) continue;
      summary.stale++;
      if (candidates.length >= maxDeletes) {
        summary.capped = true;
        continue;
      }
      candidates.push(user.uid);
    }
    pageToken = page.pageToken;
  } while (pageToken);

  if (dryRun) {
    summary.deleted = 0;
    summary.wouldDelete = candidates.length;
    return summary;
  }

  const ready = [];
  for (const uid of candidates) {
    try {
      if (await isPremium(uid)) {
        summary.skippedPremium++;
        continue;
      }
      await deleteUserData(uid);
      ready.push(uid);
    } catch (_) {
      summary.dataFailures++; // keep the Auth user; the next run retries it
    }
  }

  for (const part of chunk(ready, AUTH_DELETE_CHUNK)) {
    const result = await deleteAuthUsers(part);
    summary.deleted += result.successCount;
    summary.authFailures += result.failureCount;
  }
  return summary;
}

module.exports = {
  DAY_MS,
  MIN_AGE_DAYS,
  DEFAULT_AGE_DAYS,
  isAnonymousRecord,
  lastActivityMs,
  isStaleAnonymous,
  cleanupAnonymousUsers,
};
