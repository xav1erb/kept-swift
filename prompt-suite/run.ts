// The prompt-suite red-team harness (M1-CONTRACTS §6): every never-rule gets a case asserted
// against LIVE model output, with the exact prompt stack the deployed function uses. Run on
// every prompt change:
//
//   deno run --allow-net --allow-env prompt-suite/run.ts
//
// Requires ANTHROPIC_API_KEY (provisioning item 2 — the CI key, never the production key in a
// shell profile). Exits 2 when unconfigured (a skipped red-team is a FAILED red-team, never a
// silent green), 1 on any assertion failure.

import {
  PERSONA,
  PROMPT_VERSION,
  SCHEMA_INSTRUCTIONS,
  SURFACE_CHAPTER_CHAT,
  SURFACE_ONBOARDING,
  SURFACE_VENT,
} from "../supabase/functions/extract/prompts.gen.ts";
import { ENVELOPE_OUTPUT_SCHEMA } from "../supabase/functions/extract/envelope-schema.ts";

const SURFACES: Record<string, string> = {
  onboarding: SURFACE_ONBOARDING,
  chapterChat: SURFACE_CHAPTER_CHAT,
  vent: SURFACE_VENT,
};

type Assertion =
  | { type: "noDeltaOfKind"; kind: string }
  | { type: "hasDeltaOfKind"; kind: string }
  | { type: "hasDisambiguationFor"; mention: string }
  | { type: "noPhrasesInContent"; phrases: string[] };

interface Case {
  id: string;
  law: string;
  surface: string;
  clientTime: string;
  context: unknown;
  utterance: string;
  asserts: Assertion[];
}

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

const { cases } = JSON.parse(
  await Deno.readTextFile(new URL("./cases.json", import.meta.url)),
) as { cases: Case[] };

let failures = 0;

for (const testCase of cases) {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: modelId,
      max_tokens: 4096,
      system: [
        { type: "text", text: PERSONA },
        { type: "text", text: SURFACES[testCase.surface] },
        { type: "text", text: SCHEMA_INSTRUCTIONS, cache_control: { type: "ephemeral" } },
      ],
      messages: [{
        role: "user",
        content: `clientTime: ${testCase.clientTime}\nlocale: en\ncontext:\n${
          JSON.stringify(testCase.context)
        }\n\nutterance:\n${testCase.utterance}`,
      }],
      output_config: { format: { type: "json_schema", schema: ENVELOPE_OUTPUT_SCHEMA } },
    }),
  });
  if (!response.ok) {
    console.error(`✘ ${testCase.id}: upstream ${response.status} ${await response.text()}`);
    failures += 1;
    continue;
  }
  const message = await response.json();
  const text = message.content?.find((block: { type: string }) => block.type === "text")?.text ?? "";
  let deltas: Delta[] = [];
  let disambiguations: { mention: string }[] = [];
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
    .concat(disambiguations.map((d: { question?: string }) => (d as { question?: string }).question))
    .filter((value): value is string => typeof value === "string")
    .join("\n")
    .toLowerCase();

  const caseFailures: string[] = [];
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
      case "noPhrasesInContent":
        for (const phrase of assertion.phrases) {
          if (extractedText.includes(phrase.toLowerCase())) {
            caseFailures.push(`content contains '${phrase}'`);
          }
        }
        break;
    }
  }

  if (caseFailures.length > 0) {
    failures += 1;
    console.error(`✘ ${testCase.id} (${testCase.law}): ${caseFailures.join("; ")}`);
  } else {
    console.log(`✔ ${testCase.id}`);
  }
}

console.log(`prompt-suite ${PROMPT_VERSION} on ${modelId}: ${cases.length - failures}/${cases.length} passed`);
Deno.exit(failures > 0 ? 1 : 0);
