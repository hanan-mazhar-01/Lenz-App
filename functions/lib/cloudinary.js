/**
 * Signed Cloudinary uploads.
 *
 * The app used to upload with an *unsigned* preset baked into the binary,
 * which anyone could extract and use to upload anything to this Cloudinary
 * account. Now the client asks signCloudinaryUploads for one signature per
 * photo; the server fixes the folder and public_id (always prefixed with the
 * caller's own uid, matching what deleteScanAssets / deleteAccount delete
 * by prefix), so a signature can't be reused for anyone else's path. The API
 * secret never leaves the server.
 *
 * Signature scheme (Cloudinary "authenticated requests"): sort the signed
 * params by name, join as k=v with "&", append the API secret, SHA-1 hex.
 */

const crypto = require("crypto");
const { RequestError, validScanId } = require("./limits");

const ROOT_FOLDER = "lenz_replica_detector";
const MAX_UPLOADS_PER_REQUEST = 32;
const EVIDENCE_ID = /^[A-Za-z0-9_.-]{1,80}$/;

function signParams(params, apiSecret) {
  const toSign = Object.keys(params)
    .filter((k) => params[k] !== undefined && params[k] !== null && params[k] !== "")
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join("&");
  return crypto.createHash("sha1").update(toSign + apiSecret).digest("hex");
}

/**
 * Validates a signCloudinaryUploads request and returns the signed upload
 * parameters for each evidence photo:
 *   { folder, timestamp, uploads: { [evidenceId]: { publicId, signature } } }
 * Invalid evidence ids are skipped (that photo just stays local).
 */
function planSignedUploads({ uid, scanId, evidenceIds, apiSecret, nowMs = Date.now() }) {
  const scan = validScanId(scanId);
  if (!scan) throw new RequestError("invalid-argument", "A valid scanId is required.");
  if (!Array.isArray(evidenceIds) || evidenceIds.length === 0) {
    throw new RequestError("invalid-argument", "evidenceIds must be a non-empty list.");
  }
  if (evidenceIds.length > MAX_UPLOADS_PER_REQUEST) {
    throw new RequestError("invalid-argument", `At most ${MAX_UPLOADS_PER_REQUEST} photos per request.`);
  }
  const timestamp = Math.floor(nowMs / 1000);
  const uploads = {};
  for (const id of new Set(evidenceIds)) {
    if (typeof id !== "string" || !EVIDENCE_ID.test(id)) continue;
    const publicId = `${uid}_${scan}_${id}`;
    uploads[id] = {
      publicId,
      signature: signParams({ folder: ROOT_FOLDER, public_id: publicId, timestamp }, apiSecret),
    };
  }
  return { folder: ROOT_FOLDER, timestamp, uploads };
}

module.exports = { ROOT_FOLDER, signParams, planSignedUploads };
