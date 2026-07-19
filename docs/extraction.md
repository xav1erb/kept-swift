# Kept — Extraction: THE spec

<!-- THE load-bearing spec (APPROACH: "the signal-score.md of this app"). STATUS: RATIFIED by
     Xavier 2026-07-19 with the M1-CONTRACTS package (§8 rulings recorded there; folded events are
     INCLUDED in extraction context, flagged `isHealed` — §8.3 ruling). The extraction schema +
     merge rules are the #1 human-owned seam (NN#9); amendments only through contract review.
     Sources: whitepaper §3/§14, C1/C3/C4, F4 (Claude split-tier), F11. Wire format is the contract
     between the proxy and the client; the Swift Codable types mirror it 1:1. -->

## 0. The one pipeline (C1)

Every utterance from every surface flows through exactly one path:

```
utterance ──▶ proxy /extract (Haiku-class, server-assembled prompt, structured output)
          ──▶ delta envelope (strict schema, versioned)
          ──▶ client: strict decode (NN#7) ─▶ validate ─▶ deterministic merge ─▶ Services/Store
          ──▶ UI reacts (reads only)
```

The model **proposes**; typed Swift code **disposes** (C4). No surface writes model objects any
other way. The user-facing face of this pipeline is *filing* (LEXICON).

## 1. The delta envelope (wire format, `schemaVersion: 1`)

```json
{
  "schemaVersion": 1,
  "utteranceId": "<uuid, client-generated>",
  "deltas": [ { "kind": "...", ... } ],
  "disambiguations": [ { ... } ]
}
```

- Enforced server-side via structured outputs (`output_config.format`, `json_schema`,
  `additionalProperties: false`) — the model cannot emit an off-schema envelope.
- The client still decodes strictly and validates referential integrity: **defense in depth, both
  boundaries fail loudly.** A swallowed delta is a lost piece of someone's life (NN#7).

### Entity references

Two reference forms, used consistently in every delta:
- `id` — UUID of an entity that already exists in the store. The model only knows these because the
  request context listed them; an `id` not present in the request context is a validation error.
- `ref` — a local handle (`"p1"`, `"c1"`, `"e2"`) for an entity **created earlier in this same
  envelope**. Forward references are invalid. The merge assigns real UUIDs.

### Delta kinds

**The vocabulary contains no destructive operation — no delete, no unfold, no body-overwrite.
Softness and safety are structural (C3): the model cannot propose what the schema cannot express.**

| kind | payload | notes |
|---|---|---|
| `upsertPerson` | `ref` XOR `id`, `name`, `relation?`, `mood?`, `roleFlags?[]`, `rituals?[]`, `notesAppend?`, `chapterRefs?[]` | `notesAppend` appends — never replaces the profile. `chapterRefs` is **attach-only** (ratification amendment — the wire needs person↔chapter linking; detachment is a user action, never a delta). New-person path is gated (§3). |
| `upsertChapter` | `ref` XOR `id`, `type`, `chapterKind`, `title?`, `iconRef?`, `state?` | `title` in the user's words (whitepaper); model may propose, merge stamps `createdAt`/`lastTouchedAt`. |
| `addEvent` | `ref`, `chapterRef`, `date?`, `datePrecision`, `title`, `body`, `valence`, `isOpen`, `isUpcoming` | `source` is NOT model-set — the client stamps it from the surface that sent the utterance. |
| `foldEvent` | `eventId`, `reason` | Proposes `isHealed = true`. **One-way**: there is no unfold kind — unfolding/refolding is a user tap only. Applied only when the user's own words indicate resolution (fixture-tested). |
| `addCommitment` | `ref`, `chapterRef`, `personRef?`, `text`, `dateMade?`, `datePrecision` | "Receipts matter": `dateMade` = stated date if given, else the merge stamps utterance date with `datePrecision: "day"`. |
| `updateCommitmentStatus` | `commitmentRef`, `status`, `evidenceEventRef?` | held → broken/resolved transitions; evidence links to an event in this envelope or the store. `commitmentRef` takes id or ref (ratification amendment): a promise disclosed and broken in ONE utterance must be status-updatable inside its own envelope (fx-001). |
| `upsertGoal` | `ref` XOR `id`, `chapterRef?`, `text`, `targetDate?`, `progressNote?` | |
| `setChapterState` | `chapterRef`, `state` | warm/fine/quiet/tense/complicated — the soft vocabulary only. |
| `setPersonMood` | `personRef`, `mood` | includes `drifting`. |
| `addCrossLink` | `fromChapterRef`, `toChapterRef`, `note` | e.g. Insecurities ↔ Relationship. |
| `fillSlots` | `chapterRef`, `slots: [slotKey]` | The model reports which awareness slots this utterance filled. **It never emits a percentage** — scoring is deterministic (§4, C4/C6). |

Dates: ISO-8601 date strings resolved by the model against `clientTime` from the request;
`datePrecision ∈ day | month | year | unknown`. Unresolvable relative dates → omit `date`, merge
falls back to utterance date at `day` precision.

### Disambiguation (the C4 gate)

```json
{ "ref": "p1", "mention": "Sara", "candidateIds": ["<uuid>", "<uuid>"], "question": "work-Sara, not Instagram-Sara, right?" }
```

- The ambiguous person is assigned a local `ref` like any created entity; the disambiguation
  carries that `ref` as its **binding handle** (ratification amendment — the wire needs an exact
  target for resolution). Any delta referencing that `ref` is **held**, not applied — parked in a
  pending queue keyed by `utteranceId` + `ref`. Everything else in the envelope applies normally.
- The question is asked in Pom's voice on the originating surface; the user's answer resolves the
  held deltas — binds the `ref` to an existing person id, or confirms a new person — which then
  merge.
- **Deterministic backstop:** even when the model does NOT flag it, the merge refuses to create a
  new `Person` whose normalized name matches an existing person — it converts that creation into a
  disambiguation itself. Two Saras can never silently merge or silently duplicate; the model's
  diligence is never the mechanism (C3 philosophy applied to C4).

## 2. Validation (client-side, before any merge)

Reject the **entire envelope** — loudly, with the `utteranceId` logged for re-extraction — when any
of: unknown `schemaVersion` · unknown `kind` · unknown enum value · `id` not in the request context
we sent · unresolvable or forward `ref` · `foldEvent` targeting a non-existent event · slot key not
in the chapter type's schema (§4). No partial application, no `try?`, no silently-dropped delta.
Atomicity exception: disambiguation-held deltas (§1) are parked, not dropped — they survive app
restarts (persisted with the draft state) and apply on resolution.

## 3. The deterministic merge

Order within an envelope: **persons → chapters → events → commitments → goals → crossLinks →
states → foldEvent → fillSlots**, then recompute stored numbers (`awarenessPct` per touched
chapter, `lastTouchedAt`) and stamp `source` on new events (C6: computed at write, stored, never
re-derived in views).

Rules:
1. **Idempotent.** The store records applied `utteranceId`s; a duplicate envelope is a no-op.
   (Retries after a mid-merge crash are therefore safe.)
2. **Upsert semantics.** `id` present → update only the provided fields; absent fields are
   untouched. `ref` → create.
3. **Person creation is gated** (§1 backstop). Person merges NEVER happen automatically — a merge
   of two Person records is not even expressible as a delta; it exists only as a user-confirmed
   disambiguation resolution.
4. **Folding is one-way and conservative.** `foldEvent` flips `isHealed` false→true only; the
   `reason` must quote or paraphrase the user's own words (prompt rule + fixture). Folded events
   stay available to pattern analysis; the do-not-raise-unprompted flag is enforced at prompt
   assembly (M1-CONTRACTS §prompt-stack), never relied on the model's goodwill.
5. **No model-estimated numbers.** `awarenessPct` is recomputed by §4 whenever `fillSlots` or
   chapter creation touches a chapter. Streak math is day-close logic (M0 store), untouched here.

## 4. Awareness scoring (C4/C6; slot schemas are seam #5 — Xavier rules on these tables)

`awarenessPct = round(100 × filledSlots / totalSlots)`, computed at merge, stored on the chapter.
Grades (display only): ≥90 mint "fully aware" · 55–89 gold · <55 lilac "tell me more". Decay after
long inactivity is a **scheduled write** (M6 cron), never a read-time computation.

Proposed slot tables (counts match the whitepaper §6 question-sequence lengths; relationship slots
are verbatim from §3):

| type | slots | shown as count? |
|---|---|---|
| relationship (7) | partnerName · duration · livingSituation · originStory · currentState · positives · openIssues | yes |
| family (6) | keyPeople · homeBase · dynamics · currentState · positives · openIssues | yes |
| friendship (5) | keyPeople · history · currentState · positives · openIssues | yes |
| work (6) | role · place · keyPeople · ambitions · currentState · openIssues | yes |
| health (5) | focusAreas · routines · currentState · goals · openIssues | yes |
| money (4) | situation · habits · goals · openIssues | yes |
| passion (4) | what · why · cadence · currentState | yes |
| growth (5) | focus · why · practices · progress · blockers | yes |
| privateCorner (3, internal) | topic · feelings · needs | **NEVER** (§19 never-test) |
| grief (4, internal) | whoOrWhat · relationship · whereYouAre · support | **NEVER** (§19 never-test) |

Sensitive types still need internal slots (awareness % must exist for their pins) — the never-rule
is about *display*: no question count, no slot list, ever surfaces in their flows. That rule is a
type-level property (`ChapterType.isSensitive`) checked by a never-test, not copy discipline.

## 5. Transcript-fixture corpus (the M1 done-bar)

Each fixture = input transcript (utterance sequence + request contexts) + the **exact expected
object graph**, asserted by Swift Testing against the real merge into a real (test) store. The
corpus is the acceptance test: M1 is done when it is green **before any UI polish exists** (NN#4).

| id | fixture | asserts |
|---|---|---|
| fx-001 | Onboarding, focus fork, the Daniel disclosure (whitepaper script verbatim) | UserProfile fields; relationship Chapter with AI title; Person Daniel; Commitment "no following girls" dated Jul 6; pinned `isUpcoming` talk Event; awareness % matches slot table |
| fx-002 | Onboarding, full fork | all census blocks → expected graph; followupQueue empty |
| fx-003 | Three-topic vent (mom / work / money) | exactly 3 chapters touched; filing summary lists exactly those 3; no 4th write |
| fx-004 | Two Saras | disambiguation raised; ALL Sara-deltas held; nothing auto-merged; resolution applies held deltas correctly |
| fx-005 | Name collision the model missed | merge's deterministic backstop converts the create into a disambiguation |
| fx-006 | Commitment lifecycle | made (dated) → later utterance breaks it with evidence ref; status transitions correct |
| fx-007 | Positive anchor (Q6) | bright Events created; keep-card material present; valence correct |
| fx-008 | Folding | user's own words of forgiveness → `foldEvent` applies; a *Pom-initiated* fold attempt fixture asserts it does NOT |
| fx-009 | Idempotent replay | same envelope twice → byte-identical graph |
| fx-010 | Poisoned envelope (unknown kind / bad ref / bad slot) | loud rejection; store untouched; error surfaced with utteranceId |
| fx-011 | Sensitive-type creation (grief) | internal slots fill; no count exposed anywhere in the read models (never-test) |

Corpus grows with every incident: any production extraction bug lands here as a fixture the same
day, alongside the `Services/Store/CLAUDE.md` gotcha entry.
