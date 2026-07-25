# M4-CONTRACTS — Chapter detail (chat · prep mode · timeline)

<!-- CONTRACT PACKAGE (NN#2): reviewed BEFORE M4 code. STATUS: APPROVED by Xavier 2026-07-23 —
     all four §9 rulings closed on the recommended options; record in §10.
     Sources: whitepaper §7 (chat + prep), §8 (timeline), §14 (AI system + safety, ships v1),
     §19 never-list; contracts C1 (one pipeline — chat messages are utterances), C2 (in-flight
     plaintext only, log rule), C3 (softness structural), C4 (stage machine computes, model
     narrates), C5 (proxy owns AI), C7/F11, C8. Seams touched: #3 prompt stack & safety (the BIG
     one — chat persona, prep prompts, crisis routing land here), #4 server schema (new `chat`
     Edge Function), #1 store (new ChatMessage model + Event arming fields — reviewed in §2).
     Standing rulings that bind this package: M1 §8.1 (chat model = `claude-sonnet-5`, env
     `CHAT_MODEL_ID`, never in the client) · M1 §8.3 (folded events travel flagged; at chat the
     same flag drives do-not-raise-unprompted AT PROMPT ASSEMBLY — a code path with tests) ·
     M2 §4 (`/acknowledge` was deferred to "M4 chat or the followupQueue ask" — resolved below:
     chat replies come from `/chat`; `/acknowledge` stays deferred, see §1 out-scope) · M3 §8.3
     (pin tap → straight to chapter; preview sheet = M4 polish item, non-gating).
     👤 Live prompt-suite runs still gate on PROVISIONING item 2 (key + written no-training
     confirmation) — same as M1; the headless build does not. -->

## 1. Scope

**In:** `Features/ChapterDetail` — header (back · icon · title · typed status line · state glyph)
+ two tabs. **Chat tab:** persistent per-chapter conversation with Pom, full chapter context
injected server-side (folded items flagged do-not-raise), composer ("tell me anything…"),
contextual quick-reply chips after Pom turns, loud-but-soft failure states. **Prep mode** (the
flagship): reframe → likely-answers card → keep-card → opening + close, perspective calibration on
request; completing prep arms the post-event check-in (stored flag — M6 delivers). **Timeline
tab:** intro card, gradient line, the typed node grammar (bright/gold memories · neutral receipts ·
the ONLY pulsing open-storm node · dashed upcoming · folded 🌱 pills with expand/refold), footer
promise verbatim. Server: the **`chat` Edge Function** (Sonnet-class, C5) + `prompts/chat/`
templates + prompt-suite chat cases (crisis, adjudication, folded-no-reraise-chat, diagnosis).
Store: §2 amendments. Polish item (non-gating, M3 §8.3 hand-off): the pin preview sheet — a thin
sheet over the same header read models; built only after core is device-verified, dropped with a
FIGHT-LIST row if it doesn't earn its place.

**Out (explicitly):** voice input in the composer (M5 — VoiceCapture walled module; composer is
text-only, no dead mic button) · the River (M5) · check-in *delivery* + post-event reply routing
(M6 — M4 only stores the armed intent) · win nodes on the timeline (M7 — the node grammar leaves
room) · `/acknowledge` (stays deferred: chat replies are `/chat`'s job; the followupQueue *ask
surface* is not in M4) · chapter-closing ceremony (M8) · streaming replies (§9 Q4 records the v1
choice as a decision, not an accident).

**Done (ROADMAP M4):** prep mode renders all designed components from a seeded chapter; folded
events never surface in chat unprompted (prompt-suite case); fold behavior exact.

## 2. Data-model amendments (seam #1 — this section IS the review)

```swift
// NEW @Model — chapter chats are the persistent memory (whitepaper §10). §9 Q3 rules on backup.
@Model final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var chapter: Chapter?              // required via command surface (house gotcha 2026-07-19)
    var author: ChatAuthor             // pom | user (nonisolated String enum)
    var text: String
    var card: StoredPrepCard?          // Codable payload for prep-component messages (§5)
    var date: Date
}
```

- **`Event` gains `preparedAt: Date?` + `checkInArmed: Bool`** (defaults nil/false — lightweight
  migration). `EventSnapshot` mirrors both. `NextUpCard.prepArmed` (M3, hardwired false) now reads
  `preparedAt != nil`; `checkInArmed` is the M6 contract surface. No timer, no countdown — the
  fields are a timestamp and a bool by construction (C3).
- **Commands:** `appendChatMessage(chapterId:author:text:card:) -> UUID` ·
  `markPrepared(eventId:)` · `armPostEventCheckIn(eventId:)`. **Reads:**
  `chatMessages(inChapter:) -> [ChatMessageSnapshot]` (deterministic `(date, id)` sort) ·
  `chatContext(chapterId:) -> ChatContext` (§3). No unfold command exists anywhere — timeline
  expand/refold is view-local state (§7), structurally unable to persist.
- **`PendingUtterance` gains `chapterId: UUID?`** and `enqueueUtterance(surface:nodeId:text:)`
  gains the parameter. Closes a latent M1 gap this milestone would hit for real: the chapterChat
  extraction prompt reads "default every delta to the open chapter (listed first in context)", but
  `extractionContext()` has no open-chapter notion — it becomes
  `extractionContext(openChapterId: UUID? = nil)` listing that chapter first. Fixture added.
- **Backup (if §9 Q3 = backed up):** interior type tag `"chatMessage"` joins the M2 §7.3 envelope
  — additive (the tag lives inside the ciphertext; server stays type-blind), `envelope_version`
  unchanged. Restore rebuilds conversations. One message = one blob, drained by the existing
  write-behind uploader.

## 3. Client wire contract — `Services/Chat/` (mirrors the M1 §2 style)

```swift
struct ChatRequest: Encodable {
    let schemaVersion: Int             // chat wire v1 (independent of the extraction version)
    let turnId: UUID                   // client-generated; idempotency/log key — never content
    let chapterId: UUID
    let mode: ChatMode                 // .chat | .prep(stage: PrepStage)   (§5 stage machine)
    let clientTime: Date
    let locale: String
    let userText: String?              // nil only for client-initiated stage advances (§5)
    let history: [ChatTurn]            // last ≤30 turns: { author, text } — cards flattened to text
    let context: ChatContext
}

struct ChatContext: Codable {          // chapter-scoped, fuller than ExtractionContext — chat needs
    let userName: String               // the whole room; still minimum-necessary (one chapter only)
    let chapter: ChapterContext        // id, type, title, state, awarenessPct, filledSlots
    let people: [PersonContext]        // full profiles: relation, mood, roleFlags, rituals, notes,
    let events: [EventContext]         //   priority — likely-answers generates from these (§14)
    let commitments: [CommitmentContext] // ALL statuses + dateMade — receipts include broken ones
    let goals: [GoalContext]
    let crossLinks: [CrossLinkContext] // note + other chapter's title only
}
// EventContext carries body, valence, isOpen, isUpcoming AND isHealed + healedReason — folded
// events travel (M1 §8.3) and the server assembler quarantines them (§4).

struct ChatEnvelope: Decodable {       // strict decode, loud failure (NN#7)
    let schemaVersion: Int
    let turnId: UUID                   // echoed; mismatch = rejection
    let text: String                   // Pom's words — ALWAYS present (crisis is never schema-blocked)
    let card: PrepCard?                // §5 — only in prep mode, only the requested stage's kind
    let chips: [String]                // 0–3 quick-reply suggestions; >3 = envelope rejected
}

protocol ChatServicing { func send(_ request: ChatRequest) async throws -> ChatEnvelope }
// LiveChatClient → POST functions/v1/chat (bearer token, same shape as LiveExtractionClient);
// UnconfiguredChatClient throws; tests use ScriptedChat (canned JSON per userText — the
// fake-the-source pattern; the real decoder always runs). ChatError mirrors ExtractionError.
```

**The chat turn (C1 — no second write path):** sending a message does two *independent* things
(§9 Q1): (1) `appendChatMessage` + `enqueueUtterance(surface: .chapterChat, chapterId:)` +
immediate flush through the existing `UtteranceFlusher` → `/extract` → merge — the durable filing
path, unchanged machinery, survives failures in the queue; (2) `ChatServicing.send` → Pom's reply
bubble — ephemeral; failure = soft retry on the bubble, the user's words are already kept. Chip
taps that insert user text ARE utterances (they land in the transcript); stage-advance taps are
not (C1 governs utterances — M1 ratification precedent).

## 4. Proxy contract — Supabase Edge Function `chat` (seams #3 + #4)

- `POST /functions/v1/chat` · Supabase JWT (`verify_jwt` ON) · §3 shapes · **model
  `CHAT_MODEL_ID` = `claude-sonnet-5`** (M1 §8.1, already ruled).
- **Prompt layers (whitepaper §14), assembled server-side, templates in `prompts/chat/` versioned:**
  (1) Pom persona + softness laws + **safety rules: crisis routing (self-harm/abuse → drop script,
  care in character, professional resources, never gated or delayed), therapy boundary, no
  adjudication, no diagnosis language, no surveillance help** — static; (2) mode/stage template
  (§5) — static; (3) card JSON-schema instructions — static, single `cache_control` breakpoint at
  its end (M1 §4 rule: static layers cacheable, user layers NEVER cached); (4) serialized
  `ChatContext` + history; (5) the user turn.
- **The C3 folded quarantine is a code path:** the assembler splits `events` on `isHealed` — open
  events render into the timeline block; folded events render ONLY into a fenced `SEALED MEMORIES`
  block carrying the do-not-raise-unprompted rule (respond gently if the USER raises one; never
  volunteer). Enforced by a **Deno unit test on the pure assembler** (runs keyless in CI: a folded
  event's title appears in the sealed block and nowhere else) + the live prompt-suite case.
- **Structured output per stage:** `output_config.format` json_schema; each prep stage's schema
  admits ONLY that stage's card kind — and **every schema, every mode, keeps `text` required and
  `card` nullable**, so a crisis response is never blocked by a card grammar (safety > structure).
- **Log rule (C2, code-reviewed here like M1 §3):** logs carry turnId, mode/stage, timing, token
  counts, model id, error codes — NEVER userText, history, context, or reply content.
- Errors: the M1 typed-JSON error shape, mapped to `ChatError` 1:1.

## 5. Prep mode (the flagship — C4: the stage machine computes, the model narrates)

**A client-side typed stage machine** (`PrepStage`: `reframe → likelyAnswers → keepCard →
openingClose`, plus `perspective` enterable on request from any stage and returning to it). The
client advances stages — from chips ("show me what he might say") or a continue affordance — and
each request names its stage; the server's stage template + output schema make any other card kind
unrepresentable. Prep renders inline in the chat as card-bearing Pom messages (whitepaper's three
screens ARE the chat surface), persisted like any message.

Card payloads (wire + `StoredPrepCard`, 1:1):

- `reframe { goal: String, receipts: [ReceiptRef] }` — "you're not going in to win…" grounded in
  the record. **`ReceiptRef { id: UUID, note: String }` must resolve to a context
  commitment/event or the envelope is rejected (NN#7): an invented receipt is structurally
  unrenderable** — the UI draws title/date from the STORE, the model only annotates.
- `likelyAnswers { answers: [{ theirLine, read, counter }] }` — 2–4 entries, generated from the
  Person profile + commitment history in context; decode enforces the 2…4 bound.
- `perspective { incidentRead, patternRead, signals: [{ text, present: Bool }], grounding }` —
  honest calibration, directed at the pattern. **The type has no verdict field** — "never a
  verdict on the relationship" is unexpressible, not discouraged (C3).
- `keepCard { items: [ReceiptRef], closingLine }` — the gold card; positives on file, same
  resolve-or-reject rule ("this talk is about protecting that, not putting it on trial").
- `openingClose { opening, close }` — the ready sentence + Pom's close ("Then let him talk. I'll
  check on you after. 🤍"). On this card the client calls `markPrepared` + `armPostEventCheckIn`
  on the linked upcoming event (nearest upcoming open event in the chapter; none → prep still
  completes, nothing arms). **No reconciliation timer, no countdown, no percentage exists on any
  prep type** (C3, compile-level).

Prep entry: a quiet affordance on the chat surface whenever the chapter has an upcoming open
event ("want to get ready for {event}?") or on demand from a chip — never a push (M6 owns
outreach), never a guilt string (the copy bank is scanned).

## 6. Chat tab (Features/ChapterDetail)

- **Header:** back · chapter icon · title · typed status line (template over store fields:
  `"{type} · since {month year} · {nearest-upcoming relativeDay}"` — reuses the M3 relative-day
  helper; no model text) · state glyph via tokens. Tabs: 💬 Chat / 🧵 Timeline (C8 route lands on
  Chat; `Route.chapter(id)` replaces the M3 placeholder in `AppShellView`).
- **Transcript:** `ChatMessageSnapshot` → bubbles (reuse `ChatBubbleView`/`DraftBubble` mapping);
  card messages render their designed component; chips row after the latest Pom turn (≤3, from
  the envelope; tapping inserts the text as the user's message → full C1 turn).
- **States (NN#6):** empty = Pom's typed room-greeting from the copy bank (state-aware, guilt-
  scanned); loading = typing indicator; reply failure = soft inline retry ("I lost my thread —
  again?") with the user bubble already persisted; unconfigured backend = the honest offline line,
  composer still files to the queue (words are never lost).

## 7. Timeline tab (typed node grammar — C3/C4, no model involvement)

Pure mapping over `events(inChapter:)` (already includes folded, deterministically sorted):

| store facts | node |
|---|---|
| `isHealed` | **folded 🌱 pill** — overrides everything below; dashed mint, "worked through & forgiven · tap only if you want to revisit"; expand → full card framing forgiveness as strength + `healedReason`; one tap refolds. **Expansion is view-local `@State` — there is no store field, so every fresh render leads folded (structural refold, never-test).** |
| `valence == .storm && isOpen` | **open storm** — the ONLY node with a pulsing dot + OPEN tag (Reduce Motion honored) |
| `valence == .storm && !isOpen` | calm small receipt — factual, no storm styling |
| `isUpcoming && date >= now` | dashed upcoming — shows "You're prepped. I'll check in after." iff `preparedAt != nil` |
| `.bright / .gold` | bright memory node (gold), body quoted as the user's own words |
| `.neutral` | receipt node ("On record.") |
| `.soft` | gentle node |

Intro card: `"Your story with {title}, the way I keep it — the good stays bright, the healed rests
quietly."` Footer verbatim: **"Healed moments stay folded so your story leads with the good.
They're yours to open — never mine to bring up."** Gradient line rose→lilac→mint via tokens. Wins
nodes = M7 (grammar leaves the slot). Sensitive chapters: same grammar, no counts anywhere (M1
never-rule holds on every new surface).

## 8. Acceptance (Swift Testing + Deno) + device-verify

1. **The chat turn, end-to-end** (ScriptedChat + ScriptedExtraction, real decode + real merge):
   user text → persisted user message + utterance flushed → deltas land in the store + Pom reply
   persisted. Reply failure keeps the user message AND the queued utterance (durable filing).
2. **Prep walk on a seeded fx-001-shaped chapter** (Daniel, the Jul 6 commitment, positives): all
   five cards arrive typed through the stage machine; every `ReceiptRef` resolves; a canned
   envelope citing an unknown id is rejected loudly; wrong-stage card → rejected; >3 chips →
   rejected; >4 likely-answers → rejected.
3. **Arming:** openingClose → `preparedAt` + `checkInArmed` set on the linked event;
   `NextUpCard.prepArmed` flips; the upcoming timeline node shows the prepped line.
4. **Timeline grammar goldens:** one seeded event per row of the §7 table → exact node kinds;
   ONLY the open storm pulses (never-test — a folded storm does not).
5. **Structural refold:** expanded healed event + fresh model construction → folded; no store
   write occurs on expand (never-test).
6. **Context + quarantine:** `chatContext` includes folded events flagged; the Deno assembler
   test proves sealed-block-only placement (keyless CI); schema files assert `text` required /
   `card` nullable in EVERY stage schema (the crisis-path guarantee, testable without a key).
7. **Copy bank guilt-scan** over every new ChapterDetail string (the M3 forbidden list).
8. **Router:** `kept://chapter/<uuid>` lands on detail-chat; unknown links still refuse.
9. **Privacy audit extension:** no chat prompt text, no key, in the app target.
10. **Live prompt-suite (👤 gated on provisioning item 2):** crisis routing · adjudication bait
    ("should I break up with him?") · folded-no-reraise-chat · diagnosis-language · surveillance
    bait — run with the deployed chat stack; every case added to `prompt-suite/cases.json`.
11. **Device-verify (confirmed build number):** chat feel (keyboard, scroll, retry), prep cards
    legible in all themes, tab swap, pulse honors Reduce Motion, deep link lands, VoiceOver reads
    cards sensibly.

## 9. Open questions (rulings needed before code)

1. **Chat turn wire shape.** (a) *Recommended:* two independent calls — `/chat` for the reply
   (ephemeral, retryable) + the EXISTING utterance queue → `/extract` for filing (durable). One
   write path (C1), all M1/M2 machinery reused, filing never blocks on reply latency and a failed
   reply never loses filed words. (b) One `/chat` call that fans out server-side and returns
   reply + delta envelope together — one round trip, but couples the two failure domains and
   creates a second envelope-bearing response path to keep correct forever.
2. **Prep delivery.** (a) *Recommended:* the §5 client-driven stage machine — conversational,
   matches the whitepaper's chat-surface screens, each response schema-locked to its stage, cards
   persist as chat history. (b) One-shot `/prep` package (all components in one response) — fewer
   calls, but a wall of cards, no calibration mid-flow, one giant schema.
3. **Chat history persistence.** (a) *Recommended:* `ChatMessage` in the encrypted store AND the
   E2E backup (additive `"chatMessage"` interior tag) — "chapter chats are the persistent memory"
   survives new-phone restore; last 30 turns travel as context. (b) Local-only (never uploaded)
   — lighter blob traffic, but restore loses every conversation while the story it produced
   survives; the sign-in promise gets an asterisk.
4. **Reply transport v1.** (a) *Recommended:* non-streaming typed JSON envelope — the strict
   decode boundary stays whole (NN#7), structured outputs enforce card grammars, prep cards render
   whole-object anyway; perceived latency handled by the typing indicator. (b) SSE token streaming
   with post-hoc parsing — faster first token, weaker boundary; if device feel demands it later,
   that's a new decision row, not a silent change.

## 10. Rulings (Xavier, 2026-07-23 — this review)

All four §9 questions closed on the recommended options:

1. **Chat turn = two independent calls.** `/chat` for the reply (ephemeral, retryable); the same
   message enqueues in the existing utterance queue → `/extract` → merge (durable filing). One
   write path (C1); the two failure domains never couple.
2. **Prep = the §5 client-driven stage machine.** Each response schema-locked to its stage; `text`
   required and `card` nullable in every schema (crisis never schema-blocked); cards persist as
   chat history.
3. **Chat history = encrypted store + E2E backup.** `ChatMessage` records join the M2 §7.3
   envelope via the additive `"chatMessage"` interior tag; `envelope_version` unchanged; restore
   rebuilds conversations; last ≤30 turns travel as model context.
4. **Reply transport v1 = non-streaming typed JSON.** Streaming, if device feel ever demands it,
   is a new FIGHT-LIST row — never a silent change.
