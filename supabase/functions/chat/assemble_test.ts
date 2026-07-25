// KEYLESS assembler tests (M4-CONTRACTS §8.6): the C3 folded quarantine and the crisis-path
// schema guarantee, proven deterministically — no network, no ANTHROPIC_API_KEY.
//   deno test supabase/functions/chat/assemble_test.ts

import { assembleContextBlock, SEALED_MEMORIES_HEADER, type WireChatContext } from "./assemble.ts";
import { outputSchemaFor, PREP_STAGES } from "./card-schemas.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

const CONTEXT: WireChatContext = {
  userName: "Maya",
  chapter: { id: "c-1", type: "relationship", title: "Daniel", state: "tense", awarenessPct: 71, filledSlots: [] },
  people: [{
    id: "p-1",
    name: "Daniel",
    relation: "boyfriend",
    mood: "tense",
    roleFlags: [],
    rituals: [],
    notes: "",
    priority: 5,
  }],
  events: [
    {
      id: "e-open",
      title: "The credit thing",
      body: "Second time it happened.",
      date: "2026-07-18",
      valence: "storm",
      isOpen: true,
      isHealed: false,
      isUpcoming: false,
    },
    {
      id: "e-sealed",
      title: "The March bump",
      body: "A fight about the weekend.",
      date: "2026-03-02",
      valence: "storm",
      isOpen: false,
      isHealed: true,
      healedReason: "we talked it through, I forgave it",
      isUpcoming: false,
    },
  ],
  commitments: [{ id: "cm-1", personId: "p-1", text: "no following girls", dateMade: "2026-07-06", status: "held" }],
  goals: [],
  crossLinks: [],
};

Deno.test("folded events render ONLY inside the sealed block (C3 quarantine)", () => {
  const block = assembleContextBlock(CONTEXT);
  const sealedAt = block.indexOf(SEALED_MEMORIES_HEADER);
  assert(sealedAt >= 0, "sealed block missing");
  const before = block.slice(0, sealedAt);
  const after = block.slice(sealedAt);

  assert(before.includes("The credit thing"), "open event must be in the open record");
  assert(!before.includes("The March bump"), "folded event leaked into the open record");
  assert(after.includes("The March bump"), "folded event missing from the sealed block");
  assert(!after.includes("The credit thing"), "open event leaked into the sealed block");
  assert(after.includes("NEVER mention them unless the user brings one up first"), "do-not-raise rule missing");
});

Deno.test("no folded events → no sealed block at all", () => {
  const context = { ...CONTEXT, events: CONTEXT.events.filter((event) => !event.isHealed) };
  const block = assembleContextBlock(context);
  assert(!block.includes(SEALED_MEMORIES_HEADER), "sealed block must not render empty");
});

Deno.test("every output schema keeps text required and card nullable (crisis never schema-blocked)", () => {
  const schemas = [
    outputSchemaFor("chat", null),
    ...PREP_STAGES.map((stage) => outputSchemaFor("prep", stage)),
  ] as Array<{ required: string[]; properties: Record<string, { anyOf?: Array<{ type?: string }> }> }>;

  assert(schemas.length === 6, `expected 6 schemas, got ${schemas.length}`);
  for (const schema of schemas) {
    assert(schema.required.length === 1 && schema.required[0] === "text", "only text may be required");
    const card = schema.properties.card;
    if (card) {
      const allowsNull = card.anyOf?.some((variant) => variant.type === "null") ?? false;
      assert(allowsNull, "card must be nullable in every stage schema");
    }
  }
});

Deno.test("each prep stage's schema admits only that stage's card kind", () => {
  for (const stage of PREP_STAGES) {
    const schema = outputSchemaFor("prep", stage) as {
      properties: { card: { anyOf: Array<{ properties?: { kind?: { enum?: string[] } } }> } };
    };
    const kinds = schema.properties.card.anyOf
      .flatMap((variant) => variant.properties?.kind?.enum ?? []);
    assert(kinds.length === 1 && kinds[0] === stage, `stage ${stage} schema admits ${kinds}`);
  }
});
