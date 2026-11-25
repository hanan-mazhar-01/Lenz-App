"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("crypto");
const c = require("../lib/cloudinary");

test("signParams matches Cloudinary's documented example", () => {
  // From Cloudinary's "Generating authentication signatures" docs.
  const sig = c.signParams({ eager: "w_400,h_300,c_pad|w_260,h_200,c_crop", public_id: "sample_image", timestamp: 1315060510 }, "abcd");
  assert.equal(sig, "bfd09f95f331f558cbd1320e67aa8d488770583e");
});

test("uploads are signed for the caller's own uid and the fixed folder", () => {
  const nowMs = 1764072000000;
  const plan = c.planSignedUploads({ uid: "user1", scanId: "rep_1764072000000", evidenceIds: ["overview", "logo", "overview"], apiSecret: "s3cret", nowMs });
  assert.equal(plan.folder, "lenz_replica_detector");
  assert.equal(plan.timestamp, 1764072000);
  assert.deepEqual(Object.keys(plan.uploads), ["overview", "logo"]);
  const u = plan.uploads.overview;
  assert.equal(u.publicId, "user1_rep_1764072000000_overview");
  const expected = crypto.createHash("sha1")
    .update(`folder=lenz_replica_detector&public_id=${u.publicId}&timestamp=1764072000s3cret`).digest("hex");
  assert.equal(u.signature, expected);
});

test("bad input is rejected or skipped", () => {
  const base = { uid: "u", apiSecret: "s" };
  assert.throws(() => c.planSignedUploads({ ...base, scanId: "../x", evidenceIds: ["a"] }), /scanId/);
  assert.throws(() => c.planSignedUploads({ ...base, scanId: "rep_123456", evidenceIds: [] }), /non-empty/);
  assert.throws(() => c.planSignedUploads({ ...base, scanId: "rep_123456", evidenceIds: Array.from({ length: 33 }, (_, i) => `e${i}`) }), /At most/);
  const plan = c.planSignedUploads({ ...base, scanId: "rep_123456", evidenceIds: ["ok", "../evil", "a/b", 7] });
  assert.deepEqual(Object.keys(plan.uploads), ["ok"]);
});
