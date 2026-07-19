# M1-CONTRACTS — Extraction pipeline + backend proxy (the heart)

<!-- CONTRACT PACKAGE (NN#2): reviewed BEFORE M1 code. STATUS: APPROVED by Xavier 2026-07-19,
     together with docs/extraction.md (THE spec — this package implements it). §8 rulings recorded
     below; §8.3 ruled AGAINST the draft (folded events are included, flagged). Covers seams #1
     (schema/merge — in extraction.md), #3 (prompt stack + softness filter), #4 (server schema).
     Gates: F1 Supabase, F3 transient-plaintext, F4 Claude split-tier — all closed.
     👤 STILL OPEN: PROVISIONING item 2 (Anthropic key with WRITTEN no-training confirmation — a C2
     contractual gate; blocks §7.5 live smoke test + milestone close, not the headless build).
     M0 landed 2026-07-19. API facts verified against the current Claude API reference 2026-07-19
     (structured outputs, model ids, caching semantics). -->

## 1. Scope

**In:** `docs/extraction.md` implemented end-to-end — proxy Edge Function `extract`, client
`ExtractionClient` + strict decode boundary, deterministic merge in `Services/Store/`, awareness
scoring, disambiguation gate + held-delta queue, transcript-fixture corpus green, `prompts/` +
prompt-suite harness with the first never-list red-team cases, ciphertext-blob DB schema + RLS
deployed (may be executed by the separate DB session — the migration files land in THIS repo and
this package is their review).

**Out (explicitly):** chat/prep endpoints (Sonnet-class — contract drafted in M4-CONTRACTS) ·
onboarding UI (M2) · client blob-encryption upload + master key (the sync half of C2/F3 — proposed
for the M2 sign-in slice, open question §8.2) · check-in engine (M6) · live mic (M5).

**Done (ROADMAP):** the fixture corpus (fx-001…fx-011) produces the expected object graphs,
asserted by tests, before any UI polish exists. This milestone is the app.

## 2. Client contract (Swift, mirrors extraction.md §1 exactly)

```swift
// Services/Extraction/ — the ONLY caller of the proxy. NN#7: explicit Codable, no try?.
struct ExtractionRequest: Encodable {
    let schemaVersion: Int            // 1
    let utteranceId: UUID             // client-generated; idempotency key
    let surface: Surface              // onboarding | chapterChat | vent
    let clientTime: Date              // for relative-date resolution
    let locale: String
    let utterance: String
    let context: ExtractionContext    // minimum-necessary, §4
}

struct ExtractionEnvelope: Decodable {
    let schemaVersion: Int
    let utteranceId: UUID
    let deltas: [Delta]               // enum Delta: Decodable — tagged by "kind";
    let disambiguations: [Disambiguation]
}
// Unknown kind / enum / ref → DecodingError, envelope rejected loudly (extraction.md §2).

enum ExtractionError: Error {        // typed proxy errors — never a silent nil
    case rateLimited(retryAfter: TimeInterval?)
    case upstreamUnavailable
    case schemaMismatch(serverVersion: Int)
    case unauthorized
    case transport(underlying: Error)
}
```

The merge (`Services/Store/MergeEngine`) consumes `ExtractionEnvelope` values only — it is fully
testable against fixtures with no network (LOOP-safe once this package is ratified).

## 3. Proxy contract — Supabase Edge Function `extract` (C5)

- `POST /functions/v1/extract` · Supabase auth JWT required · request/response = §2 shapes, JSON.
- **Model:** Haiku-class per F4. Current id `claude-haiku-4-5` — pinned in server config
  (one env var), never in the client. (Sonnet-class = `claude-sonnet-5` when M4 adds chat.)
- **Structured output:** the delta envelope is enforced with `output_config.format`
  (`json_schema`, `additionalProperties: false`) — the API layer guarantees schema-valid JSON, the
  client re-validates anyway (defense in depth). Schema limitations respected by design: no
  recursion, no numeric constraints (we compute all numbers anyway — C4).
- **In-memory only (C2):** the function holds utterance + context in memory for the duration of
  the call. **Log config is part of this review:** logs carry `utteranceId`, timing, token counts,
  model id, error codes — NEVER utterance text, context, or deltas. No content-level analytics.
- **Errors:** typed JSON `{ "error": { "code": "...", "message": "..." } }` mapping 1:1 to
  `ExtractionError`. Anthropic 429/529 → `rate_limited`/`upstream_unavailable` with retry-after.

## 4. Context assembly & the prompt stack (seam #3)

Transient-plaintext (F3) means **the server can read nothing at rest** — all context the model
needs travels with the request, minimum-necessary:

```
ExtractionContext {
  people:      [{ id, name, relation }]                     // known people, for id-matching
  chapters:    [{ id, type, title, state, filledSlots }]    // so fillSlots/upserts target correctly
  openCommitments: [{ id, personId?, text, dateMade }]      // for status transitions
  recentEvents:    [{ id, chapterId, title, date, isOpen, isHealed }] // last N, folded INCLUDED,
}                                                           // flagged (§8.3 ruling)
```

Prompt layers, assembled server-side per whitepaper §14 — templates live in `prompts/`, versioned:

1. Extraction persona + **softness laws** + safety rules (static)
2. Surface template (onboarding / chapterChat / vent — static per surface)
3. The delta JSON-schema instructions + slot tables (static)
4. Serialized `ExtractionContext` (per-user, volatile)
5. The utterance (volatile)

**Prompt caching under C2 — reviewed rule:** `cache_control` may sit ONLY at the end of layer 3.
Layers 1–3 are our static text — cacheable, cache-safe, and shared across all users. Layers 4–5
contain user life-content and are **never cached** (an ephemeral provider-side cache entry of user
context would blur "processed, not stored"; we simply don't create one).

**The C3 filter is structural (§8.3 ruling, 2026-07-19):** folded events travel in the extraction
context WITH `isHealed: true` — so an utterance referencing a folded memory id-matches instead of
re-extracting a duplicate. Safety is held by the schema, not the flag alone: the delta vocabulary
contains no unfold and no destructive op (extraction.md §1), so the worst a model can do with a
folded event is reference its id. The prompt's folded-events rule (match, never re-raise, never
re-open) is layer-1 static text with a prompt-suite case; when M4 adds chat context the same
`isHealed` flag drives the `do-not-raise-unprompted` rule at prompt assembly — a code path with a
prompt-suite test, never a model instruction alone.

## 5. Server schema (seam #4) — BASELINE DEPLOYED 2026-07-19

Superseded by the deployed baseline: **`supabase/README.md` + `supabase/migrations/`** (project
`biwwvntcofpjjbqvfkby`; deployed at Xavier's direction by the DB session, RLS verified). It is
stricter than this package's original sketch — notably **no kind/object-type column** on
`encrypted_blobs` (record-type counts are story-shape metadata; minimum-leak posture), tombstone
`deleted_at` for sync deletions, hard erase = row deletion via auth-user cascade.

Remaining for M1/M2 sync-seam review (amendments only through contract review): envelope format
(nonce/ciphertext/tag framing behind `envelope_version`), per-blob conflict strategy over the
`updated_at` cursor, and whether per-collection sync justifies adding a type column.

## 6. `prompts/` + the prompt suite (new organ)

- `prompts/extract/v001-*.md` — every prompt template versioned in-repo; the Edge Function embeds
  a pinned version; bumping = PR.
- `prompt-suite/` — red-team harness run on **every prompt change**: never-list cases (folded
  moment bait, adjudication bait "should I break up with him?", surveillance bait "check his
  followers", guilt-copy bait) asserted against live model output on the CI key. First cases land
  with this milestone; every §19 rule gets at least one case before its surface ships.

## 7. Acceptance + verification

1. **The fixture corpus green** (extraction.md §5, fx-001…fx-011) — merge + scoring, no network.
2. **Decode boundary tests** — malformed/hostile envelopes rejected loudly; no partial writes.
3. **Disambiguation gate tests** — hold, resolve, backstop (fx-004/005).
4. **Idempotency** — fx-009 + crash-mid-merge replay.
5. **Live smoke test** (needs provisioning): the fx-001 transcript through the REAL proxy + model
   → envelope decodes and merges (asserts the schema holds against the live model, not just fixtures).
6. **C2 audits as tests/checklists:** grep-audit proves no Anthropic key or prompt text in the app
   target; Edge Function log output reviewed against §3's log rule; cache placement reviewed
   against §4's rule; the written no-training confirmation filed before this milestone closes.
7. **Never-tests:** fx-011 (no counts on sensitive types) + the first prompt-suite red-team runs.

Device-verify: none — M1 is deliberately headless (mic/UI come later). LOOP: once this package +
extraction.md are ratified, the merge engine, scoring, and decoders are loop-safe work items.

## 8. Rulings (Xavier, 2026-07-19 — this review)

1. **Model ids — CONFIRMED.** `claude-haiku-4-5` (extract) pinned now, `claude-sonnet-5` reserved
   for M4 chat — both as server env config (`EXTRACT_MODEL_ID`), never in the client.
2. **Blob upload timing — DEFERRED TO M2.** DB schema is deployed (§5); the client
   encrypt-and-upload path + master-key creation land with the M2 sign-in slice ("sign-in attaches
   backup").
3. **Folded events in extraction context — INCLUDED, FLAGGED (overrides the draft).** Folded
   events travel with `isHealed: true` from M1 so folded memories id-match instead of duplicating.
   Structural safety analysis in §4; prompt-suite case required.
4. **Schema evolution — CONFIRMED server-led.** Client sends its `schemaVersion`; the proxy
   answers in that version or returns `schema_mismatch` (forcing an app update), never silently
   translates.
5. **Onboarding acknowledgments — CONFIRMED separate.** A light `acknowledge` endpoint contract is
   drafted in M2-CONTRACTS (voice register is a human-ruled seam), not smuggled into `extract`.

### Amendments made at ratification (mechanical, no scope change)

- **Disambiguation carries a binding `ref`** (extraction.md §1): the ambiguous mention gets a local
  handle so held deltas have an exact binding target at resolution — the wire needs it; prose
  alone couldn't say *which* deltas were held.
- **`upsertPerson.chapterRefs` (attach-only)** — the delta vocabulary had no person↔chapter link;
  fx-001 requires it. Attach-only keeps the vocabulary non-destructive (detach = user action).
- **`updateCommitmentStatus.commitmentRef` takes id or ref** (was id-only) — a promise disclosed
  and broken in one utterance must be status-updatable inside its own envelope (fx-001).
- **Structured census answers** (name/age/city/occupation/fork chips + fields) write via typed
  `KeptStore` commands — C1 governs *utterances*; a chip tap is not an utterance. Free-text
  answers go through extraction unchanged.
- **The proxy stamps envelope identity** (`schemaVersion` + `utteranceId` echoed from the request,
  C4-consistent): the model's structured output is only `{deltas, disambiguations}` — a
  per-request `const` in the output schema would defeat grammar caching for zero safety gain.
- **Merge-engine storage:** `Chapter.filledSlots`, `Event.healedReason`, plus two internal models —
  `AppliedUtterance` (idempotency record, spec §3 rule 1) and `HeldDeltaBatch` (persisted
  disambiguation queue, spec §2 atomicity exception). All behind `Services/Store/` (C7); none
  surface in read models except `filledSlots` (context assembly needs it).
