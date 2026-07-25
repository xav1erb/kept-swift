// The prompt-suite red-team harness (M1-CONTRACTS §6): every never-rule gets a case asserted
// against LIVE model output, with the exact prompt stack the deployed function uses. Run on
// every prompt change:
//
//   deno run --allow-net --allow-env --allow-read prompt-suite/run.ts
//
// Requires ANTHROPIC_API_KEY (provisioning item 2 — the CI key, never the production key in a
// shell profile). Exits 2 when unconfigured (a skipped red-team is a FAILED red-team, never a
// silent green), 1 on any assertion failure.
//
// Two pipelines (M4-CONTRACTS §8.10): "extract" cases run the extract stack (Haiku-class,
// delta-envelope asserts); "chat" cases run the chat stack (Sonnet-class, reply-content asserts).

import {
  PERSONA,
  PROMPT_VERSION,
  SCHEMA_INSTRUCTIONS,
  SURFACE_CHAPTER_CHAT,
  SURFACE_ONBOARDING,
  SURFACE_VENT,
} from "../supabase/functions/extract/prompts.gen.ts";
import { ENVELOPE_OUTPUT_SCHEMA } from "../supabase/functions/extract/envelope-schema.ts";
import {
  MODE_CHAT,
  PERSONA as CHAT_PERSONA,
  PROMPT_VERSION as CHAT_PROMPT_VERSION,
  STAGE_KEEPCARD,
  STAGE_LIKELYANSWERS,
  STAGE_OPENINGCLOSE,
  STAGE_PERSPECTIVE,
  STAGE_REFRAME,
} from "../supabase/functions/chat/prompts.gen.ts";
import { assembleUserMessage, type WireChatContext, type WireTurn } from "../supabase/functions/chat/assemble.ts";
import { outputSchemaFor } from "../supabase/functions/chat/card-schemas.ts";

const SURFACES: Record<string, string> = {
  onboarding: SURFACE_ONBOARDING,
  chapterChat: SURFACE_CHAPTER_CHAT,
  vent: SURFACE_VENT,
};

const CHAT_STAGES: Record<string, string> = {
  reframe: STAGE_REFRAME,
  likelyAnswers: STAGE_LIKELYANSWERS,
  perspective: STAGE_PERSPECTIVE,
  keepCard: STAGE_KEEPCARD,
  openingClose: STAGE_OPENINGCLOSE,
};

type Assertion =
  | { type: "noDeltaOfKind"; kind: string }
  | { type: "hasDeltaOfKind"; kind: string }
  | { type: "hasDisambiguationFor"; mention: string }
  | { type: "noPhrasesInContent"; phrases: string[] }
  | { type: "replyLacksPhrases"; phrases: string[] }
  | { type: "replyHasOneOfPhrases"; phrases: string[] };

interface ExtractCase {
  id: string;
  law: string;
  pipeline?: "extract";
  surface: string;
  clientTime: string;
  context: unknown;
  utterance: string;
  asserts: Assertion[];
}

interface ChatCase {
  id: string;
  law: string;
  pipeline: "chat";
  mode: "chat" | "prep";
  prepStage?: string;
  clientTime: string;
  userText: string | null;
  history: WireTurn[];
  chatContext: WireChatContext;
  asserts: Assertion[];
}

type Case = ExtractCase | ChatCase;

interface Delta {
  kind: string;
  title?: string;
  body?: string;
  text?: string;
  note?: string;
  question?: string;
  reason?: string;
}

const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
if (!apiKey) {
  console.error("prompt-suite: ANTHROPIC_API_KEY not set — cannot red-team (provisioning item 2).");
  Deno.exit(2);
}
const modelId = Deno.env.get("EXTRACT_MODEL_ID") ?? "claude-haiku-4-5";
const chatModelId = Deno.env.get("CHAT_MODEL_ID") ?? "claude-sonnet-5";

const { cases } = JSON.parse(
  await Deno.readTextFile(new URL("./cases.json", import.meta.url)),
) as { cases: Case[] };

let failures = 0;

function checkPhrases(haystack: string, assertion: Assertion): string[] {
  const found: string[] = [];
  switch (assertion.type) {
    case "noPhrasesInContent":
    case "replyLacksPhrases":
      for (const phrase of assertion.phrases) {
        if (haystack.includes(phrase.toLowerCase())) found.push(`content contains '${phrase}'`);
      }
      break;
    case "replyHasOneOfPhrases":
      if (!assertion.phrases.some((phrase) => haystack.includes(phrase.toLowerCase()))) {
        found.push(`content has none of [${assertion.phrases.join(", ")}]`);
      }
      break;
    default:
      break;
  }
  return found;
}

async function callModel(model: string, system: unknown, content: string, schema: object) {
  return await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey!,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: 4096,
      system,
      messages: [{ role: "user", content }],
      output_config: { format: { type: "json_schema", schema } },
    }),
  });
}

for (const testCase of cases) {
  const caseFailures: string[] = [];

  if (testCase.pipeline === "chat") {
    const stage = testCase.mode === "prep" ? testCase.prepStage ?? null : null;
    const layerTwo = stage !== null ? CHAT_STAGES[stage] : MODE_CHAT;
    const response = await callModel(
      chatModelId,
      [
        { type: "text", text: CHAT_PERSONA },
        { type: "text", text: layerTwo, cache_control: { type: "ephemeral" } },
      ],
      assembleUserMessage(testCase.chatContext, testCase.history, testCase.userText, testCase.clientTime, "en"),
      outputSchemaFor(testCase.mode, stage),
    );
    if (!response.ok) {
      console.error(`✘ ${testCase.id}: upstream ${response.status} ${await response.text()}`);
      failures += 1;
      continue;
    }
    const message = await response.json();
    const text = message.content?.find((block: { type: string }) => block.type === "text")?.text ?? "";
    let reply: { text?: unknown; card?: unknown; chips?: unknown };
    try {
      reply = JSON.parse(text);
    } catch {
      console.error(`✘ ${testCase.id}: model output was not the reply JSON`);
      failures += 1;
      continue;
    }
    const replyContent = [
      typeof reply.text === "string" ? reply.text : "",
      reply.card ? JSON.stringify(reply.card) : "",
      Array.isArray(reply.chips) ? reply.chips.join("\n") : "",
    ].join("\n").toLowerCase();

    for (const assertion of testCase.asserts) {
      caseFailures.push(...checkPhrases(replyContent, assertion));
    }
  } else {
    const response = await callModel(
      modelId,
      [
        { type: "text", text: PERSONA },
        { type: "text", text: SURFACES[testCase.surface] },
        { type: "text", text: SCHEMA_INSTRUCTIONS, cache_control: { type: "ephemeral" } },
      ],
      `clientTime: ${testCase.clientTime}\nlocale: en\ncontext:\n${
        JSON.stringify(testCase.context)
      }\n\nutterance:\n${testCase.utterance}`,
      ENVELOPE_OUTPUT_SCHEMA,
    );
    if (!response.ok) {
      console.error(`✘ ${testCase.id}: upstream ${response.status} ${await response.text()}`);
      failures += 1;
      continue;
    }
    const message = await response.json();
    const text = message.content?.find((block: { type: string }) => block.type === "text")?.text ?? "";
    let deltas: Delta[] = [];
    let disambiguations: { mention: string; question?: string }[] = [];
    try {
      const parsed = JSON.parse(text);
      deltas = parsed.deltas ?? [];
      disambiguations = parsed.disambiguations ?? [];
    } catch {
      console.error(`✘ ${testCase.id}: model output was not the envelope JSON`);
      failures += 1;
      continue;
    }

    const extractedText = deltas
      .flatMap((delta) => [delta.title, delta.body, delta.text, delta.note, delta.reason])
      .concat(disambiguations.map((d) => d.question))
      .filter((value): value is string => typeof value === "string")
      .join("\n")
      .toLowerCase();

    for (const assertion of testCase.asserts) {
      switch (assertion.type) {
        case "noDeltaOfKind":
          if (deltas.some((delta) => delta.kind === assertion.kind)) {
            caseFailures.push(`emitted forbidden ${assertion.kind}`);
          }
          break;
        case "hasDeltaOfKind":
          if (!deltas.some((delta) => delta.kind === assertion.kind)) {
            caseFailures.push(`missing expected ${assertion.kind}`);
          }
          break;
        case "hasDisambiguationFor":
          if (!disambiguations.some((d) => d.mention === assertion.mention)) {
            caseFailures.push(`no disambiguation for '${assertion.mention}'`);
          }
          break;
        default:
          caseFailures.push(...checkPhrases(extractedText, assertion));
          break;
      }
    }
  }

  if (caseFailures.length > 0) {
    failures += 1;
    console.error(`✘ ${testCase.id} (${testCase.law}): ${caseFailures.join("; ")}`);
  } else {
    console.log(`✔ ${testCase.id}`);
  }
}

console.log(
  `prompt-suite extract ${PROMPT_VERSION} on ${modelId} · chat ${CHAT_PROMPT_VERSION} on ${chatModelId}: ` +
    `${cases.length - failures}/${cases.length} passed`,
);
Deno.exit(failures > 0 ? 1 : 0);
