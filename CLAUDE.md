@AGENTS.md

# CLAUDE.md — Keeper

> **Keeper** replaces the notes-app graveyard and the goldfish-memory chatbot with a **character who
> keeps your whole life story**: you talk (or type) to Pom, a small creature; the app silently extracts
> people, events, promises, and feelings into persistent chapters orbiting a little world — and Pom
> follows up, prepares you for hard conversations, and never forgets. Native iOS (Swift + SwiftUI),
> encrypted local-first store, AI via our backend proxy only. Names "Keeper"/"Pom" are placeholders (F5).

This file is the **constitution**. Design, scope, and reasoning docs live in `day-zero/` until
graduated. The non-negotiables and locked contracts below apply to every change made here.

---

## PRIME DIRECTIVE

**Sealed, soft, and on your side.** (Ruled by Xavier 2026-07-19.) The unit of Keeper is a life story
held safely by someone on your side. Every decision must pass all three tests: *sealed* — would this
weaken a privacy claim's architectural truth? *soft* — does this weaponize a memory, guilt the user,
or celebrate drama? *on your side* — does this prepare the user, or adjudicate for her? If a choice
makes Keeper feel like "a case file being built" or "an app that guilts you back," it is wrong. If it
makes it feel like "a gentle keeper who remembers so you don't have to, and only ever uses it FOR
you," it is right.

- Receipts surfaced in prep mode to make the user clear-eyed → for you → right.
- A folded (healed) moment raised unprompted → ammunition → wrong.
- A filing confirmation after a messy vent ("filed to Mom, Work, Money") → kept → right.
- "We miss you" notification, a timer on reconciliation, a badge for a fight → weaponized care → wrong.

If a task seems to contradict a locked contract below, **stop and flag it — do not silently diverge.**

---

## NON-NEGOTIABLES (always apply)

1. **Swift 6 + SwiftUI on the current SDK.** Stale-priors warning in `@AGENTS.md` — read shipped
   headers for anything you touch.
2. **Contracts before code.** Types + decode boundary + acceptance test first; a milestone starts only
   after its `M*-CONTRACTS.md` package is reviewed.
3. **The three product laws bind every change:** privacy claims are architectural facts (C2); softness
   is enforced in code (C3); Pom prepares, never adjudicates (§14 safety rules).
4. **Real pipeline data on day one.** UI is built against the real store fed by real extraction output
   (transcript fixtures until live) — no long-lived mocks, fake the *source* never the *shape*.
5. **Vertical slices, each device-verified.** Anything touching mic, Face ID, icons, notifications, or
   StoreKit is proven on hardware on a confirmed build number.
6. **Every screen ships loading + empty + error states.** An empty world is never a blank page.
7. **Decode every external boundary, fail loudly.** Extraction deltas, backend responses, deep links —
   explicit `Codable`, no silent `try?`. A swallowed delta is a lost piece of someone's life.
8. **Never commit broken.** Build + relevant tests green before commit.
9. **Human judgment owns the seams** (APPROACH §seams): extraction schema/merge, encryption & sync,
   prompt stack & safety, server schema, awareness schemas, auth/entitlements, paywall.
10. **Done = acceptance test green on real data AND the slice's device-verify checklist ticked on a
    confirmed build number.** The §19 never-list is part of code review on every PR.

---

## LOCKED ARCHITECTURAL CONTRACTS (do not silently diverge)

Approved by Xavier 2026-07-19. Reasoning lives in `day-zero/APPROACH.md`; decision record in
`day-zero/FIGHT-LIST.md`.

- **C1 — One extraction pipeline.** All writes flow utterance → extraction → typed deltas →
  deterministic merge → store. Every surface is a read over that store. No second write path, ever.
- **C2 — Privacy claims are architectural facts.** UI privacy copy and architecture are one artifact.
  The mechanism (F3 ruling, 2026-07-19): **stored = ciphertext always; processed = plaintext only in
  flight.** Master key in iCloud Keychain (Apple-E2E synced); local store file-protected; Supabase
  holds client-encrypted blobs it cannot open. AI calls send minimum-necessary context over TLS to
  our proxy, processed in-memory, **never persisted, never logged** — Edge Function log config is
  code-reviewed under this contract. No-training tier verified in writing; no content-level
  analytics; erase = ciphertext blobs + derived metadata + AI-provider deletion; export ships;
  lock-screen copy never exposes secrets (generic phrasing default ON, F12).
- **C3 — Softness is code, not vibes.** Every §19 "never" has structural enforcement (type design,
  prompt-assembly filter, or test) — never only a system-prompt line. Folded events are flagged at
  prompt assembly; share cards are stripped by type; reconciliation has no timer field.
- **C4 — Engines compute, the model narrates.** Deltas are proposed by the model, validated and merged
  by deterministic code. Awareness %, streaks, states: typed code. Person merges gate on explicit
  confirmation. No user-facing number is model-estimated.
- **C5 — The proxy owns AI.** All calls via our backend; prompts assembled server-side; keys never on
  device; typed request/response contracts only.
- **C6 — First-class numbers computed at write.** awarenessPct, streak, chapter/person states are
  stored at merge/day-close and only read by views. Never recomputed in a view.
- **C7 — Data layer behind `Services/Store/`.** SwiftData details, the merge engine, encryption, and
  sync live there; features consume typed read models + commands.
- **C8 — One state pattern.** SwiftUI + `@Observable` MVVM-lite; logic in models, not views; `Route`
  enum + Router; every notification deep-links through it.
- **C9 — Walled modules.** GlobeKit (store-blind 2.5D engine), voice capture (faked in tests), paywall
  — behind protocols; the core loop never imports them.
- **C10 — Scheduled intelligence is server-driven; user reminders are local.** Check-ins/recaps/decay
  via server cron → user-facing push; tiny-task reminders are local notifications; every job logged in
  the cron ops README the day it's wired.

---

## THE BUILD WORKFLOW (every slice)

1. **Plan** — seams (NN#9) get a reviewed plan before generation.
2. **Contract** — types + `Codable` boundary + acceptance test (Swift Testing); milestone packages
   reviewed before the milestone.
3. **Implement** the vertical slice against the real store/pipeline.
4. **Verify** — build green, tests green (incl. the never-tests), loading/empty/error present, device
   checklist ticked where hardware is involved.
5. **Commit** small, scoped; bump build number every archive; never commit red.

For UI work read `DesignSystem/CLAUDE.md` first (tokens + Figma fidelity protocol — REQUIRED; note F7
gate). For store work read `Services/Store/CLAUDE.md`.

---

## STACK (all gates closed 2026-07-19)

- **Client:** Swift 6, SwiftUI, async/await, `@Observable`. **iOS 18+ floor.**
- **Persistence:** **SwiftData**, encrypted store behind `Services/Store/` (C7).
- **Backend:** **Supabase** — Edge Functions as the AI proxy, pg_cron for the check-in engine,
  Postgres+RLS for ciphertext blobs + derived metadata.
- **Sync:** transient-plaintext architecture (C2 / F3): iCloud-Keychain master key, client-encrypted
  blobs, ciphertext-only server, in-memory-only proxy processing.
- **AI:** **Claude, split-tier** — Haiku-class extraction, Sonnet-class chat/prep/recaps; no-training
  tier verified in writing; server-side prompt assembly (C5).
- **Voice:** on-device `SFSpeechRecognizer` behind a protocol (C9); **type-only fallback** where
  unsupported (F9) — never network STT.
- **Auth:** Sign in with Apple (primary) + email magic link; required at onboarding end.
- **Security:** Face ID app-lock (LocalAuthentication); alternate/disguise icons; file protection.
- **Fonts/Design:** Fraunces + Quicksand; 6 themes as semantic tokens; theming engine at M0. Brand
  identity + UI/UX developed from the whitepaper (F7); designer art/palettes + Figma 1:1 protocol
  land later.
- **Payments:** **Superwall presents, StoreKit 2 mirror is entitlement truth** (the affirmly pattern —
  `docs/monetization.md` is REQUIRED reading before any paywall work). Pricing per F8 ruling; final
  points confirmed before M8 ASC config.
- **Testing:** Swift Testing; transcript-fixture corpus for the pipeline; snapshot tests pinned to one
  simulator; the prompt suite (never-list red-team) on every prompt change.
- **Project generation:** XcodeGen (`project.yml`).

---

## ANTI-SLOP (what we never do)

- A screen that writes model objects around the pipeline. (C1)
- A privacy claim in copy without its mechanism, or vice versa. (C2)
- Enforcing a §19 "never" only in a system prompt. (C3)
- Auto-merging two same-named people; model-estimated awareness %. (C4)
- API keys or prompt assembly on device. (C5)
- Streak/awareness computed in a view. (C6)
- Raising a folded moment unprompted; guilt notifications; timers on reconciliation; badges for
  conflict; names on share cards by default; question counts on grief/private flows. (§19)
- Surveillance features of any kind. (§19)
- Untyped backend/LLM JSON; `try?`-swallowed decode of a delta. (NN#7)
- Mock data that outlives its slice; horizontal layers that integrate "later." (NN#4/5)
- Clinical/lecturing/"As an AI…" copy anywhere in Pom's surfaces.
