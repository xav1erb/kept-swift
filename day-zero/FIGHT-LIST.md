# KEEPER — Fight List

<!-- DAY-ZERO DOC. Every open decision, numbered, with what it blocks. ⛔ = blocking.
     STATUS: ALL TWELVE CLOSED — rulings by Xavier, 2026-07-19. Architectural rulings graduated
     into CLAUDE.md; this file is now the decision record. -->

## Closed decisions (rulings dated 2026-07-19)

| # | Decision | Ruling | Consequence |
|---|----------|--------|-------------|
| F1 | Backend platform | **Supabase.** Edge Functions = the AI proxy; pg_cron = the check-in engine; Postgres+RLS = ciphertext blobs + derived metadata. | House gotcha docs carry over. Xavier provisions the project (see `docs/PROVISIONING.md`). |
| F2 | Persistence | **SwiftData.** Custom E2E sync (F3) means no CloudKit-sync constraints. Sharp edges get `Services/Store/CLAUDE.md` gotcha treatment. | Unblocks M0. |
| F3 | Sync/E2E boundary | **Transient-plaintext architecture.** Master key in iCloud Keychain (Apple-E2E synced → "new phone, story follows you"). Stored data = client-encrypted blobs; Supabase holds ciphertext only. AI calls = minimum-necessary context, plaintext only in flight over TLS, processed in-memory at the proxy, **never persisted, never logged** (log config is code-reviewed under C2). Erase = ciphertext blobs + derived metadata + AI-provider deletion request. | Graduated into C2. The stored/processed line IS the consent copy's line. Unblocks M1 contracts + sign-in slice. |
| F4 | LLM | **Claude, split-tier.** Haiku-class for extraction (every utterance, strict schema); Sonnet-class for chat/prep/recaps. No-training tier verified **in writing** before M1 (C2 requirement). | Xavier provisions the key. |
| F5 | Naming | **Build under placeholders (Keeper/Pom).** LEXICON graveyard armed; one rename pass budgeted; hard deadline before M8 assets. | Soft-blocks store assets only. |
| F6 | Age gate | **Restricted under-18 flow ships v1.** Agent drafts the restricted spec in `M2-CONTRACTS.md` (feature subset, tightened crisis routing, COPPA/GDPR-K analysis) — Xavier rules on it like any seam. | Adds a seam to M2 contracts. |
| F7 | Design source | **The whitepaper is the design reference:** agent develops the brand identity + UI/UX from it (Cloud Cream tokens are fully specified). Designer supplies Pom art + the 5 remaining theme palettes with the Figma file later; the 1:1 fidelity protocol activates when that file exists. Until then: no "1:1" claims, stub palettes behind the token engine. | Unblocks all UI milestones with a swap-later plan. |
| F8 | Monetization | **Superwall presents; StoreKit 2 mirror is entitlement truth** (the affirmly pattern, ported). Pricing per research (2026-07-19): **$12.99/mo · $69.99/yr (7-day trial on annual only) · $4.99/wk SKU built but dark** (enable per-campaign for paid-TikTok cohorts via Superwall). Free tier: 3 chapters, ~5 vents/day soft cap (in-character "I'll be here tomorrow"), first prep + first recap free, **reading your own history is never paywalled.** Full evidence + do/never checklist: `docs/monetization.md`. Final price points re-confirmed by Xavier before M8 StoreKit config. | Unblocks M8 design; ASC config waits on the confirm. |
| F9 | Voice fallback | **Type-only.** No on-device STT for a locale → mic hidden with soft copy. Never network STT; "voice never leaves your phone" stays unconditional. | Unblocks M5. |
| F10 | followupQueue | **Agent drafts the spec in `M2-CONTRACTS.md`:** one question per app-open max, oldest-highest-priority first, auto-resolved by contextual capture. Xavier approves with the milestone package. | Unblocks M2 contracts. |
| F11 | `@Query` in views | **Banned.** All reads via `Services/Store/` read models. If SwiftData fights it hard, agent stops and proposes the narrow exception — never decides alone. | Unblocks M0. |
| F12 | Notification privacy | **Generic phrasing ON by default** ("Pom is thinking about tonight 🤍"); exact content is opt-in in settings. | Unblocks M6. |

## Standing rulings from the same session

- **Prime directive:** "Sealed, soft, and on your side" (VISION.md candidate 3). Ruled 2026-07-19.
- **Contracts C1–C10:** approved as drafted, 2026-07-19. CLAUDE.md DRAFT banner removed.
- **Defaults bundle:** iOS 18+ floor · F10/F11/F12 as above. Ruled 2026-07-19.
- **Provisioning (Xavier-owned, agent supplies instructions):** Supabase project · Anthropic API key
  (no-training tier confirmation in writing) · Apple Developer setup (bundle id, signing, ASC record,
  APNs key). Telegram loop pings: not provisioned — loop runs without pings for now.
  Checklist: `docs/PROVISIONING.md`.
- **Code naming = Kept** (target/module `Kept`, bundle id `com.kept.app`). Ruled 2026-07-19;
  LEXICON graveyard entry filed. "Keeper"/"Pom" remain doc placeholders until F5.
- **M0-CONTRACTS approved** 2026-07-19 with five rulings (`day-zero/M0-CONTRACTS.md` §8):
  swift-dependencies at M0 · snapshot testing at M0 · fetch-or-create singletons · stub palettes OK ·
  Dimension config → M3-CONTRACTS.
- **M0 done** — device-verify confirmed by Xavier 2026-07-19; ROADMAP flipped ☑.
- **M1-CONTRACTS approved + extraction.md RATIFIED** 2026-07-19 with five rulings
  (`day-zero/M1-CONTRACTS.md` §8): model ids pinned (haiku-4-5 extract / sonnet-5 M4) · blob upload
  → M2 sign-in slice · **folded events INCLUDED flagged in extraction context (overrides draft)** ·
  server-led schemaVersion · `acknowledge` endpoint → M2-CONTRACTS.
- **M1 headless build green** 2026-07-19 (45 tests; corpus fx-001…fx-011). Milestone close still
  gated on 👤 PROVISIONING item 2 (key + written no-training confirmation) → live smoke + first
  prompt-suite run.
- **M2-CONTRACTS approved** 2026-07-23 with four rulings (`day-zero/M2-CONTRACTS.md` §8):
  **pre-sign-in AI calls QUEUE UNTIL SIGN-IN (overrides draft; step reorder + /acknowledge
  deferred + fixed interview acknowledgments)** · acknowledge model = haiku-4-5 when it lands ·
  F6 as drafted (u13 hard stop, skip=adult, GDPR-K 👤 legal pre-EU) · backup + restore both in M2.
  F6 + F10 specs thereby closed as drafted.
- **M2 headless build green** 2026-07-23 (72 tests / 13 suites: engine walks both forks, queue +
  flush idempotency, F10/F6 behaviors + never-scans, envelope/restore crypto, end-to-end flow
  incl. the returning-account restore path). Milestone close gated on the §9.7 device checklist
  (👤 provisioning items 1.3 + 3, anon key).
- **M3-CONTRACTS approved** 2026-07-23 with four rulings (`day-zero/M3-CONTRACTS.md` §8):
  new-chapter sequence = shared `InterviewEngine` behind a script-provider seam (C1, no second
  runner) · Next-up line = typed template in-app (cached model phrase = an M6 decision) · pin tap
  → straight to `Route.chapter(id)`, preview sheet moved to M4 · idle spin ON + Reduce Motion honor.
  Amendments: `ChapterSummary` += priority/createdAt · C9 wall = source-scan test (single target).
- **M3 headless build green** 2026-07-23 (93 tests / 16 suites: orbit golden values + determinism,
  the C9 store-blind scan, grade mapping + exact sublines, next-up selection, resting-never-pulses
  + guilt-free copy bank + sensitive-no-count never-tests, router, live ring re-grade, and the
  "done" check — a chapter built via its sequence lands on the world at the right grade through
  the real pipeline). Incident absorbed: blob-interior dates were iso8601-lossy → `.deferredToDate`
  (M2-CONTRACTS §7.3 amendment, pre-first-blob; Store CLAUDE.md gotcha logged). Close gated on the
  §6.8 device checklist (drag/idle feel, 60fps).

- **M4-CONTRACTS approved** 2026-07-23 with four rulings (`day-zero/M4-CONTRACTS.md` §10):
  chat turn = two independent calls (`/chat` reply + the existing utterance queue → `/extract`,
  C1 one write path) · prep = client-driven stage machine, response schema-locked per stage,
  `text` always allowed (crisis never schema-blocked) · chat history = encrypted store + E2E
  backup (additive `"chatMessage"` interior tag, envelope version unchanged) · reply transport v1
  = non-streaming typed JSON (streaming would be a new row, never silent drift). Draft amendments
  recorded in-package: `Event` += `preparedAt`/`checkInArmed` · `PendingUtterance` += `chapterId`
  + `extractionContext(openChapterId:)` (closes the latent "open chapter listed first" M1 gap) ·
  `/acknowledge` stays deferred (chat replies are `/chat`'s job).
- **M4 headless build green** 2026-07-23 (104 Swift tests / 17 suites + 4 keyless Deno assembler
  tests: the two-path chat turn incl. failure-keeps-words-and-queue, the full prep walk with
  store-grounded receipts + arming, invented-receipt rejection, hostile-envelope rejection
  (chips>3, answers∉2–4, wrong-stage, mis-echoed turnId), timeline grammar goldens +
  fold-overrides-everything + only-open-storm-pulses, guilt-free detail copy bank, chat history
  through seal/restore, and the server-side C3 quarantine + crisis-path schema guarantees).
  New organ: `supabase/functions/chat/` + `prompts/chat/` + `scripts/deploy-chat.sh`; prompt-suite
  gained the chat pipeline (ps-006…ps-010: folded-no-reraise-chat, adjudication, crisis,
  diagnosis, surveillance). Close gated on: `chat` deploy + first live prompt-suite run (👤 key),
  the §8.11 device checklist, and ⚠ copy review (persona + stage prompts + detail copy bank).

- **M5-CONTRACTS approved** 2026-07-25 with four rulings (`day-zero/M5-CONTRACTS.md` §8):
  vent reply = typed filing confirmation only (no model call; `/acknowledge` stays deferred) ·
  disambiguation card = vent-only for M5 (persisted batches surface on next vent; wider surfaces
  = an M6 row) · sensitive chapters on the shared River = full structural suppression (the gentle
  card's type carries no title/body) · smart prompt = typed selection + template (cached model
  line = an M6 row). Free-tier vent cap explicitly OUT until M8 entitlement truth.
- **M5 headless build green** 2026-07-25 (119 tests / 19 suites: the three-topic done-bar vent
  with exact deep-link chips, two-Saras through the surface (question card → resolution → the
  right Sara), nothing-lost on failed flush, smart-prompt goldens (armed post-event > nearer
  unarmed > upcoming > quiet), structural session freshness, F9 mic gating + hold-to-talk via
  the fake, the VoiceCapture on-device+walled source scan, §9 grading goldens + size-class law +
  structural sensitive suppression (String(describing:) leak check) + future-events-off-the-river,
  deterministic S-curve layout with exact bucket markers, filter purity, both copy banks
  guilt-scanned). New walled module: `Kept/VoiceCapture/` (live `OnDeviceSpeechCapture`, headers
  verified against the iOS 26.5 SDK). Close gated on the §6.11 device checklist (mic is
  hardware-only truth) + ⚠ copy review (VentCopy, RiverCopy, mic/speech plist strings).

- **M6-CONTRACTS approved** 2026-07-25 with four rulings (`day-zero/M6-CONTRACTS.md` §10):
  server-plaintext check-in metadata = **content-free alarm rows** (client is scheduler-of-record;
  prefs never leave the phone; server owns WHEN never WHAT — closes `supabase/README.md`'s open
  ruling and **amends C10**: awareness decay becomes a client scheduled write; recap fits the same
  timing/content split) · F12 exact-content opt-in = generic-only in M6, **NSE mechanism committed
  for M7** (plaintext-upload door permanently closed; sensitive chapters always generic) ·
  check-in materializes **in chapter chat** (stored truth, push is transport, works permissionless;
  `Event.checkInAskedAt` dedupes) · the "Pom asks in-app" cluster (F10 ask surface, questions-held
  affordance, wider disambiguation, cached model phrases) → **all M7 rows**; M6 stays the
  notification vertical.

## Open

*(none — new decisions get new rows, dated)*
