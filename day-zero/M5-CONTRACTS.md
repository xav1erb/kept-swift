# M5-CONTRACTS — Tell Pom + the River (capture & the master timeline)

<!-- CONTRACT PACKAGE (NN#2): reviewed BEFORE M5 code. STATUS: APPROVED by Xavier 2026-07-25 —
     all four §7 rulings closed on the recommended options; record in §8.
     Sources: whitepaper §10 (Tell Pom / vent), §9 (the River, hard grading rules), §19;
     contracts C1 (the vent IS the pipeline's front door), C3 (grading + suppression structural),
     C4 (smart prompt & filing confirmation are typed selection, never estimates), C9 (VoiceCapture
     is a walled, store-blind module, faked in tests), F9 (type-only fallback — never network STT,
     ruled 2026-07-19), C8 (deep-link chips through Router). Seams: NONE open server-side — the
     extract function already speaks `vent` (M1) and filing/disambiguation machinery is built;
     M5 is fully offline-buildable. Human-owned pieces here: the §7 rulings + ⚠ copy review.
     API tripwire (AGENTS.md): SFSpeechRecognizer / AVAudioSession headers read at implementation,
     not recalled. Free-tier ~5 vents/day soft cap (F8) is OUT — enforcement needs entitlement
     truth, which lands with M8 StoreKit; the cap gets its M8-CONTRACTS row. -->

## 1. Scope

**In:** the real **Tell Pom sheet** replacing the M3 placeholder (grab handle · ✕ · 🔒 SEALED badge ·
hero "I'm listening." with the §10 verbatim copy) — 1 contextual **smart prompt card** (typed
selection, §2) + the 6 template chips verbatim (🌧 just need to vent · ✨ something good happened ·
📖 quick chapter update · 🤔 help me decide something · 🌿 log something small · 💬 ask me about my
day), chips pre-fill the composer · **fresh each session** (nothing persists on this surface — the
chapters are the memory) · send → the ONE pipeline (enqueue `surface: .vent` + flush) → the
**filing confirmation with deep-link chips** ("filed to Mom 🏠, Work 💼 and Money 🪙 — want to open
any?" — ships v1, non-negotiable) · the **disambiguation question card** in Pom's voice (the C4
gate finally gets its surface; §3) · honest failure states. **VoiceCapture** (C9 walled module):
hold-to-talk on-device STT behind a protocol, F9 type-only fallback, never-network never-test.
**The River**: S-curve layout engine (deterministic), alternating banks, time markers, per-chapter
filter chips, end cap "where your river begins" — under the §9 **hard grading rules** (only true
open wounds pulse · factual negatives small & calm · sensitive silences get the gentlest card ·
healed = folded 🌱 pills · positives over-represented), replacing the River tab placeholder.

**Out (explicitly):** the ~5 vents/day soft cap (M8 — needs entitlement truth; in-character copy
is specced in `docs/monetization.md`) · check-in engine + the post-event reply routing (M6 — the
smart prompt only *asks*; the answer files like any vent) · win nodes on the River (M7 — the
grammar leaves the slot, same as M4's timeline) · `/acknowledge` (stays deferred; §7 Q1 rules on
whether the vent even wants it) · streak/savings milestone markers (their data lands M6/M7).

**Done (ROADMAP M5):** a three-topic vent files to three chapters and says so; the River renders
the seeded world with correct grading (only true open wounds pulse).

## 2. Store reads + the smart prompt (typed, C4)

- **`riverEvents() -> [EventSnapshot]`** — every event, newest first, deterministic `(date desc,
  id)` tiebreak (the restore-stability rule). The River joins against `chapterSummaries()` for
  chapter title/icon/type/sensitivity; no new snapshot type needed.
- **Smart prompt selection is a pure function** (the M3 Next-up pattern, §7 Q4):
  1. **Post-event** — a pinned event whose moment just passed: `isUpcoming && date < now &&
     date ≥ now − 48h`, nearest-past first, `checkInArmed` preferred → "💗 {title} happened — how
     did it go? · I've been thinking about you." Tapping pre-fills nothing — it focuses the
     composer; whatever she says files like any vent (the M6 engine will *push* this question;
     M5 only *offers* it in-sheet).
  2. **Upcoming** — else the Next-up pick (reused `selectNextUp`) → "{title} · {relativeDay} —
     want to talk it through?"
  3. **Quiet** — else the default card ("what's alive today? even the small stuff counts").
  All copy in the `VentCopy` bank (guilt-scanned, ⚠ review).

## 3. Tell Pom — the vent sheet (Features/TellPom)

- **Session model:** `@Observable VentModel`, constructed fresh at each sheet presentation
  (`router.isTellPomPresented`) — the session transcript (sent texts, filing confirmations,
  question cards) is a session-local array. **There is no vent-transcript store model — freshness
  is structural** (never-test: dismiss + reopen → empty; the store schema has nothing to hold it).
- **The turn (C1, no model reply):** send → `enqueueUtterance(surface: .vent, nodeId: "vent",
  text:)` (chapterId nil — filing decides) → `UtteranceFlusher.flush()` → each `FilingSummary`
  renders a **typed filing confirmation**: the touched chapters as icon+title deep-link chips
  ("want to open any?"); tapping routes `Route.chapter(id)` and dismisses the sheet. Pom's
  response IS the confirmation — the daily proof-of-listening, no network beyond the pipeline
  (§7 Q1 rules on adding a model acknowledgment line).
- **Disambiguation card (the fx-004 surface):** flush results carrying `pendingQuestions` (plus
  any batches persisted from earlier sessions — `pendingDisambiguations()`) render as a question
  card in Pom's voice: the batch's `question` text + one chip per candidate (name · relation) +
  "someone new". A choice calls `resolveDisambiguation(batchId:resolution:)`; the returned
  `FilingSummary` renders its own confirmation. Held deltas stay parked until answered — never
  dropped, never guessed (§7 Q2 rules on whether this card also lands on other surfaces now).
- **Failure states (NN#6/NN#7):** extraction down → the row stays queued and the session shows
  the honest line ("kept. I'll file it the moment I can — nothing gets lost.") — words are
  captured BEFORE any network is attempted, so the vent literally cannot lose them. Empty session
  = the hero + prompts (that IS the empty state); loading = a soft "filing…" shimmer per send.

## 4. VoiceCapture — the walled module (C9/F9)

```swift
// Kept/VoiceCapture/ — store-blind, network-blind. Produces text; knows nothing else.
nonisolated struct SpeechAvailability: Equatable, Sendable {
    let onDeviceSupported: Bool     // locale + device + supportsOnDeviceRecognition
    let permissionDenied: Bool
}
nonisolated protocol SpeechCapturing: Sendable {
    func availability(locale: Locale) async -> SpeechAvailability
    func requestPermissions() async -> Bool                    // mic + speech, system prompts
    func startCapture(partial: @escaping @Sendable (String) -> Void) async throws
    func stopCapture() async -> String                         // final transcript
    func cancelCapture() async
}
```

- Live `OnDeviceSpeechCapture`: `SFSpeechRecognizer(locale:)` with
  **`requiresOnDeviceRecognition = true` unconditionally** + `supportsOnDeviceRecognition`
  runtime-checked, AVAudioEngine tap, current-headers verification at implementation (tripwire).
- **Hold-to-talk:** press-and-hold the warm mic → partials stream into the composer live; release
  → final transcript stays EDITABLE; the user sends. Voice is senior to typing (§10) but never
  auto-sends — her words, her send.
- **F9 fallback:** `onDeviceSupported == false` → the mic simply isn't there; composer is
  type-only with one soft line ("typing is just as kept"). Permission denied → same hiding, soft
  settings hint. Never a broken button, never a nag.
- **Never-tests (C3/C9, mechanical):** source scan over `Kept/VoiceCapture/*.swift` — MUST
  contain `requiresOnDeviceRecognition = true`; MUST NOT reference `URLSession`, `import Network`,
  `CFNetwork`, or `Services/Store` symbols (the GlobeKit A3 pattern). "Voice never leaves your
  phone" stays an architectural fact, not copy.
- Tests drive `FakeSpeechCapture` (scripted partials/finals, scriptable availability). Plist
  strings (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`) join the ⚠ copy
  review; the live mic path is device-verify only.

## 5. The River (Features/River)

- **Card grammar** extends the M4 `TimelineNode` mapping with the River's §9 hard rules, joined
  per-event with its chapter badge (icon + title):
  - `openStorm` (non-sensitive chapters) — the ONLY pulsing card, OPEN tag (Reduce Motion honored).
  - `calmReceipt` — factual negatives: SMALL card, calm styling, never storm-dressed.
  - `folded` — the 🌱 pill, identical behavior to M4 (view-local expand, structural refold).
  - **`sensitiveSilence` — any event of a sensitive chapter (`ChapterType.isSensitive`) renders
    the fixed gentlest card: "It went quiet — a hard talk. The door stays open, no rush." The
    card TYPE carries no title/body fields — suppression is structural, full detail lives only
    inside the chapter's own timeline** (§7 Q3 rules on this).
  - `bright`/`gold` — LARGE cards, the user's own words quoted; `receipt`/`gentle` — standard.
  - **Positives over-represented is a size-class law, not a mood:** bright/gold always render
    large, negatives always small — asserted by a grammar test, so a life with texture reads as
    one (§9: "my life has texture, not a case file").
- **Layout engine (pure, LOOP-safe):** input = graded cards newest-first → S-curve
  `x(t) = mid + amplitude · sin(2π · y / period)`, banks alternate by index, vertical slotting
  from fixed per-kind heights (no overlap by construction), **time markers** inserted at calendar
  bucket boundaries (TODAY · EARLIER IN {MONTH} · {MONTH} · {MONTH YEAR} · LAST YEAR — fixed
  calendar in tests), gradient by time-depth (rose→lilac→blue→gold at the origin), Pom floats at
  Today, end cap "where your river begins" ☀️. Golden-value layout tests on a fixed seed;
  scroll view + generated layout, **no 3D**.
- **Filter chips:** ✨ Everything + one chip per chapter (icon + title) → pure re-filter,
  deterministic re-layout. Empty river = the end cap + one soft line (never a blank page).
- Replaces the River tab placeholder; `kept://river` already routes.

## 6. Acceptance (Swift Testing) + device-verify

1. **The done-bar vent (fx-003 shape, through the UI model):** one three-topic vent → scripted
   envelope → confirmation lists EXACTLY the three touched chapters as deep-link chips (titles +
   icons, no 4th); tapping a chip resolves `Route.chapter(id)` and dismisses.
2. **Two-Saras in the vent (fx-004 through the surface):** scripted disambiguation → the question
   card shows both candidates + "someone new"; resolving applies the held deltas and renders the
   resolution's own confirmation; the "someone new" path creates, never merges.
3. **Nothing lost:** extraction down → row queued, honest copy shown, no confirmation fabricated;
   the next successful flush files it.
4. **Smart prompt goldens** (fixed calendar/now): post-event-within-48h wins over upcoming;
   `checkInArmed` preferred; else upcoming; else quiet. Pure function, exact copy.
5. **Freshness is structural:** dismiss + represent → empty session; grep-level assert that no
   store model/read exposes a vent transcript.
6. **VoiceCapture:** availability-driven UI (supported → mic; unsupported/denied → hidden +
   soft copy — F9); scripted partials land in the composer, release keeps text editable; the
   §4 source-scan never-test.
7. **River grammar goldens:** a seeded world (bright/gold/neutral/soft/storm-open/storm-closed/
   healed/sensitive) → exact card kinds + size classes; ONLY the open storm pulses; **no
   sensitive event's title or body string appears anywhere in the rendered card models**
   (never-test); folded pill refolds structurally.
8. **Layout determinism:** fixed seed → exact banks/offsets/marker positions, twice; filters
   re-layout deterministically.
9. **Copy banks guilt-scanned** (VentCopy + RiverCopy, the M3/M4 forbidden list).
10. **Router:** `kept://tellpom` presents the sheet; `kept://river` lands the tab.
11. **Device-verify (confirmed build number):** hold-to-talk feel (press, partials, release,
    edit, send) · on-device proof: STT works in airplane mode · permission prompt flow + denial
    → mic hides softly · unsupported-locale device (or simulated) → type-only · River scroll
    performance on a long seeded world · sheet present/dismiss feel · confirmation chips land.

## 7. Open questions (rulings needed before code)

1. **Pom's vent response.** (a) *Recommended:* the typed filing confirmation ONLY — offline,
   deterministic, instant, and it IS the §10 proof-of-listening; no model call beyond the
   pipeline. (b) Add a one-line Haiku acknowledgment via the deferred `/acknowledge` before the
   confirmation — warmer, but adds a network dependency + red-team surface to every vent, and
   the M2 §4 deferral would finally land here. (A warm ack can still arrive later as its own row.)
2. **Where the disambiguation card lives.** (a) *Recommended:* the vent sheet only for M5 — it is
   the originating surface for messy multi-person dumps; batches raised elsewhere persist and
   surface on the next vent open (the queue already survives restarts). Chapter chat + a global
   "questions Pom is holding" affordance become an M6 row. (b) Build the card into chapter chat
   too, now — more complete, more surface area to get right this milestone.
3. **Sensitive chapters on the shared River.** (a) *Recommended:* FULL structural suppression —
   every event of a `privateCorner`/`grief` chapter renders the fixed gentle card (a type with no
   title/body fields); detail exists only inside the chapter. The shared surface can never leak a
   grief detail, even over-the-shoulder. (b) Suppress only negatives; bright moments of sensitive
   chapters show normally — warmer river, but a structural hole (the type must carry content).
4. **Smart prompt phrasing.** (a) *Recommended:* typed selection + typed template (the M3 §8.2
   pattern — no network renders the sheet). (b) A cached model-written line — deferred to the M6
   check-in engine as its own decision row, not smuggled in now.

## 8. Rulings (Xavier, 2026-07-25 — this review)

All four §7 questions closed on the recommended options:

1. **Vent reply = the typed filing confirmation only.** No model call beyond the pipeline; a warm
   model acknowledgment stays a possible future row (`/acknowledge` remains deferred).
2. **Disambiguation card = the vent sheet only for M5.** Batches from other surfaces persist and
   surface on the next vent open; chapter-chat + a global affordance = an M6 row.
3. **Sensitive chapters on the River = full structural suppression.** The gentle card's type has
   no title/body fields; detail exists only inside the chapter.
4. **Smart prompt = typed selection + typed template.** No network renders the sheet; a cached
   model line would be an M6 decision row, never silent drift.
