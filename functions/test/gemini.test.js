"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const g = require("../lib/gemini");

const cand = (parts, finishReason = "STOP") => ({ candidates: [{ content: { parts }, finishReason }] });

test("thought parts are not part of the answer", () => {
  const c = g.finishedCandidate(cand([{ text: "thinking...", thought: true }, { text: '{"a":' }, { text: "1}" }]));
  assert.equal(g.answerText(c), '{"a":1}');
});

test("truncated, blocked and empty responses are errors, never results", () => {
  assert.throws(() => g.finishedCandidate(cand([{ text: '{"a":' }], "MAX_TOKENS")), (e) => e.code === "truncated");
  assert.throws(() => g.finishedCandidate(cand([{ text: "x" }], "SAFETY")), (e) => e.code === "blocked");
  assert.throws(() => g.finishedCandidate(cand([{ text: "  " }])), (e) => e.code === "empty");
  assert.throws(() => g.finishedCandidate({ candidates: [], promptFeedback: { blockReason: "OTHER" } }), (e) => e.code === "blocked");
});

test("JSON answers are parsed strictly", () => {
  assert.deepEqual(g.parseJsonAnswer('```json\n{"a":1}\n```'), { a: 1 });
  assert.throws(() => g.parseJsonAnswer("[1,2]"), (e) => e.code === "malformed");
  assert.throws(() => g.parseJsonAnswer('{"a":'), (e) => e.code === "malformed");
});

test("thinking levels come from an allow-list", () => {
  assert.deepEqual(g.thinkingConfigFor("low"), { thinkingLevel: "low" });
  assert.deepEqual(g.thinkingConfigFor("max"), { thinkingBudget: 0 });
  assert.deepEqual(g.thinkingConfigFor(null), { thinkingBudget: 0 });
});

test("requests never enable tools such as Google Search", async () => {
  let sent;
  const fetchImpl = async (_url, opts) => {
    sent = JSON.parse(opts.body);
    return { ok: true, status: 200, json: async () => ({ candidates: [{ finishReason: "STOP", content: { parts: [{ text: "{}" }] } }] }) };
  };
  await g.generateContent({ apiKey: "k", parts: [{ text: "x" }], generationConfig: {}, tools: [{ google_search: {} }], fetchImpl });
  assert.equal(sent.tools, undefined);
  assert.equal(JSON.stringify(sent).includes("google_search"), false);
});
