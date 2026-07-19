# KEEPER — Roadmap

<!-- DAY-ZERO DOC → hoist to repo root at first commit (smyle convention). The single source of
     truth for where we stand. Vertical-slice milestones from whitepaper §18.
     STATUS: GRADUATED 2026-07-19 — all decision gates F1–F12 closed (see FIGHT-LIST.md).
     Remaining human-owned inputs: provisioning (docs/PROVISIONING.md), per-milestone contract
     approvals, device-verify passes, F5 naming before M8, F8 price confirm before M8.
     Legend: ☐ not started · ◐ in progress · ☑ done · 🔒 blocked · 👤 human-owned · 🛑 decide-first -->

## The rule

A milestone is **done** when its acceptance tests are green on real data AND its device-verify
checklist is ticked on a confirmed build number. Before a milestone starts, its contract package
(`day-zero/M<n>-CONTRACTS.md`) is written and reviewed — schema, types, tests, open questions.
The plan is a **dependency sequence, not a calendar.**

## Milestones

### M0 — Foundations `☑` (built 2026-07-19; device-verify confirmed by Xavier 2026-07-19)
Design tokens + theming engine (6 themes as semantic tokens, live re-skin proven with a test screen),
Fraunces + Quicksand bundled, nav shell (5-slot bar, Pom center button), Route/Router, data model (§3)
in the encrypted store behind `Services/Store/`, XcodeGen project.
**Done =** theme switch re-skins a sample screen live; models round-trip through the encrypted store;
app-lock scaffold present.

### M1 — Extraction pipeline + backend proxy (the heart) `◐` (contracts APPROVED + spec RATIFIED 2026-07-19; 👤 live smoke test + milestone close need PROVISIONING item 2)
`docs/extraction.md` FIRST (delta schema, merge rules, disambiguation gate, awareness scoring).
Backend proxy up (prompt assembly server-side, no-training tier verified); utterance → deltas →
deterministic merge → store; person disambiguation; awareness % per chapter-type schema; the
prompt-suite harness with the first never-list red-team cases.
**Done =** a corpus of transcript fixtures (incl. the whitepaper's onboarding script + multi-topic
vents + two-Saras cases) produces the expected object graph, asserted by tests — **before any UI
polish exists.** This milestone is the app.

### M2 — Onboarding `☐` (F6 restricted-u18 spec + F10 followupQueue spec drafted in M2-CONTRACTS 👤 approval)
**Canonical spec: `docs/onboarding.md`** — screen-by-screen with verbatim copy, the scripted
interview (fixed questions + AI acknowledgments), fork mechanics, extraction mappings, and the
11-point acceptance list. Engine = the affirmly onboarding pattern (linear @Observable step machine,
scaffold + progress bar, resumable draft store, RootView gate), adapted: local encrypted store is
primary, sign-in last attaches backup.
**Done =** the 11 acceptance checks in `docs/onboarding.md` §13 pass on device in both fork modes.

### M3 — World globe + new chapter `☐` (F7: whitepaper-driven brand identity; Figma 1:1 protocol activates when the file lands)
GlobeKit 2.5D engine (orbit math, drag, idle spin, depth scale/opacity/z-order), pins with awareness
rings + state sublines, streak chip, next-up card; new-chapter grid with per-type scripted sequences
(sensitive types: no question counts — never-test).
**Done =** pins reflect store state live; a new chapter created via its sequence appears on the globe
with a correct ring.

### M4 — Chapter detail `☐`
Chat tab with full context injection (folded items flagged do-not-raise); prep mode components
(reframe, likely-answers card, perspective calibration, keep-card, opening sentence, post-event
check-in arming); timeline tab with valence nodes + the folded-healed fold/expand/refold behavior.
**Done =** prep mode renders all designed components from a seeded chapter; folded events never
surface in chat unprompted (prompt-suite case), fold behavior exact.

### M5 — Tell Pom + the River `☐` (F9 closed: type-only fallback)
Center-button capture sheet (fresh each session), hold-to-talk voice, contextual smart prompt + 6
template chips, multi-topic filing → **filing confirmation with deep-link chips** (ships v1,
non-negotiable); the River (S-curve layout engine, bank assignment, time markers, filters, §9 grading
rules incl. positives over-represented).
**Done =** a three-topic vent files to three chapters and says so; River renders the seeded world with
correct grading (only true open wounds pulse).

### M6 — Check-in engine + notifications `☐` (F12 closed: generic phrasing default ON) 👤 needs APNs key (PROVISIONING item 3)
Server-side scan of upcoming/open events × prefs → check-ins in Pom's voice; post-event replies route
into the owning chapter; local tiny-task reminders with quiet-hours + exemptions; pre-permission
pattern; deep links; cron ops README starts.
**Done =** a pinned "talk tonight" produces a next-morning check-in on device that deep-links into the
chapter; no guilt-copy string exists (never-test).

### M7 — Wins, Streak, Profile `☐`
Wins categories + blooming + secret wins + share cards (stripped by default — never-test);
soft streak (protected rest day, cosmetic-only milestones); profile: hero, three tree geometries
(auto-built from extraction, never a form), goals, reminders UI, notification prefs, Pom settings,
the seal (Face ID toggle, export, erase with server+AI purge, sign out).
**Done =** erase provably purges all three layers; share card contains no names; trees render from
extracted people.

### M8 — Recap, closing, paywall, ship `☐` (👤 F5 naming + F8 final price confirm before ASC config)
Monthly recap letter (first Sunday), chapter-closing ceremony (letter → Resting → 📖 win), paywall:
**Superwall presents / StoreKit 2 mirror is truth — `docs/monetization.md` is the contract**
($12.99/mo · $69.99/yr + 7-day trial · $4.99/wk dark SKU; free tier 3 chapters / 5 vents/day /
history never paywalled; triggers at proven-value moments, none in onboarding), polish, App Store:
17+ rating, privacy nutrition labels matching the architecture (C2), reviewer notes.
**Done =** submission-ready build; labels audited against §15 mechanisms; `.storekit` = ASC = store
description on prices.

## Decision Log
`day-zero/FIGHT-LIST.md` is the record: **F1–F12 all closed 2026-07-19** (plus prime directive,
C1–C10 approval, defaults bundle, provisioning ownership). New decisions get new dated rows there.

## The standing organs (grow as the build runs)
- `docs/extraction.md` — the load-bearing spec (before M1).
- `docs/VERIFY-CHECKLIST.md` + `docs/QA-CHECKLIST.md` — device gates (from M0).
- `DesignSystem/CLAUDE.md` — tokens + Figma fidelity protocol (M0; node refs when F7 closes).
- `Services/Store/CLAUDE.md` — SwiftData/E2E gotchas log (from M0, dated incidents).
- `prompts/` + the prompt suite — versioned, red-teamed (from M1).
- `supabase|backend/cron/README.md` — job registry + post-mortems (from M6, or M1 if proxy is cron-hosted).
- `LEXICON.md` — from day zero; graveyard on every rename.
