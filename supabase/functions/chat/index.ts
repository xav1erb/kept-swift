// Kept chat proxy — Pom's voice (C5). Platform JWT verification is ON (never deploy with
// --no-verify-jwt); prompts are assembled HERE, server-side, from the versioned templates in
// prompts/chat/ (regenerated into prompts.gen.ts at deploy).
//
// C2 — transient plaintext: userText, history, and context exist in this function's memory for
// the duration of the call and nowhere else. Nothing is persisted.
//
// LOG CONTRACT (M4-CONTRACTS §4, code-reviewed under C2): log lines carry turnId, mode/stage,
// timing, token counts, model id, prompt version, and error codes. NEVER the user text, the
// history, the context, or the reply. Adding a logged field = contract review.

import {
  MODE_CHAT,
  PERSONA,
  PROMPT_VERSION,
  STAGE_KEEPCARD,
  STAGE_LIKELYANSWERS,
  STAGE_OPENINGCLOSE,
  STAGE_PERSPECTIVE,
  STAGE_REFRAME,
} from "./prompts.gen.ts";
import { assembleUserMessage, type WireChatContext, type WireTurn } from "./assemble.ts";
import { outputSchemaFor } from "./card-schemas.ts";

const SCHEMA_VERSION = 1;
const HISTORY_CAP = 30;

const STAGE_TEMPLATES: Record<string, string> = {
  reframe: STAGE_REFRAME,
  likelyAnswers: STAGE_LIKELYANSWERS,
  perspective: STAGE_PERSPECTIVE,
  keepCard: STAGE_KEEPCARD,
  openingClose: STAGE_OPENINGCLOSE,
};

function errorResponse(
  status: number,
  code: string,
  message: string,
  extra: Record<string, unknown> = {},
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify({ error: { code, message, ...extra } }), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
}

Deno.serve(async (req: Request) => {
  const startedAt = performance.now();
  if (req.method !== "POST") {
    return errorResponse(405, "bad_request", "POST only");
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "bad_request", "Body must be JSON");
  }

  const { schemaVersion, turnId, chapterId, mode, prepStage, clientTime, locale, userText, history, context } = body;
  if (schemaVersion !== SCHEMA_VERSION) {
    // Server-led schema evolution (M1-CONTRACTS §8.4): never silently translate.
    return errorResponse(409, "schema_mismatch", "Update the app to continue", {
      serverVersion: SCHEMA_VERSION,
    });
  }
  const stage = typeof prepStage === "string" ? prepStage : null;
  if (
    typeof turnId !== "string" || typeof chapterId !== "string" ||
    typeof clientTime !== "string" || typeof context !== "object" || context === null ||
    !Array.isArray(history) ||
    (mode !== "chat" && mode !== "prep") ||
    (mode === "prep" && (stage === null || !STAGE_TEMPLATES[stage])) ||
    (userText !== undefined && userText !== null && typeof userText !== "string")
  ) {
    return errorResponse(400, "bad_request", "Malformed chat request");
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  const modelId = Deno.env.get("CHAT_MODEL_ID") ?? "claude-sonnet-5"; // F4 Sonnet-class (M1 §8.1)
  if (!apiKey) {
    console.error(JSON.stringify({ turnId, error: "missing_api_key_config" }));
    return errorResponse(503, "upstream_unavailable", "AI upstream not configured");
  }

  // Prompt stack (M4-CONTRACTS §4): layers 1–3 are our static text, shared across all users —
  // the ONLY cache breakpoint sits at the end of layer 3 (the mode/stage template; the output
  // schema itself is grammar-cached by the API). Layers 4–5 carry user life-content and are
  // never cached (C2: processed, not stored — not even as a provider cache entry).
  const layerTwo = mode === "prep" ? STAGE_TEMPLATES[stage!] : MODE_CHAT;
  const system = [
    { type: "text", text: PERSONA },
    { type: "text", text: layerTwo, cache_control: { type: "ephemeral" } },
  ];
  const userMessage = assembleUserMessage(
    context as unknown as WireChatContext,
    (history as WireTurn[]).slice(-HISTORY_CAP),
    typeof userText === "string" ? userText : null,
    clientTime,
    typeof locale === "string" ? locale : "unknown",
  );

  let upstream: Response;
  try {
    upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: modelId,
        max_tokens: 4096,
        system,
        messages: [{ role: "user", content: userMessage }],
        output_config: { format: { type: "json_schema", schema: outputSchemaFor(mode, stage) } },
      }),
    });
  } catch {
    console.error(JSON.stringify({ turnId, model: modelId, error: "upstream_unreachable" }));
    return errorResponse(503, "upstream_unavailable", "AI upstream unreachable");
  }

  if (upstream.status === 429 || upstream.status === 529) {
    console.warn(JSON.stringify({ turnId, model: modelId, upstreamStatus: upstream.status, error: "rate_limited" }));
    const retryAfter = upstream.headers.get("retry-after");
    return errorResponse(
      429,
      "rate_limited",
      "Try again shortly",
      {},
      retryAfter ? { "Retry-After": retryAfter } : {},
    );
  }
  if (!upstream.ok) {
    console.error(JSON.stringify({ turnId, model: modelId, upstreamStatus: upstream.status, error: "upstream_error" }));
    return errorResponse(503, "upstream_unavailable", "AI upstream error");
  }

  const message = await upstream.json();
  const text: unknown = message?.content?.find?.((block: { type: string }) => block.type === "text")?.text;
  let parsed: { text?: unknown; card?: unknown; chips?: unknown };
  try {
    parsed = JSON.parse(typeof text === "string" ? text : "");
  } catch {
    console.error(JSON.stringify({ turnId, model: modelId, error: "unparseable_model_output" }));
    return errorResponse(503, "upstream_unavailable", "Model output unusable");
  }
  if (typeof parsed.text !== "string") {
    console.error(JSON.stringify({ turnId, model: modelId, error: "missing_text_in_output" }));
    return errorResponse(503, "upstream_unavailable", "Model output unusable");
  }

  // The server stamps identity; the model only ever proposes the reply (C4).
  const envelope = {
    schemaVersion: SCHEMA_VERSION,
    turnId,
    text: parsed.text,
    card: parsed.card ?? null,
    chips: Array.isArray(parsed.chips) ? parsed.chips : [],
  };

  console.info(JSON.stringify({
    turnId,
    mode,
    stage,
    model: modelId,
    promptVersion: PROMPT_VERSION,
    ms: Math.round(performance.now() - startedAt),
    inputTokens: message?.usage?.input_tokens,
    outputTokens: message?.usage?.output_tokens,
    cacheReadTokens: message?.usage?.cache_read_input_tokens,
    hasCard: envelope.card !== null, // a flag, never content
  }));

  return new Response(JSON.stringify(envelope), {
    headers: { "Content-Type": "application/json" },
  });
});
