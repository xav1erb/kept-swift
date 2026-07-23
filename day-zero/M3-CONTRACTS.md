# M3-CONTRACTS — World globe + new chapter (the home surface)

<!-- CONTRACT PACKAGE (NN#2): reviewed BEFORE M3 code. STATUS: APPROVED by Xavier 2026-07-23 —
     all four §7 rulings closed on the recommended options; record + amendments in §8.
     Sources: whitepaper §2.3 (nav), §5 (the World globe), §6 (new chapter), §3 (states, awareness
     grades); contracts C4/C6 (engines compute), C7/F11 (read models only), C8 (Route/Router),
     C9 (GlobeKit is a walled, store-blind module), F7 (whitepaper-driven identity; no "1:1" claims
     until the Figma file lands). Seams touched: NONE that are still open — GlobeKit is store-blind
     math; the World surface is a read over the M0/M1 store. This is the most autonomous milestone:
     no key, no live proxy, no crypto/sync decision required.
     API facts to verify at implementation (AGENTS.md tripwires): SwiftUI Canvas/TimelineView for the
     idle spin, DragGesture velocity, conicGradient for the awareness ring, matchedGeometry for pin→
     sheet. Read shipped headers before writing. -->

## 1. Scope

**In:** the `Features/World` home surface fed by `StoreReader` (C7) — top row (＋ new chapter · title
`"{name}'s world ✨ / everything in its place"` · 🔥 streak chip) · the **GlobeKit** 2.5D engine
(orbit math, drag-to-spin, idle auto-rotation, depth scale/opacity/z-order, pins with awareness rings
+ state sublines) · the dashed "＋ Start a new chapter" row · the **Next up** card · recent chapter
cards · state-reactive greeting + Pom pose · every tap deep-links through the C8 `Router`. Plus the
`Features/NewChapter` **grid** (10 fixed types, per-type question-count tags, sensitive types show no
count) and its launch point. Loading/empty/error on every surface (NN#6) — an empty world is never a
blank page.

**Out (explicitly):** the scripted new-chapter *question sequence itself* (it reuses M2's
`InterviewEngine` — see §5, this milestone owns the grid + launch, not the engine) · chapter detail /
chat / timeline (M4 — a pin tap lands on an M4 stub until then) · prep mode (M4) · the River (M5) ·
Tell Pom capture (M5) · real Pom art + the 5 stub theme palettes (F7 — placeholder Pom, Cloud Cream
is the only fully-specified theme) · SceneKit (never in v1 — the C9 wall keeps that swap honest).

**Done (ROADMAP M3):** pins reflect store state live; a new chapter created via its sequence appears
on the globe with a correct awareness ring.

## 2. GlobeKit — the walled engine (C9, store-blind, types first)

GlobeKit **cannot import `Services/Store`** (README + C9). It defines its OWN value-type input; the
World feature maps `ChapterSummary` → this input (§3). Pure geometry, no SwiftData, no `Color` from
the theme engine — colors arrive pre-resolved as tokens so the engine never reaches into app state.

```swift
// Kept/GlobeKit/ — no import of Services/Store, ever.

struct GlobePin: Identifiable, Equatable, Sendable {
    let id: UUID                       // == chapter id (opaque to GlobeKit; used only for tap-out)
    let iconRef: String                // rendered by the host via a closure; GlobeKit places, host draws
    let awarenessPct: Int              // 0–100, already computed & stored (C6) — GlobeKit never recomputes
    let ringColor: GlobeTokenColor     // grade→color resolved by host (§3); engine just draws it
    let sublineText: String            // "fully aware · 100%" — host-built copy; engine lays it out
    let statusLine: String?            // live chapter status ("talk tonight"); nil = none
    let lon: Double                    // stable longitude on the sphere (host-assigned, deterministic)
}

struct GlobeConfig: Equatable, Sendable {
    let radius: CGFloat
    let scaleRange: ClosedRange<CGFloat>   // 0.62...1.0 (whitepaper §5)
    let idleRadiansPerSecond: Double       // slow auto-rotation
    let behindBlurMax: CGFloat
}

// Pure output of the orbit math for one pin at the current rotation. The layout IS the contract —
// golden-value tested (LOOP.md loop-safe: deterministic, no Date.now/random in the math).
struct PinLayout: Equatable, Sendable {
    let id: UUID
    let xOffset: CGFloat               // sin(lon + rot) × radius
    let scale: CGFloat                 // lerp over scaleRange by (cos(lon+rot)+1)/2
    let opacity: Double                // depth-driven
    let zIndex: Double                 // cos(lon+rot): behind-globe pins sink under it
    let blur: CGFloat                  // behind pins get up to behindBlurMax
    let isBehind: Bool                 // cos(lon+rot) < 0
}

@Observable final class GlobeEngine {
    private(set) var rotation: Double          // radians; idle tick + drag both add here
    func layout(pins: [GlobePin], config: GlobeConfig) -> [PinLayout]   // pure fn of rotation
    func drag(deltaX: CGFloat, config: GlobeConfig)                     // pan → rotation delta
    func tick(dt: TimeInterval, config: GlobeConfig)                    // idle auto-rotation
    func settle()                                                       // momentum decay after drag
    func pinHitTest(at point: CGPoint, layouts: [PinLayout]) -> UUID?   // front-most wins
}
```

- **Longitude assignment is deterministic, not random** (LOOP.md): pins are spread by a stable rule
  — `lon = 2π × (stableIndex / count)`, `stableIndex` = the chapter's `priority` then `createdAt`
  tiebreak — so the same world lays out identically every launch and golden tests are stable. Adding a
  chapter re-spreads deterministically; the host animates the delta.
- **Store-blindness is a test, not a convention:** a GlobeKit target/module test asserts it has no
  dependency edge to `Services/Store` (the C9 wall, mechanically enforced).

## 3. The store → globe mapping (World feature owns the boundary)

The World feature sees both worlds and does the translation the engine can't:

- `ChapterSummary.awarenessPct` → **grade** (pure function, whitepaper §3):
  `≥90 → .fullyAware (mint)`, `55…89 → .gaining (gold)`, `<55 → .tellMeMore (lilac)`.
  Colors resolve through the M0 `ThemeTokens` (mint/gold/lilac) — the mapping is deterministic display
  of an already-stored number, **not** a C6 violation (no headline number is recomputed; the pct comes
  straight off the snapshot).
- `sublineText` copy bank (whitepaper §5, verbatim grade phrasing): `"fully aware · {pct}%"` /
  `"needs a bit more · {pct}%"` / `"tell me more · {pct}%"`.
- `ringColor` band and `state`→accent both route through tokens (M0 §4: warm→mint, quiet→blue,
  tense→rose) — no hardcoded hex at call sites.
- `isResting` chapters (closed/resting) render dimmed and do not pulse; they still orbit.

## 4. The World surface (Features/World, C8)

- `@Observable WorldModel` consuming `StoreReader` snapshots (never `@Model`, never `@Query` — F11).
  Rebuilds pins from `chapters()`; the streak chip reads `UserProfileSnapshot.streakCount` /
  `streakRestDayUsed` (C6 — stored, never recomputed here).
- **Next up card (C4 — engine selects, does not estimate):** deterministic pick of the most important
  upcoming thing = the nearest future `EventSnapshot` where `isUpcoming`, tiebroken by chapter
  `priority`. The card's **fields are typed** (event title, relative date, prep-armed bool, check-in
  bool); the rendered sentence is a **typed template over those fields**, assembled in-app — no network
  call renders the home screen, and no number is model-estimated. (Whether that line may instead be a
  *cached* model phrase is §7 Q2.)
- **State-reactivity (whitepaper §5):** greeting + Pom pose are a pure function of world state — an
  imminent pinned event → alert pose + "Big evening. I'm right here."; calm day → sleepy. The pose
  set is typed cases over a placeholder Pom (F7); copy is a typed bank (no guilt strings — the §19
  never-bank test from C3 applies to this bank too).
- **Deep links (C8/C10):** `＋` → `Route.newChapter`; streak chip → `Route.streak`; pin tap →
  `Route.chapter(id)`; recent card → same. Every one goes through `Router.open`, so a notification can
  land on any of them. New `Route` cases: `.newChapter`, `.chapter(UUID)` (exists), `.streak` (exists).
- **Empty/loading/error (NN#6):** loading = breathing globe skeleton; **empty = one lit chapter + "The
  rest, we'll light together"** (post-onboarding there is always ≥1 chapter, but a defensive empty
  ships); error = a soft retry card, never a stack trace.

## 5. New chapter — grid + launch (Features/NewChapter)

- Grid of the **10 fixed `ChapterType`s** (M0 enum, verbatim), each card = icon · one-liner ·
  question-count tag. **Counts (whitepaper §6):** relationship 7 · family 6 · friendship 5 · work 6 ·
  health 5 · money 4 · passion 4 · growth 5. **`privateCorner` and `grief` show NO count** and render
  "goes gently" — `ChapterType.isSensitive` already gates this (M0); the **never-test** asserts no
  count string is ever produced for a sensitive type (C3, structural).
- Footer copy verbatim: "Pom will ask a few questions to build this room — you can stop anytime."
- CTA "Begin this chapter with Pom →" launches that type's scripted sequence. **Dependency (see §7
  Q1):** that sequence is M2's shared `InterviewEngine` running a chapter-type node list — M3 owns the
  grid + the launch route, **not** a second engine (C1: one path; no parallel scripted-chat engine).
  The per-type question schemas (the awareness slots) already live in `AwarenessSlots.swift` (M1).

## 6. Acceptance tests (Swift Testing) + device-verify

1. **Orbit golden values:** for a fixed pin set + rotation grid, `layout(...)` matches precomputed
   `PinLayout`s (x, scale, opacity, zIndex, blur, isBehind) within ε. Depth ordering correct; behind
   pins blurred and sunk. Deterministic across runs (LOOP.md).
2. **Store-blindness:** GlobeKit has no build/import edge to `Services/Store` (C9 wall).
3. **Grade mapping:** 0/54/55/89/90/100 → tellMeMore/tellMeMore/gaining/gaining/fullyAware/fullyAware,
   correct token colors; subline copy exact.
4. **Next-up selection:** given seeded events, picks nearest-future upcoming, priority tiebreak; no
   upcoming → card hidden (not a fake line).
5. **Never-tests (C3):** no question-count string for `privateCorner`/`grief`; the World Pom copy bank
   contains no guilt string; a resting chapter never pulses.
6. **Router:** ＋/pin/streak/recent all resolve to the right `Route`; a `kept://chapter/<uuid>` deep
   link lands on the pin's chapter (NN#7 — unknown links refused loudly).
7. **Live reactivity:** merging a delta that raises `awarenessPct` re-grades the ring on next snapshot
   (drives the M3 "done" check via a fixture-fed store, no live proxy).
8. **Device-verify (confirmed build number):** globe spins by drag + idles; depth reads as 2.5D; pins
   legible at min scale; theme switch re-skins rings/greeting live; deep links land; 60fps-ish, no hitch
   on a mid-tier device (Instruments if it stutters).

## 7. Open questions (rulings needed before code)

1. **New-chapter sequence dependency:** confirm M3 ships the **grid + launch only**, with the running
   sequence being M2's `InterviewEngine` (recommended — C1, one path). That makes M3's *globe* fully
   buildable now and its *new-chapter completion* inherit M2's readiness. Alternative (not recommended):
   a minimal M3-local sequence runner, later merged — risks a second write path.
2. **Next-up phrasing:** typed template over structured fields (recommended — offline, deterministic,
   no home-screen network) or a *cached* model-written line refreshed by the check-in engine (M6)?
   Either way the *selection* stays typed code (C4).
3. **Bottom-sheet pin preview:** whitepaper calls it "optional." Ship the preview sheet in M3, or tap
   → straight to the chapter (M4)? Recommended: straight-through in M3, preview as an M4 polish item.
4. **Idle spin default:** on by default (recommended, matches "slow idle auto-rotation") with a reduce-
   motion honor (accessibility), or off until first interaction?

## 8. Rulings (Xavier, 2026-07-23) + ratification amendments

All four §7 questions closed on the recommended options:

1. **Sequence = M2's shared `InterviewEngine`.** M3 generalizes the engine behind a script-provider
   seam (the onboarding script becomes one provider; each chapter type's sequence another, generated
   from the `AwarenessSlots` tables). One scripted-chat path (C1); no M3-local runner, ever.
2. **Next-up line = typed template** over structured fields, assembled in-app. No network renders the
   home screen. A cached model phrase may *layer on* at M6 via the check-in engine — new decision row
   then, not silent drift.
3. **Pin tap → straight to `Route.chapter(id)`** (M4 stub until chapter detail lands). The preview
   sheet moves to M4 as a polish item.
4. **Idle spin ON by default, Reduce Motion honored** (spin off when the system setting is on; drag
   always works).

**Amendments (facts verified against the codebase at ratification):**

- **A1 — `ChapterSummary` gains `priority: Int` + `createdAt: Date`** (both already on the `@Model`);
  the §2 deterministic-longitude rule sorts on them. Snapshot builder updated in `KeptStore`.
- **A2 — Engine reuse is a parameterization, not a fork:** `InterviewEngine`'s node lookup + branching
  move behind a `ScriptProviding` seam; the M2 onboarding flow keeps its exact behavior (M2 tests stay
  green, untouched). Chapter sequences write through the SAME paths: typed slot commands for
  chips/fields, the C1 utterance queue for free text (flushed immediately when signed-in + configured).
- **A3 — C9 wall enforcement mechanism:** single app target today, so the "no dependency edge" test is
  a source scan — no `GlobeKit/` file may import SwiftData/reference `Services/Store` symbols. If
  GlobeKit graduates to its own module target later, the scan upgrades to a real target boundary.
