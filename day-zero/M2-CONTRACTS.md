# M2-CONTRACTS — Onboarding (the interview IS the product demo)

<!-- CONTRACT PACKAGE (NN#2): reviewed BEFORE M2 code. STATUS: APPROVED by Xavier 2026-07-23 —
     §8 rulings recorded below. §8.1 ruled AGAINST the draft (queue-until-sign-in, not anonymous
     sessions) — consequences recorded as amendments in §8: step reorder, /acknowledge deferred,
     interview acknowledgments are fixed script lines in v1.
     Canonical UX spec: docs/onboarding.md (copy source of truth, §13 acceptance list). This package
     adds the contracts that spec defers: the engine types, the F6 restricted-u18 spec, the F10
     followupQueue spec, the /acknowledge endpoint (M1 §8.5 deferral), and the sign-in slice with
     master key + ciphertext backup (M1 §8.2 deferral — seam #2, the E2E design). Seams touched:
     #2 (encryption/key mgmt/sync), #3 (prompt stack — acknowledge voice), #6 (auth, icons, Face ID).
     API facts to verify at implementation against current headers/docs (AGENTS.md tripwires):
     setAlternateIconName, LAContext, supabase-swift auth surface, CryptoKit AES.GCM. -->

## 1. Scope

**In:** the full `docs/onboarding.md` flow (splash → reveal, 12 steps in the §2 amended order, both
fork modes) on the real pipeline — every free-text answer through the `PendingUtterance` queue into
M1 extraction at sign-in (C1, §8.1 ruling), every chip/field through typed `KeptStore` commands
(M1 amendment) · `InterviewScript` as a typed data structure · resumable draft ·
consent gate as a structural network + queue refusal · F6 restricted flow ·
F10 followupQueue · alternate icons (9) · Face ID wiring (M0 scaffold → real setting) · notification
pre-permission (chip → system prompt on Yes only; no push engine, that's M6) · Sign in with Apple +
magic link · master key creation · initial ciphertext backup + restore (per §8.4 ruling).

**Out (explicitly):** the globe itself (M3 — the reveal lands on a placeholder world surface that
lists chapters until M3 replaces it; loading/empty/error still ship, NN#6) · prep mode (M4 — the
reveal's "route to prep" ruling records the *routing*; the destination is a stub card) · check-in
push (M6) · voice capture (M5 — the interview is type-only) · paywall (M8; nothing monetized in
onboarding per F8).

## 2. The engine (C8 — types first)

```swift
// Features/Onboarding/ — linear @Observable step machine (affirmly pattern, adapted).
enum OnboardingStep: Int, CaseIterable, Codable {
    case splash, meetPom, themePicker, iconPicker, aiConsent,
         interview, privacyPledge, faceID, signIn,
         worldGenerating, worldContents, reveal
}
// Step order AMENDED at ratification (§8.1 queue-until-sign-in ruling): worldGenerating moved
// AFTER signIn — the queued utterances flush through extraction there, so the generating dwell is
// real work (no fake progress) and the narration references truly extracted objects.

@Observable final class OnboardingModel {
    private(set) var step: OnboardingStep
    let interview: InterviewEngine            // hosts the sub-machine during .interview
    func advance()                            // linear; interview advances internally by node
    // Progress bar: segments from .themePicker onward; interview's segment fills fractionally
    // by script position (docs/onboarding.md §0).
}
```

- **RootView gate:** `!store.hasCompletedOnboarding` → `OnboardingFlowView`; else the M0 lock gate.
  `hasCompletedOnboarding` is a stored flag on `UserProfile`, set exactly once at reveal.
- **Draft/resume:** a small `@Model OnboardingDraft` in the encrypted store (C7): current step,
  current node id, and the rendered bubble log (Pom + user bubbles as `[DraftBubble]`) so a killed
  app re-opens mid-interview pixel-identical. Extracted objects are NOT duplicated in the draft —
  answers already landed in the store the moment they were given (C1). The draft row is deleted at
  reveal.
- **Skips:** every node carries `skippable: Bool` (true except aiConsent and signIn, per spec);
  a skip advances with no write, no queue entry, no Pom comment (§13.10 acceptance).

## 3. The interview script (typed data, never prompt-engineered)

```swift
struct InterviewScript { static let v1: [InterviewNode] }   // fixed order, fork branch rules

struct InterviewNode: Identifiable {
    let id: String                    // stable: "q1-name", "q2-fork", "q3-age", "q4-partner"…
    let prompt: String                // VERBATIM from docs/onboarding.md §6
    let input: InputKind              // .chips([Chip]) | .freeText | .field(.name/.age/.city)
    let writes: WriteTarget           // .command(StoreCommand) | .extraction | .none
    let acknowledgment: AckKind       // .fixed(String) | .ai | .none
    let branch: BranchRule            // .next | .fork | .conditional(...)
    let skippable: Bool
}
```

- Chips/fields → `KeptStore` commands (`setUserName`, `setUserBasics`, `setOnboardingMode`,
  relationship-status chips → typed writes). Free text → the M1 pipeline unchanged. The Q5
  real-disclosure behavior (pattern naming, dated commitment, chapter title, disambiguation, pinned
  event) is **entirely M1's extraction + merge doing its job** — fx-001 already asserts the graph;
  M2 adds only the surfaces that render it (disambiguation question bubble, filing acknowledgment).
- Q6 (positive anchor) is `skippable: false` at the script level per spec ("REQUIRED, never skipped
  by the script") — the user may still answer minimally; the script just never omits the node.
- Focus fork: deep-dive runs the disclosed chapter's type sequence (same node structure); untouched
  types queue per §5. Full fork: census blocks at survey depth, fixture fx-002's shape.
- **World generating narration (C4):** the checklist lines are typed code reading the store
  (chapter titles, person names) — never model text, no fake progress, minimum dwell only.

## 4. `/acknowledge` — DEFERRED at ratification (§8.1 consequence)

The §8.1 queue-until-sign-in ruling means **no AI call exists before step 9 (signIn)** — and the
interview is steps 1–6. An acknowledgment that arrives after sign-in is conversational filler four
screens too late, so:

- **v1 interview acknowledgments are fixed script lines** — typed, verbatim in `InterviewScript`,
  per node (warm keeper register; the disclosure nodes get "kept, safe" phrasing — see §3). This is
  *stronger* than the draft on two axes: the interview is fully completable offline, and fixed copy
  needs no red-team.
- The `/acknowledge` endpoint contract (drafted in this package's history, M1 §8.5) is **deferred to
  the first authed conversational surface** — M4 chat or the followupQueue ask, whichever lands
  first. The §8.2 model ruling (`claude-haiku-4-5`, env-pinned `ACKNOWLEDGE_MODEL_ID`) is recorded
  now and applies then.
- Q5's live "reflect the pattern back" behavior becomes: fixed warm keeper acknowledgment in the
  interview; the pattern-naming *materializes in the built world* (AI chapter title, dated
  commitment, pinned event) which the user meets at worldContents/reveal — the receipts still land,
  the theater moves to where extraction actually runs.

## 5. F10 — followupQueue spec (ruling F10: agent drafts, Xavier approves here)

- **Storage:** `UserProfile.followupQueue: [ChapterType]` (exists since M0). Order in array = queue
  order.
- **Enqueue:** at worldContents confirm — every *selected-but-unbuilt* chapter type, ordered by the
  fixed priority table: `relationship > family > friendship > work > health > money > passion >
  growth`. **`privateCorner` and `grief` are never enqueued** — sensitive rooms are only ever
  user-opened; Pom never solicits them (C3, structural: the enqueue function's domain excludes
  `isSensitive` types, never-test asserts it).
- **Presentation:** at most **one** queue question per app-open (a session flag, reset on
  background > 30 min), asked only from the world surface at idle — never mid-capture, never
  mid-prep. Phrased in Pom's voice from a typed per-type template. Declining ("later" chip) moves
  the type to the queue tail and ends solicitation for the session. No second ask, ever.
- **Auto-resolve:** the merge engine removes a type from the queue whenever a chapter of that type
  is created through ANY capture (contextual auto-resolution — the M1 merge gets a 6-line hook at
  `upsertChapter` apply). Silent — no "you completed a followup" copy.
- **Never (tests):** no badge, no count ("2 rooms left"), no streak/pressure copy, no re-ask after
  decline in-session, no sensitive type in the queue — one never-test each.

## 6. F6 — restricted under-18 spec (ruling F6: agent drafts, Xavier rules)

- **Age source:** self-declared at Q3; the gate runs silently at the moment of the write
  (`setUserBasics(age:)`). No callout, no visible mode label, no different theme — the restriction
  is invisible (whitepaper: "age-gate runs silently").
- **Under-13 (COPPA floor):** hard stop — a soft landing screen in Pom's voice ("Keeper is for 13
  and up. I hope we meet again when the time's right 🤍"), no data retained beyond the local draft,
  which is wiped. TOS floor 13+; App Store rating stays 17+ (rating ≠ gate).
- **13–17 (restricted mode):** stored as derived `isMinor` on `UserProfile` (computed at write,
  C6-style; never displayed). Differences, all structural:
  1. **Crisis routing tightened:** the extraction/chat context carries `isMinor`; the server prompt
     stack selects the restricted safety layer (lower threshold for surfacing help resources,
     minor-appropriate resource set). The layer is versioned prompt text with prompt-suite cases —
     never a client-side string.
  2. **Monetization fence (forward note for M8):** the dark weekly SKU and win-back discount
     campaigns never target `isMinor` users; recorded here so `docs/monetization.md` inherits it.
  3. Everything else identical — same encryption, same softness, same features. A teen's story is
     not a lesser story.
- **Skipped age:** unrestricted default (self-declaration is the mechanism; restriction without a
  signal is guessing) — §8.3 asks for the ruling explicitly.
- **GDPR-K:** EU age-of-digital-consent varies 13–16 by member state; a parental-consent flow is
  NOT drafted here. Flagged as a 👤 legal-review item for Xavier before EU launch — this package
  ships the 13+ floor + restricted mode only.

## 7. The sign-in slice — auth, master key, ciphertext backup (M1 §8.2 deferral; seam #2)

### 7.1 Auth (seam #6)

- **supabase-swift** behind `Services/Backend/` (protocol-fronted, faked in tests — C9 posture).
  Sign in with Apple (primary) + email magic link; magic-link redirect via custom scheme
  `kept://auth-callback` in v1 (universal links when provisioning item 3 lands), routed through the
  C8 Router.
- **Pre-sign-in AI calls (§8.1 RULING: queue until sign-in — overrides the draft):** no AI call of
  any kind before sign-in. Free-text answers land in a persisted, encrypted **`PendingUtterance`
  queue** (`@Model`: order, surface, nodeId, text, clientTime, utteranceId — the idempotency key is
  minted at capture so a crash mid-flush replays safely through M1's `AppliedUtterance` gate).
  Chip/field answers still write locally via typed commands the moment they're given (no network,
  C1-consistent). At first successful sign-in the queue flushes FIFO through the M1 pipeline during
  worldGenerating; disambiguation questions surface there, pre-reveal ("quick question before I
  finish building…"). No anonymous sessions, no dashboard delta, no cleanup cron. The queue
  survives kill/relaunch with the draft and is deleted after a fully-applied flush.
- Consent gate is structural (C2/C3): `ExtractionClient` and `AcknowledgeClient` sit behind a
  `ConsentGate` that throws `.consentNotGranted` unless the stored consent flag is set — asserted
  by a test that the network layer refuses pre-consent (§13.2 acceptance), not by view logic.

### 7.2 Master key (C2/F3)

- Generated at first successful sign-in: 32 bytes `SecRandomCopyBytes`, stored as
  `kSecClassGenericPassword` with `kSecAttrSynchronizable = true` (iCloud Keychain, Apple-E2E —
  "new phone, story follows you"), accessible-after-first-unlock. The key never leaves the
  Keychain except in memory for seal/open. No passphrase derivation in v1 (the Keychain IS the
  recovery story); export (M7) is the user-readable escape hatch.

### 7.3 Envelope v1 + backup protocol (completes the M1 §5 sync-seam review)

- **Blob unit = one record** (`blob_id` = the record's UUID). Payload interior (plaintext, then
  sealed): `{ "t": "person" | "chapter" | …, "v": 1, "data": <snapshot JSON> }` — the type tag
  lives INSIDE the ciphertext; the server stays type-blind (no kind column, closing the M1 §5
  question: per-collection sync does NOT justify one).
- **Envelope (`envelope_version = 1`):** CryptoKit `AES.GCM.seal` under the master key,
  12-byte random nonce, `combined` (nonce ‖ ciphertext ‖ tag) base64 in `payload`.
  - *Amended 2026-07-23 (M3, pre-first-production-blob):* interior dates encode as
    `.deferredToDate` (raw `timeIntervalSinceReferenceDate` Double), NOT `.iso8601` — iso8601
    truncates sub-second precision, which broke restore equality and destabilized `createdAt`
    ordering once M3's read models exposed chapter dates. Interiors are ciphertext; fidelity
    beats readability. Envelope version unchanged (no sealed blob existed anywhere yet).
- **Upload:** after sign-in — initial full backup (every record), then write-behind: each merge
  commit / command enqueues touched record ids; a background uploader drains the queue
  (`upsert` on `(user_id, blob_id)`). Deletes → tombstone (`deleted_at`).
- **Conflict strategy:** last-write-wins per blob on `updated_at`, v1 (single-active-device
  assumption, documented). True multi-device merge is a future contract review, not a silent
  upgrade.
- **Restore (per §8.4 ruling):** fresh install + successful sign-in + empty local store + server
  blobs present → restore path (download all, open with the Keychain key, rebuild the store,
  land on the world). Backup without restore is a promise without a mechanism — the sign-in copy
  says "new phone, your story follows you" and C2 makes copy = architecture.

## 8. Rulings (Xavier, 2026-07-23 — this review)

1. **Pre-sign-in AI calls — QUEUE UNTIL SIGN-IN (overrides the draft's anonymous-session
   proposal).** No AI call before sign-in, period. Mechanics in §7.1.
2. **`/acknowledge` model tier — `claude-haiku-4-5`**, env-pinned `ACKNOWLEDGE_MODEL_ID`. Applies
   when the endpoint lands (deferred per §4).
3. **F6 — CONFIRMED as drafted:** under-13 hard stop + draft wipe; skipped age = unrestricted;
   GDPR-K parental consent stays a 👤 legal-review item pre-EU.
4. **Backup scope — BACKUP + RESTORE in M2**, as drafted in §7.3.

### Amendments made at ratification (consequences of §8.1)

- **Step order:** `worldGenerating`/`worldContents` moved after `signIn` (§2) — the flush is the
  generating dwell; narration stays honest (C4, no fake progress). Sign-in copy "one last thing"
  survives: it is the last thing *asked of her* (remaining steps are automatic/confirmation).
- **`/acknowledge` deferred** out of M2 (§4); interview acknowledgments are fixed script lines.
- **`PendingUtterance` queue** added to the store (§7.1) — encrypted, persisted, idempotent flush.
- **docs/onboarding.md** carries a matching amendment note (§0) — copy stays verbatim; only step
  order and acknowledgment sourcing changed.

## 9. Acceptance + device-verify

1. The 11 checks of `docs/onboarding.md` §13 — the master list; copy character-for-character.
2. Engine unit tests: script walk in both forks produces fx-001/fx-002's store graphs through the
   REAL pipeline path (harness feeds the fixture envelopes at the extraction boundary — the same
   corpus, now driven by the engine); kill/resume at every step; skip writes nothing.
3. Consent-gate test: network layer throws pre-consent AND the queue refuses to accept an
   utterance pre-consent (§13.2 — structural, not UI). Queue tests: FIFO flush order, crash
   mid-flush replays idempotently (M1 `AppliedUtterance` gate), queue survives kill/relaunch,
   deleted only after full application.
4. F10 tests: enqueue order, one-per-open, decline-to-tail, auto-resolve on capture, and the
   never-tests (no counts, no sensitive types, no re-ask).
5. F6 tests: under-13 stop + draft wipe; `isMinor` derived at write; restricted context flag
   reaches the request; no age callout string exists.
6. Crypto tests: envelope round-trip (seal → open), tamper detection (flipped byte fails loudly),
   restore rebuilds a byte-equivalent store from fixtures.
7. Device-verify (hardware, confirmed build number): both forks end-to-end · all 9 icons apply +
   disguises render on the home screen · Face ID lock honors the 4.10 choice · kill/relaunch
   mid-interview resumes exactly · notification system prompt only after Yes · Sign in with Apple +
   magic link end-to-end (👤 needs provisioning items 1.3 + 3) · restore on a second
   device/simulator.
