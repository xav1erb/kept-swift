# KEEPER — Engineering Approach

<!-- DAY-ZERO DOC. Lives OUTSIDE the repo once graduated. This is where the locked architectural
     contracts get DECIDED (with reasoning); CLAUDE.md is where they get STATED.
     STATUS: ALL CONTRACTS C1–C10 APPROVED by Xavier 2026-07-19; open items resolved the same day
     (see FIGHT-LIST.md): F1 Supabase, F2 SwiftData, F3 transient-plaintext (graduated into C2),
     F4 Claude split-tier, F9 type-only voice fallback, F11 no-@Query. Prime directive ruled:
     "Sealed, soft, and on your side." Graduated into CLAUDE.md the same day.
     Derived FRESH from KEEPER-whitepaper-final v1.0 (per autobuild-kit's rule: never cargo-cult).
     Where a contract matches the house pattern (affirmly/smyle), the reasoning below says WHY it
     genuinely recurs here — a match is not the justification. -->

## Approaches we take (the locked-contract candidates)

### C1. One extraction pipeline; every surface is a view over it (PROPOSED) — *the Keeper-defining contract*
- **The decision:** Every user utterance (onboarding answer, chapter chat, vent) flows through ONE
  pipeline: utterance → AI extraction call → **structured deltas** (new/updated Person, Event,
  Commitment, Goal, state changes, awareness changes, cross-links) → deterministic validation + merge
  into the store → UI reacts. No surface writes model objects any other way. The globe, chapters, the
  River, trees, Wins, recaps are all *reads* over this one store.
- **Why:** The whitepaper says it outright ("Everything in the app is a view over one extraction
  pipeline") and orders it built first, tested with transcripts before any UI polish (M1 before M2+).
  If two surfaces write through different paths, the story forks — and a keeper whose story forks is
  dead as a product. This is also what makes the build parallelizable: UI slices consume a typed store
  they can fake.
- **What it forecloses:** Quick hacks that write an Event directly from a screen; "we'll wire the vent
  into extraction later" (it IS extraction); a separate onboarding data path.
- **Graduates as:** "All writes flow utterance → extraction → typed deltas → deterministic merge →
  store. Every surface is a read over that store. No second write path, ever."

### C2. Every privacy claim in the UI is an architectural fact (PROPOSED) — *the brand contract*
- **The decision:** The four consent-screen claims (processed only to power your world · never used to
  train models · never sold/advertised on · deletable always, including AI-side) and the pledge/footer
  copy ("sealed", "recoverable, never readable", "gone means gone") are engineering requirements with
  named mechanisms: local store encrypted (`NSFileProtectionComplete`, key in Secure Enclave/Keychain);
  sync as ciphertext only (E2E — mechanism per F3); AI calls via our backend proxy on a contractually
  verified no-training tier, minimum-necessary context, keys never on device; no third-party analytics
  on conversation content (event-level, content-free only); "Erase my world" = local wipe + server
  purge + AI-provider deletion, double-confirmed; export ships (trust feature, sits above erase);
  lock-screen notification phrasing never exposes secrets.
- **Why:** Law 1 — privacy IS the brand, and the whitepaper's never-list closes with "never make a
  privacy claim in UI that the architecture doesn't literally satisfy." A single false claim is an
  App-Store-review, legal, and trust catastrophe for exactly this audience. Making it a contract means
  copy changes and architecture changes are coupled: touch one, verify the other.
- **What it forecloses:** Convenient plaintext server-side processing; content-level analytics;
  soft-deletes pretending to be erasure; any SDK that phones conversation content home.
- **Graduates as:** "UI privacy copy and architecture are one artifact. No claim ships without its
  mechanism; no mechanism weakens without the copy changing. Erase = local + server + AI-provider."

### C3. The softness laws are code, not vibes (PROPOSED)
- **The decision:** The whitepaper's hard behavioral rules are enforced mechanically: `isHealed`
  (folded) events carry a `do-not-raise-unprompted` flag stripped-or-flagged at prompt assembly (never
  reliant on the model's goodwill), render folded everywhere, expand/refold on tap, stay available to
  pattern analysis; share cards strip names/details by default at the type level (the share payload
  simply has no fields for them); reconciliation wins have no timer/percentage field; no achievement
  can be triggered by a conflict event; notification copy bank contains no guilt strings; grief/private
  flows have no question-count in their type config. The never-list (§19) becomes a code-review
  checklist AND prompt-suite test cases.
- **Why:** Law 2. An LLM system prompt is not an enforcement mechanism — models drift, prompts get
  edited, context gets truncated. Anything the whitepaper phrases as "never" must be structurally
  impossible or test-caught, because one folded-moment-weaponized incident destroys the product's
  reason to exist ("kept as something you survived, not as ammunition").
- **Graduates as:** "Every §19 'never' has a structural enforcement (type design, prompt-assembly
  filter, or test) — never only a system-prompt instruction. New features add their never-tests."

### C4. Engines compute, the model narrates; deltas are proposed, deterministically merged (PROPOSED)
- **The decision:** The LLM proposes; typed code disposes. Extraction output is a strict schema of
  proposed deltas, validated and merged by deterministic Swift/server code. Awareness % is computed by
  typed code scoring filled slots against each chapter type's question schema — never model-estimated.
  Streak/rest-day math, state grading, River layout, pin math (sin/cos orbit) are pure typed code.
  Person disambiguation is a hard gate: the merge NEVER auto-merges two same-named people; on first
  ambiguity the AI must confirm ("work-Sara, not Instagram-Sara, right?").
- **Why:** The lyfesum law ("engines compute, models narrate") recurs here with higher stakes: a wrong
  auto-merge of two Saras corrupts the user's life story irreversibly; a model-guessed awareness %
  drifts between calls. Numbers users see must be recomputable and stable. The model's irreplaceable
  jobs — extraction proposals, Pom's voice, prep-mode reasoning, titles, recaps — are all narration or
  proposal, never final arithmetic or final identity resolution.
- **Graduates as:** "The model proposes (deltas, titles, narration); deterministic typed code computes
  (awareness %, streaks, states, merges). Person merges are gated on explicit confirmation. No
  user-facing number is model-estimated."

### C5. Backend proxy owns all AI; the client never holds a key or assembles a prompt (PROPOSED)
- **The decision:** Thin client → our backend → LLM API (no-training tier, verified contractually).
  All prompt layers (persona+voice register+softness laws / surface context / retrieved structured
  memory with folded-flags / conversation) are assembled server-side. The client sends utterance +
  surface identifiers; it receives typed responses (chat text, delta sets, check-in copy). API keys
  never ship in the binary.
- **Why:** §14 specifies it, and C2 requires it (minimum-necessary context and no-training guarantees
  are only auditable in one server-side place). It also makes the softness filter (C3) enforceable at
  a single choke point, and lets prompts iterate without app releases.
- **Graduates as:** "All AI calls go through our backend proxy; prompts assembled server-side; keys
  never on device; client speaks only typed request/response contracts."

### C6. First-class numbers are computed at write and stored; views only read (PROPOSED)
- **The decision:** `awarenessPct`, `streakCount` (+ rest-day state), chapter `state`, and per-person
  `mood` are computed when the relevant write happens (delta merge, day close) and stored on the model
  object. No SwiftUI view re-derives a headline number.
- **Why:** The MENtality home-triangle mistake, re-derived for Keeper: awareness appears on globe pins,
  chapter headers, and world-contents rows; the streak appears on World, Streak page, profile stats.
  Re-derivation per view = drift across surfaces = "she doesn't actually know me" = trust broken.
  Decay-on-inactivity is a scheduled write, not a read-time computation.
- **Graduates as:** "awarenessPct, streak, states are computed at write (merge/day-close), stored, and
  only read by views. Never recomputed in a view."

### C7. Data layer behind `Services/`; SwiftData details never leak past it (PROPOSED)
- **The decision:** SwiftData (`@Model`, encrypted store per C2) is owned by `Services/Store/`. Views
  and features consume `@Observable` read models + a typed command surface; they do not construct
  `ModelContext` queries ad hoc. The store boundary is where encryption, migration, and the delta-merge
  live. (Whether `@Query` is permitted in leaf list views is a fight item — see F11 — the default
  posture is no, revisit if it fights the framework.)
- **Why:** Testability first (the extraction merge MUST be testable against transcript fixtures with a
  fake store — that is M1's whole verification story), one home for SwiftData's sharp edges (migration,
  predicate limits, CloudKit constraints), and E2E-sync (F3) will live at this boundary. Not for
  swappability — that justification stays refuted.
- **Graduates as:** "SwiftData lives behind `Services/Store/`; the merge engine and encryption live
  there; features consume typed read models + commands."

### C8. One state pattern: SwiftUI + @Observable MVVM-lite (PROPOSED)
- **The decision:** Vanilla SwiftUI + `@Observable` models + async/await; business logic — the
  extraction-session state machine, the vent capture flow, the prep-mode assembly, the globe rotation
  model — lives in testable `@Observable` models, not views. Navigation via a `Route` enum + one
  `navigationDestination(for:)` + typed path → `@Observable` Router (notification deep links route
  through it — every notification opens its owning surface). DI mechanism per house standard
  (swift-dependencies) unless fought down.
- **Why:** Third app on this pattern; it held on affirmly (including for a speech state machine, which
  Keeper's vent shares). No TCA, no mixed paradigms — consistency across the three apps is itself an
  asset (shared reviewer instincts, shared gotcha docs).
- **Graduates as:** "SwiftUI + @Observable MVVM-lite, one pattern; logic in models, not views; Route
  enum + Router; deep links route through it."

### C9. Walled modules behind protocols: the globe renderer, voice capture, paywall (PROPOSED)
- **The decision:** (a) **GlobeKit** — the 2.5D orbit engine (pin math, drag, depth scaling) is a
  walled module with a typed input (chapters + states + awareness) and no knowledge of the store; the
  whitepaper's "SceneKit later, only if needed" swap happens behind this wall or not at all. (b)
  **Voice capture** — on-device `SFSpeechRecognizer` hold-to-talk, behind a protocol, faked in tests
  (you cannot unit-test a live mic). (c) **Paywall/StoreKit** — walled; cosmetic streak rewards stay
  free and outside it. Start as folders/targets; SPM only when build time demands.
- **Why:** Each wall has a concrete forcing function (a possible renderer swap; untestable hardware;
  a monetization surface that must never infect the core loop). No other pre-modularization — the
  cargo-cult warning applies to walls too.
- **Graduates as:** "GlobeKit, voice capture, and the paywall are walled behind protocols; the core
  loop never imports them directly. Capture is faked in tests; the globe engine is store-blind."

### C10. Scheduled intelligence is server-driven; user reminders are local (PROPOSED)
- **The decision:** The check-in engine (scan upcoming/open events + prefs → generate check-ins in
  Pom's voice), monthly recap letters, and awareness decay run server-side (cron on the backend, F1)
  and arrive as user-facing push. User-created tiny-task reminders (dose at 22:00) are LOCAL
  notifications — they are user-authored schedules, work offline, and touch no AI. Quiet hours +
  per-reminder exemptions are our logic. Pre-permission pattern everywhere. Every scheduled job gets a
  row in the cron ops README the day it is wired, and post-mortems are written there when delivery
  breaks (the affirmly device-token incident is the cautionary tale).
- **Why:** Client-side timers for the check-in engine are unreliable (OS-scheduled, no guarantee) and
  would require shipping prompt logic to the device (violates C5). But affirmly's C4 amendment showed
  local notifications are RIGHT where server delivery adds nothing — Keeper's tiny tasks are exactly
  that case, so we decide it up front instead of amending later.
- **Graduates as:** "Check-ins/recaps/decay are server-driven push; user-authored reminders are local
  notifications; quiet-hours logic is ours; every cron job is logged in ops the day it's wired."

## Approaches we explicitly DON'T take
- **A second write path.** No screen writes model objects around the extraction pipeline (C1).
- **Plaintext server-side memory.** No architecture where the server can read the story (C2; mechanism F3).
- **Prompt-only enforcement of the never-list.** Softness is structural (C3).
- **Model-computed numbers or auto-merged people.** Engines compute (C4).
- **Keys or prompt assembly on device.** Proxy owns AI (C5).
- **SceneKit for v1.** The 2.5D illusion ships; the wall (C9) keeps the upgrade honest.
- **Anonymous use in v1.** Sign-in required at onboarding end, after the pledge (whitepaper §15).
- **Surveillance features.** "Check his followers weekly" is not supported, structurally (§19).
- **TCA / mixed paradigms; long-lived mocks; horizontal layers.** House standards hold.

## The seams (human-reviewed, never generated unsupervised)
1. The extraction delta schema + merge/disambiguation rules (C1, C4) — the heart.
2. Encryption & key management; the E2E sync design (C2, F3); erase/export paths.
3. The prompt layer stack + softness filters + crisis routing (C3, C5, §14 safety) — safety ships v1.
4. DB schema (server-side) + whatever RLS/tenancy model F1 lands on.
5. The awareness schemas per chapter type (they define the product's "knowing you" feel).
6. Auth (Sign in with Apple + magic link), entitlements, alternate icons, Face ID lock.
7. The paywall placement + StoreKit config (M8).

## Net-new organs this approach adds
- **`docs/extraction.md`** — THE spec (schema, merge rules, disambiguation, awareness scoring), written
  before M1 code, with a transcript-fixture test table. The signal-score.md of this app.
- **`prompts/` as versioned artifacts** with a prompt-suite (softness/never-list red-team cases run
  against every prompt change) — new organ; no prior app had a safety-critical prompt layer.
- **`DesignSystem/CLAUDE.md`** — created at M0 with the token table + the affirmly Figma fidelity
  protocol (metadata-first, per-node, token-first, screenshot-diff deltas table). Blocked on F7 for
  real node references; the theming engine (6 themes as semantic tokens) does not wait for it.
- **Milestone contract packages** (`day-zero/M*-CONTRACTS.md`) before each milestone's code — the
  affirmly pattern, adopted wholesale: proposed schema/types/tests + open questions, reviewed first.
- **`LEXICON.md`** from day one (smyle's naming drift is the lesson) — seeded with the whitepaper's
  unusually rich vocabulary; graveyard ready for the F5 renames.

## Slice order — see `day-zero/ROADMAP.md` (M0–M8 from the whitepaper, gated by the Decision Log).

## Expectations of the agent
- Contracts before code: types + decode boundary + acceptance test first; milestone contract package
  before each milestone.
- M1 is proven with transcript fixtures before any UI polish exists to hide behind.
- Vertical slices; never commit red; loading/empty/error on every screen; device-verify on a confirmed
  build number for anything touching mic, Face ID, icons, notifications, or StoreKit.
- All UI from the designs via the fidelity protocol once F7 closes — a slice without a design stops
  and asks. Until then, UI work is structure + tokens only, no "1:1" claims.
- Stop and flag any contradiction with a locked contract — never silently diverge.
