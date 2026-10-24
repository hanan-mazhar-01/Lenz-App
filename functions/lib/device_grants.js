"use strict";
// One free-scan grant per device.
//
// A guest gets 3 scans. When they create an account or sign in, the account
// gets the free-plan scans only if THIS DEVICE has not already received them
// for another account. Otherwise every new e-mail address on the same phone
// would mean another batch of free scans.
//
// The device id comes from the app (Android ID / iOS vendor id, or a random id
// kept on the phone when neither is available). Only a SHA-256 of it is stored.
// Everything runs in one Firestore transaction on the server; clients can not
// write scan balances (see firestore.rules).

const crypto = require("crypto");

const FREE_PLAN_SCANS = 3;
const GUEST_SCANS = 3;
const GUEST_PLAN = "Guest Plan";

function hashDeviceId(deviceId) {
  return crypto.createHash("sha256").update(`lenz-device:${deviceId}`).digest("hex");
}

function isValidDeviceId(id) {
  return typeof id === "string" && id.length >= 8 && id.length <= 200;
}

function numberOr(value, fallback) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

/**
 * Finalises a guest-to-account upgrade (or a first sign-in) and grants the
 * free scans once per device.
 *
 * Returns { granted, alreadyUsedOnDevice, invalidDevice, alreadyClaimed }.
 * Idempotent: a second call for the same account changes nothing.
 */
async function claimFreeScans({ db, admin, uid, token, deviceId }) {
  const userRef = db.collection("users").doc(uid);
  const valid = isValidDeviceId(deviceId);
  const deviceRef = valid ? db.collection("device_grants").doc(hashDeviceId(deviceId)) : null;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  let result = { granted: 0, alreadyUsedOnDevice: false, invalidDevice: !valid, alreadyClaimed: false };

  await db.runTransaction(async (tx) => {
    const userDoc = await tx.get(userRef);
    const deviceDoc = deviceRef ? await tx.get(deviceRef) : null;
    const data = userDoc.exists ? userDoc.data() : {};

    // Paying accounts are never touched.
    if (data.isPremium) {
      result = { ...result, alreadyClaimed: true };
      return;
    }
    // Already finalised (by this code, or by the older version that stamped
    // upgradedAt): signing in again must not top the balance up.
    if (data.freeScansClaimed === true || data.upgradedAt) {
      result = { ...result, alreadyClaimed: true };
      return;
    }

    const guestBalance = data.planName === GUEST_PLAN ? Math.max(0, numberOr(data.scansRemaining, 0)) : 0;
    const deviceData = deviceDoc && deviceDoc.exists ? deviceDoc.data() : {};
    const accountOnDevice = deviceData.uid || null;
    const usedElsewhere = Boolean(accountOnDevice && accountOnDevice !== uid);
    // The account that held this device's free scans was deleted: the next
    // account gets what was left unused, never a fresh set.
    const released = deviceData.released === true && !accountOnDevice;
    const leftover = released ? Math.max(0, Math.min(FREE_PLAN_SCANS, numberOr(deviceData.remaining, 0))) : FREE_PLAN_SCANS;
    const grant = valid && !usedElsewhere ? leftover : 0;
    const scansRemaining = Math.max(guestBalance, grant);

    if (valid && !usedElsewhere) {
      tx.set(deviceRef, { uid, grantedAt: ts(), released: false, remaining: 0 }, { merge: true });
    }

    const update = {
      planName: "Free Plan",
      isPremium: false,
      scansRemaining,
      freeScansClaimed: true,
      freeScansGranted: grant,
      ...(valid ? { deviceHash: hashDeviceId(deviceId) } : {}),
      upgradedAt: ts(),
    };
    if (!userDoc.exists) {
      Object.assign(update, {
        name: (token && token.name) || "Collector",
        email: (token && token.email) || "",
        createdAt: ts(),
      });
    }
    tx.set(userRef, update, { merge: true });
    result = {
      granted: grant,
      alreadyUsedOnDevice: usedElsewhere || (released && leftover === 0),
      invalidDevice: !valid,
      alreadyClaimed: false,
    };
  });

  return result;
}

/**
 * Gives a new guest (anonymous user) its guest scans ONCE PER DEVICE.
 *
 * Without this, a person could sign out of an account, tap "Continue as
 * guest" and receive another batch of guest scans every time. A guest
 * document starts at 0 scans; this call, made by the app right after the
 * guest signs in, grants them only if no other guest on this device has had
 * them. Returns { granted, alreadyUsedOnDevice, invalidDevice, alreadyClaimed }.
 * Idempotent per guest.
 */
async function claimGuestScans({ db, admin, uid, token, deviceId }) {
  const userRef = db.collection("users").doc(uid);
  const valid = isValidDeviceId(deviceId);
  const deviceRef = valid ? db.collection("device_grants").doc(hashDeviceId(deviceId)) : null;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  let result = { granted: 0, alreadyUsedOnDevice: false, invalidDevice: !valid, alreadyClaimed: false };

  await db.runTransaction(async (tx) => {
    const userDoc = await tx.get(userRef);
    const deviceDoc = deviceRef ? await tx.get(deviceRef) : null;
    const data = userDoc.exists ? userDoc.data() : {};

    // A registered or paying user is not a guest; a guest claims once.
    if (data.isPremium || data.guestScansClaimed === true || (data.planName && data.planName !== GUEST_PLAN)) {
      result = { ...result, alreadyClaimed: true };
      return;
    }

    const deviceData = deviceDoc && deviceDoc.exists ? deviceDoc.data() : {};
    const usedElsewhere = Boolean(deviceData.guestUid && deviceData.guestUid !== uid);
    const grant = valid && !usedElsewhere ? GUEST_SCANS : 0;

    if (valid && !usedElsewhere) {
      tx.set(deviceRef, { guestUid: uid, guestGrantedAt: ts() }, { merge: true });
    }

    const update = {
      planName: GUEST_PLAN,
      isPremium: false,
      scansRemaining: grant,
      guestScansClaimed: true,
    };
    if (!userDoc.exists) {
      Object.assign(update, { name: "Guest Collector", email: "", createdAt: ts() });
    }
    tx.set(userRef, update, { merge: true });
    result = { granted: grant, alreadyUsedOnDevice: usedElsewhere, invalidDevice: !valid, alreadyClaimed: false };
  });

  return result;
}

/**
 * Called when an account is deleted. If that account held this device's free
 * scans, the unused ones go back into the device ledger so the next account on
 * the phone gets exactly those: deleting never creates scans, and never throws
 * the unused ones away. Premium accounts carry nothing over.
 */
async function releaseOnDelete({ db, uid }) {
  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();
  if (!userDoc.exists) return { released: false };
  const data = userDoc.data();
  if (!data.deviceHash || data.isPremium) return { released: false };

  const deviceRef = db.collection("device_grants").doc(data.deviceHash);
  const deviceDoc = await deviceRef.get();
  if (!deviceDoc.exists || deviceDoc.data().uid !== uid) return { released: false };

  const remaining = Math.max(0, Math.min(FREE_PLAN_SCANS, numberOr(data.scansRemaining, 0)));
  await deviceRef.set({ uid: null, released: true, remaining, releasedAt: new Date() }, { merge: true });
  return { released: true, remaining };
}

module.exports = {
  releaseOnDelete, FREE_PLAN_SCANS, GUEST_SCANS, hashDeviceId, isValidDeviceId, claimFreeScans, claimGuestScans };
