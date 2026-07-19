// The structured-output schema for the model's half of the delta envelope
// (docs/extraction.md §1 — the server stamps schemaVersion + utteranceId itself).
// Mirrors the Swift decode boundary 1:1; the client re-validates everything anyway
// (defense in depth, both boundaries fail loudly — NN#7).

const HANDLE = {
  type: "object",
  description: "Exactly one of id (uuid from the request context) or ref (handle created earlier in this envelope).",
  properties: {
    id: { type: "string" },
    ref: { type: "string" },
  },
  additionalProperties: false,
} as const;

const DATE = { type: "string", description: "Strict yyyy-MM-dd" } as const;
const DATE_PRECISION = { type: "string", enum: ["day", "month", "year", "unknown"] } as const;
const CHAPTER_STATE = { type: "string", enum: ["warm", "fine", "quiet", "tense", "complicated"] } as const;

const DELTA_KINDS = [
  {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["upsertPerson"] },
      id: { type: "string" },
      ref: { type: "string" },
      name: { type: "string" },
      relation: { type: "string" },
      mood: { type: "string", enum: ["warm", "fine", "quiet", "tense", "complicated", "drifting"] },
      roleFlags: { type: "array", items: { type: "string", enum: ["confidant", "ally", "witness", "trigger"] } },
      rituals: { type: "array", items: { type: "string" } },
      notesAppend: { type: "string" },
      chapterRefs: { type: "array", items: HANDLE },
    },
    required: ["kind", "name"],
    additionalProperties: false,
  },
  {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["upsertChapter"] },
      id: { type: "string" },
      ref: { type: "string" },
      type: {
        type: "string",
        enum: ["relationship", "family", "friendship", "work", "health", "money", "passion", "privateCorner", "growth", "grief"],
      },
      chapterKind: { type: "string", enum: ["situational", "dimension"] },
      title: { type: "string" },
      iconRef: { type: "string" },
      state: CHAPTER_STATE,
    },
    required: ["kind", "type", "chapterKind"],
    additionalProperties: false,
  },
  {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["addEvent"] },
      ref: { type: "string" },
      chapterRef: HANDLE,
      date: DATE,
      datePrecision: DATE_PRECISION,
      title: { type: "string" },
      body: { type: "string" },
      valence: { type: "string", enum: ["bright", "gold", "neutral", "storm", "soft"] },
      isOpen: { type: "boolean" },
      isUpcoming: { type: "boolean" },
    },
    required: ["kind", "ref", "chapterRef", "datePrecision", "title", "body", "valence", "isOpen", "isUpcoming"],
    additionalProperties: false,
  },
  {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["foldEvent"] },
      eventId: { type: "string" },
      reason: { type: "string" },
    },
    required: ["kind", "eventId", "reason"],
    additionalProperties: false,
  },
  {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["addCommitment"] },
      ref: { type: "string" },
      chapterRef: HANDLE,
      personRef: HANDLE,
      text: { type: "string" },
      dateMade: DATE,
      datePrecision: DATE_PRECISION,
    },
    required: ["kind", "ref", "chapterRef", "text", "datePrecision"],
    additionalProperties: false,
  },
  {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["updateCommitmentStatus"] },
      commitmentRef: HANDLE,
      status: { type: "string", enum: ["held", "broken", "resolved"] },
      evidenceEventRef: HANDLE,
    },
    required: ["kind", "commitmentRef", "status"],
    additionalProperties: false,
  },
  {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["upsertGoal"] },
      id: { type: "string" },
      ref: { type: "string" },
      chapterRef: HANDLE,
      text: { type: "string" },
      targetDate: DATE,
      progressNote: { type: "string" },
    },
    required: ["kind", "text"],
    additionalProperties: false,
  },
  {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["setChapterState"] },
      chapterRef: HANDLE,
      state: CHAPTER_STATE,
    },
    required: ["kind", "chapterRef", "state"],
    additionalProperties: false,
  },
  {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["setPersonMood"] },
      personRef: HANDLE,
      mood: { type: "string", enum: ["warm", "fine", "quiet", "tense", "complicated", "drifting"] },
    },
    required: ["kind", "personRef", "mood"],
    additionalProperties: false,
  },
  {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["addCrossLink"] },
      fromChapterRef: HANDLE,
      toChapterRef: HANDLE,
      note: { type: "string" },
    },
    required: ["kind", "fromChapterRef", "toChapterRef", "note"],
    additionalProperties: false,
  },
  {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["fillSlots"] },
      chapterRef: HANDLE,
      slots: { type: "array", items: { type: "string" } },
    },
    required: ["kind", "chapterRef", "slots"],
    additionalProperties: false,
  },
] as const;

export const ENVELOPE_OUTPUT_SCHEMA = {
  type: "object",
  properties: {
    deltas: { type: "array", items: { anyOf: DELTA_KINDS } },
    disambiguations: {
      type: "array",
      items: {
        type: "object",
        properties: {
          ref: { type: "string" },
          mention: { type: "string" },
          candidateIds: { type: "array", items: { type: "string" } },
          question: { type: "string" },
        },
        required: ["ref", "mention", "candidateIds", "question"],
        additionalProperties: false,
      },
    },
  },
  required: ["deltas", "disambiguations"],
  additionalProperties: false,
} as const;
