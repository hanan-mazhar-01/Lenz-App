"use strict";

/**
 * Gemini REST helpers for the callable functions. Only
 * gemini-3.1-flash-lite is used (owner's decision), without any tools: no
 * Google Search or other external research (removed 2026-09-27 at the
 * owner's request).
 *
 * Verified against the live API on 2026-09-27: thinkingConfig.thinkingLevel
 * accepts minimal | low | medium | high; thinkingBudget 0 is still accepted.
 */

const MODEL = "gemini-3.1-flash-lite";
const THINKING_LEVELS = new Set(["minimal", "low", "medium", "high"]);
const MAX_OUTPUT_TOKENS = 8192;

class GeminiError extends Error {
  /**
   * @param {string} code  unavailable | rate_limited | auth | bad_request |
   *                       truncated | blocked | empty | malformed | network
   */
  constructor(code, message, detail) {
    super(message);
    this.code = code;
    this.detail = detail;
  }
}

function thinkingConfigFor(level) {
  if (level && THINKING_LEVELS.has(level)) return { thinkingLevel: level };
  // Historical default of this backend: no thinking tokens.
  return { thinkingBudget: 0 };
}

/**
 * One generateContent call. Returns the decoded response. Throws
 * GeminiError for HTTP / network failures. Never logs the API key or
 * request contents.
 */
async function generateContent({ apiKey, parts, generationConfig, timeoutMs = 90000, fetchImpl = fetch }) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;
  // No `tools`: the backend never enables search or other tools.
  const body = { contents: [{ parts }], generationConfig };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let response;
  try {
    response = await fetchImpl(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (e) {
    throw new GeminiError("network", `Failed to reach the AI service: ${e.name === "AbortError" ? "timeout" : e.message}`);
  } finally {
    clearTimeout(timer);
  }

  if (!response.ok) {
    const status = response.status;
    // Error bodies can echo parts of the request; keep only a short prefix.
    const errText = (await response.text()).slice(0, 300);
    if (status === 429) throw new GeminiError("rate_limited", "AI service rate limit reached.", errText);
    if (status === 401 || status === 403) throw new GeminiError("auth", "AI service authorization error.", errText);
    if (status === 402) throw new GeminiError("quota_exhausted", "AI service billing/quota limit reached.", errText);
    if (status >= 500) throw new GeminiError("unavailable", `AI service temporarily unavailable (status ${status}).`, errText);
    throw new GeminiError("bad_request", `AI service returned status ${status}.`, errText);
  }
  return response.json();
}

/** Concatenated answer text of the first candidate, without thought parts. */
function answerText(candidate) {
  const parts = (candidate && candidate.content && candidate.content.parts) || [];
  return parts
    .filter((p) => typeof p.text === "string" && !p.thought)
    .map((p) => p.text)
    .join("");
}

/**
 * The first candidate, checked: a response that stopped for any reason other
 * than STOP (token limit, safety, recitation...) is an error, never a result.
 */
function finishedCandidate(decoded) {
  const candidates = decoded && decoded.candidates;
  if (!candidates || candidates.length === 0) {
    const reason = decoded && decoded.promptFeedback && decoded.promptFeedback.blockReason;
    throw new GeminiError(reason ? "blocked" : "empty", reason ? `Request blocked (${reason}).` : "No candidates returned by AI service.");
  }
  const candidate = candidates[0];
  const finish = candidate.finishReason || "STOP";
  if (finish === "MAX_TOKENS") {
    throw new GeminiError("truncated", "The AI response was cut off at the output token limit.");
  }
  if (finish !== "STOP") {
    throw new GeminiError("blocked", `The AI response stopped early (${finish}).`);
  }
  if (!answerText(candidate).trim()) throw new GeminiError("empty", "Empty response content received from AI service.");
  return candidate;
}

function parseJsonAnswer(text) {
  let clean = text.trim();
  if (clean.startsWith("```json")) clean = clean.substring(7);
  else if (clean.startsWith("```")) clean = clean.substring(3);
  if (clean.endsWith("```")) clean = clean.substring(0, clean.length - 3);
  clean = clean.trim();
  try {
    const parsed = JSON.parse(clean);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("not a JSON object");
    }
    return parsed;
  } catch (e) {
    throw new GeminiError("malformed", `Malformed JSON response from AI service: ${e.message}`, `length=${clean.length}`);
  }
}

/** Usage numbers only (no content), for logs and cost tracking. */
function usageSummary(decoded) {
  const u = (decoded && decoded.usageMetadata) || {};
  return {
    promptTokens: u.promptTokenCount || 0,
    outputTokens: u.candidatesTokenCount || 0,
    thoughtTokens: u.thoughtsTokenCount || 0,
    toolPromptTokens: u.toolUsePromptTokenCount || 0,
    totalTokens: u.totalTokenCount || 0,
  };
}

module.exports = {
  MODEL,
  THINKING_LEVELS,
  MAX_OUTPUT_TOKENS,
  GeminiError,
  thinkingConfigFor,
  generateContent,
  answerText,
  finishedCandidate,
  parseJsonAnswer,
  usageSummary,
};
