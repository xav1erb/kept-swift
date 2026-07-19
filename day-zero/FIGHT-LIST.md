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

## Open

*(none — new decisions get new rows, dated)*
