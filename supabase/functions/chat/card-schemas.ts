// Output schemas for /chat structured outputs (M4-CONTRACTS §4). One schema per mode/stage —
// each prep stage's schema admits ONLY that stage's card kind, and EVERY schema keeps `text`
// required and `card` nullable so a crisis response is never blocked by a card grammar
// (safety > structure — the crisis-path guarantee, asserted keylessly by assemble_test.ts).
//
// Numeric bounds (2–4 answers, ≤3 chips) are deliberately NOT schema-enforced here — the M1
// posture (no numeric constraints in output schemas) — they are prompt rules re-validated by
// the client's strict decoder, which rejects violations loudly.

const RECEIPT_REF = {
  type: "object",
  additionalProperties: false,
  required: ["id", "note"],
  properties: {
    id: { type: "string", description: "EXACT id of a commitment or event from the record" },
    note: { type: "string" },
  },
};

const CHIPS = {
  type: "array",
  items: { type: "string" },
  description: "0-3 short first-person quick replies the user might say next",
};

const CARD_SCHEMAS: Record<string, object> = {
  reframe: {
    type: "object",
    additionalProperties: false,
    required: ["kind", "goal", "receipts"],
    properties: {
      kind: { type: "string", enum: ["reframe"] },
      goal: { type: "string" },
      receipts: { type: "array", items: RECEIPT_REF },
    },
  },
  likelyAnswers: {
    type: "object",
    additionalProperties: false,
    required: ["kind", "answers"],
    properties: {
      kind: { type: "string", enum: ["likelyAnswers"] },
      answers: {
        type: "array",
        description: "2-4 entries",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["theirLine", "read", "counter"],
          properties: {
            theirLine: { type: "string" },
            read: { type: "string" },
            counter: { type: "string" },
          },
        },
      },
    },
  },
  perspective: {
    type: "object",
    additionalProperties: false,
    required: ["kind", "incidentRead", "patternRead", "signals", "grounding"],
    properties: {
      kind: { type: "string", enum: ["perspective"] },
      incidentRead: { type: "string" },
      patternRead: { type: "string" },
      signals: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["text", "present"],
          properties: {
            text: { type: "string" },
            present: { type: "boolean" },
          },
        },
      },
      grounding: { type: "string" },
    },
  },
  keepCard: {
    type: "object",
    additionalProperties: false,
    required: ["kind", "items", "closingLine"],
    properties: {
      kind: { type: "string", enum: ["keepCard"] },
      items: { type: "array", items: RECEIPT_REF },
      closingLine: { type: "string" },
    },
  },
  openingClose: {
    type: "object",
    additionalProperties: false,
    required: ["kind", "opening", "close"],
    properties: {
      kind: { type: "string", enum: ["openingClose"] },
      opening: { type: "string" },
      close: { type: "string" },
    },
  },
};

export const PREP_STAGES = Object.keys(CARD_SCHEMAS);

/** The model's output schema for a turn. `mode` = "chat" | "prep"; `stage` required for prep. */
export function outputSchemaFor(mode: string, stage: string | null): object {
  if (mode === "prep" && stage !== null && CARD_SCHEMAS[stage]) {
    return {
      type: "object",
      additionalProperties: false,
      required: ["text"],
      properties: {
        text: { type: "string", description: "Pom's spoken reply — always present" },
        card: {
          anyOf: [CARD_SCHEMAS[stage], { type: "null" }],
          description: "The stage's card — null when safety requires plain text",
        },
        chips: CHIPS,
      },
    };
  }
  return {
    type: "object",
    additionalProperties: false,
    required: ["text"],
    properties: {
      text: { type: "string", description: "Pom's spoken reply — always present" },
      chips: CHIPS,
    },
  };
}
