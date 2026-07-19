// Kept extract proxy — the ONLY door to the AI (C5). Platform JWT verification is ON
// (never deploy with --no-verify-jwt); prompts are assembled HERE, server-side, from the
// versioned templates in prompts/ (regenerated into prompts.gen.ts at deploy).
//
// C2 — transient plaintext: the utterance and context exist in this function's memory for the
// duration of the call and nowhere else. Nothing is persisted.
//
// LOG CONTRACT (M1-CONTRACTS §3, code-reviewed under C2): log lines carry utteranceId, timing,
// token counts, model id, prompt version, and error codes. NEVER the utterance, the context,
// the deltas, or any other user content. Adding a logged field = contract review.

import {
  PERSONA,
  PROMPT_VERSION,
  SCHEMA_INSTRUCTIONS,
  SURFACE_CHAPTER_CHAT,
  SURFACE_ONBOARDING,
  SURFACE_VENT,
} from "./prompts.gen.ts";
import { ENVELOPE_OUTPUT_SCHEMA } from "./envelope-schema.ts";

const SCHEMA_VERSION = 1;

const SURFACES: Record<string, string> = {
  onboarding: SURFACE_ONBOARDING,
  chapterChat: SURFACE_CHAPTER_CHAT,
  vent: SURFACE_VENT,
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

  const { schemaVersion, utteranceId, surface, clientTime, locale, utterance, context } = body;
  if (schemaVersion !== SCHEMA_VERSION) {
    // Server-led schema evolution (M1-CONTRACTS §8.4): never silently translate.
    return errorResponse(409, "schema_mismatch", "Update the app to continue", {
      serverVersion: SCHEMA_VERSION,
    });
  }
  if (
    typeof utteranceId !== "string" || typeof utterance !== "string" ||
    typeof surface !== "string" || !SURFACES[surface] ||
    typeof clientTime !== "string" || typeof context !== "object" || context === null
  ) {
    return errorResponse(400, "bad_request", "Malformed extraction request");
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  const modelId = Deno.env.get("EXTRACT_MODEL_ID") ?? "claude-haiku-4-5"; // F4 Haiku-class (§8.1)
  if (!apiKey) {
    console.error(JSON.stringify({ utteranceId, error: "missing_api_key_config" }));
    return errorResponse(503, "upstream_unavailable", "AI upstream not configured");
  }

  // Prompt stack (M1-CONTRACTS §4): layers 1–3 are our static text, shared across all users —
  // the ONLY cache breakpoint sits at the end of layer 3. Layers 4–5 carry user life-content
  // and are never cached (C2: processed, not stored — not even as a provider cache entry).
  const system = [
    { type: "text", text: PERSONA },
    { type: "text", text: SURFACES[surface] },
    { type: "text", text: SCHEMA_INSTRUCTIONS, cache_control: { type: "ephemeral" } },
  ];
  const userMessage = `clientTime: ${clientTime}
locale: ${typeof locale === "string" ? locale : "unknown"}
context:
${JSON.stringify(context)}

utterance:
${utterance}`;

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
        output_config: { format: { type: "json_schema", schema: ENVELOPE_OUTPUT_SCHEMA } },
      }),
    });
  } catch {
    console.error(JSON.stringify({ utteranceId, model: modelId, error: "upstream_unreachable" }));
    return errorResponse(503, "upstream_unavailable", "AI upstream unreachable");
  }

  if (upstream.status === 429 || upstream.status === 529) {
    console.warn(JSON.stringify({ utteranceId, model: modelId, upstreamStatus: upstream.status, error: "rate_limited" }));
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
    console.error(JSON.stringify({ utteranceId, model: modelId, upstreamStatus: upstream.status, error: "upstream_error" }));
    return errorResponse(503, "upstream_unavailable", "AI upstream error");
  }

  const message = await upstream.json();
  const text: unknown = message?.content?.find?.((block: { type: string }) => block.type === "text")?.text;
  let parsed: { deltas?: unknown; disambiguations?: unknown };
  try {
    parsed = JSON.parse(typeof text === "string" ? text : "");
  } catch {
    console.error(JSON.stringify({ utteranceId, model: modelId, error: "unparseable_model_output" }));
    return errorResponse(503, "upstream_unavailable", "Model output unusable");
  }

  // The server stamps identity; the model only ever proposes deltas (C4).
  const envelope = {
    schemaVersion: SCHEMA_VERSION,
    utteranceId,
    deltas: Array.isArray(parsed.deltas) ? parsed.deltas : [],
    disambiguations: Array.isArray(parsed.disambiguations) ? parsed.disambiguations : [],
  };

  console.info(JSON.stringify({
    utteranceId,
    model: modelId,
    promptVersion: PROMPT_VERSION,
    ms: Math.round(performance.now() - startedAt),
    inputTokens: message?.usage?.input_tokens,
    outputTokens: message?.usage?.output_tokens,
    cacheReadTokens: message?.usage?.cache_read_input_tokens,
    deltaCount: envelope.deltas.length, // a count, never content
  }));

  return new Response(JSON.stringify(envelope), {
    headers: { "Content-Type": "application/json" },
  });
});
