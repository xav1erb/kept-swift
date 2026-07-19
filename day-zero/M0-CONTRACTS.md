# M0-CONTRACTS — Foundations

<!-- CONTRACT PACKAGE (NN#2): proposed schema, types, tests, and open questions — reviewed BEFORE
     M0 code starts. STATUS: APPROVED — Xavier ruled on all five open questions 2026-07-19 (§8,
     rulings inline). Sources: whitepaper §2.2/§2.3/§3/§15, ROADMAP M0, contracts C2/C6/C7/C8. -->

## 1. Scope

**In:** design tokens + theming engine (6 themes, live re-skin proven on a test screen) · Fraunces +
Quicksand bundled · nav shell (5-slot bar, Pom center button) · `Route` enum + `Router` · the §3 data
model in the encrypted store behind `Services/Store/` · app-lock scaffold.

**Out (explicitly):** extraction, deltas, AI, backend (M1) · onboarding (M2) · any real surface UI
(M3+) · sync/E2E blob layer (M1+, seam) · Pom art (F7 — placeholder circle only) · Figma fidelity
(F7 gate; token-structure UI only, no "1:1" claims).

**Done (ROADMAP):** theme switch re-skins the sample screen live · models round-trip through the
encrypted store · app-lock scaffold present.

## 2. Data model (§3 → SwiftData, behind `Services/Store/` per C7)

All `@Model final class`, IDs `UUID`, enums as `String`-raw `Codable`. No CloudKit (F2/F3 ruling:
custom E2E sync), so `#Unique` and non-optional relationships are usable — iOS 18 floor confirmed.

### Enums (the controlled vocabulary, LEXICON-aligned)

```swift
enum ChapterType: String, Codable, CaseIterable {
    case relationship, family, friendship, work, health, money, passion,
         privateCorner, growth, grief
    var isSensitive: Bool { self == .privateCorner || self == .grief }  // §19: no question counts
}
enum ChapterKind: String, Codable { case situational, dimension }
enum ChapterState: String, Codable { case warm, fine, quiet, tense, complicated }
enum PersonMood: String, Codable { case warm, fine, quiet, tense, complicated, drifting }
enum RoleFlag: String, Codable { case confidant, ally, witness, trigger }
enum Valence: String, Codable { case bright, gold, neutral, storm, soft }
enum EventSource: String, Codable { case chat, vent, onboarding }
enum CommitmentStatus: String, Codable { case held, broken, resolved }
enum AchievementCategory: String, Codable { case courage, consistency, closure, selfcare, milestone }
enum OnboardingMode: String, Codable { case focus, full }
enum VoiceProfile: String, Codable { case soft, realWithMe, sunshine, calm }
enum Theme: String, Codable, CaseIterable {
    case duskLilac, warmCoquette, goldenHour, darkAcademia, cloudCream, midnight
}
```

### Models (fields verbatim from §3; stored numbers per C6)

```swift
@Model final class UserProfile {          // "User" collides with framework naming
    @Attribute(.unique) var id: UUID
    var name: String; var age: Int?; var pronouns: String?
    var city: String?; var occupation: String?
    var theme: Theme; var voiceProfile: VoiceProfile
    var streakCount: Int                  // C6: written at day-close, never derived in views
    var streakRestDayUsed: Bool
    var onboardingMode: OnboardingMode?
    var followupQueue: [ChapterType]      // F10 semantics specced in M2-CONTRACTS
    var createdAt: Date
}

@Model final class Chapter {
    @Attribute(.unique) var id: UUID
    var type: ChapterType; var kind: ChapterKind
    var title: String                     // AI-generated (M1+); seeded manually in M0 tests
    var iconRef: String                   // AI-picked at creation, theme-palette
    var state: ChapterState
    var awarenessPct: Int                 // 0–100, C6: computed at merge, stored, read-only in views
    var priority: Int
    var isResting: Bool; var closingLetter: String?
    var createdAt: Date; var lastTouchedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Event.chapter) var events: [Event]
    @Relationship(deleteRule: .cascade, inverse: \Commitment.chapter) var commitments: [Commitment]
}

@Model final class Person {
    @Attribute(.unique) var id: UUID
    var name: String                      // NEVER a merge key alone — C4 disambiguation gate (M1)
    var relation: String; var age: Int?
    var mood: PersonMood; var roleFlags: [RoleFlag]
    var rituals: [String]; var priority: Int
    var notes: String                     // AI-maintained profile (M1+)
    var chapters: [Chapter]               // many-to-many
}

@Model final class Event {
    @Attribute(.unique) var id: UUID
    var chapter: Chapter
    var date: Date; var title: String; var body: String
    var valence: Valence
    var isOpen: Bool
    var isHealed: Bool                    // folded — the do-not-raise flag lives at prompt assembly (M1, C3)
    var isUpcoming: Bool
    var source: EventSource
}

@Model final class Commitment {
    @Attribute(.unique) var id: UUID
    var chapter: Chapter; var person: Person?
    var text: String; var dateMade: Date
    var status: CommitmentStatus
    var evidenceEvents: [Event]
    // C3/§19 by construction: no timer, no countdown, no "days since" field exists on this type.
}

@Model final class Goal {
    @Attribute(.unique) var id: UUID
    var chapter: Chapter?
    var text: String; var targetDate: Date?; var progressNote: String
}

@Model final class Reminder {
    @Attribute(.unique) var id: UUID
    var chapter: Chapter?
    var title: String
    var schedule: ReminderSchedule        // typed, NOT a cron string (Codable struct: time + repeat rule)
    var enabled: Bool
}

@Model final class NotificationPrefs {   // singleton row
    var frequency: CheckInFrequency       // daily | moderate | importantOnly
    var quietStart: Int?; var quietEnd: Int?   // minutes-from-midnight; nil = no quiet hours
    var exemptReminderIDs: [UUID]
    var genericLockScreenCopy: Bool       // F12: default TRUE
    var monthlyRecapEnabled: Bool
}

@Model final class Achievement {
    @Attribute(.unique) var id: UUID
    var key: String; var category: AchievementCategory
    var chapter: Chapter?
    var earnedAt: Date?; var progress: Double?; var isSecret: Bool
    // §19 by construction at M7: no conflict-triggered key will exist; never-test lands with M7.
}

@Model final class CrossLink {
    @Attribute(.unique) var id: UUID
    var fromChapter: Chapter; var toChapter: Chapter; var note: String
}
```

Notes for review:
- **"Dimension config"** (§3 mentions it without a shape) — proposed: defer its schema to
  M3-CONTRACTS (new-chapter flow owns it). Flagged, not silently dropped.
- **Read models / commands (C7, F11):** views never see `@Model` types. M0 ships
  `StoreReader` (typed value-type snapshots: `ChapterSummary`, `WorldSnapshot`, …) and
  `StoreCommands` (typed mutations), both `@Observable`-friendly. The M0 sample screen consumes only
  these. `@Query` does not appear anywhere (F11 — banned).
- **Decode boundary at M0:** none external (no AI yet). The store round-trip IS the M0 boundary
  test; extraction-delta `Codable` contracts come in M1-CONTRACTS.

## 3. Encryption posture at M0 (C2 — the local half only)

- SwiftData store file(s) under `NSFileProtectionComplete`; store URL owned by `Services/Store/`.
- **Master key + iCloud Keychain + client-side blob encryption is the M1 sync seam** — designed and
  reviewed there, not improvised at M0. M0 makes room for it (store init is async and key-aware in
  shape) but creates no keys.
- Test: assert the protection attribute on the store file. Full enforcement is device-verified
  (checklist §7).

## 4. Theming engine (§2.2 → semantic tokens)

```swift
struct ThemeTokens: Equatable, Sendable {
    let backgroundTop: Color; let backgroundBottom: Color   // vertical gradient
    let card: Color                                          // white ~85% + soft lilac shadow
    let ink: Color; let inkSoft: Color
    let rose: Color; let peach: Color; let mint: Color
    let gold: Color; let lilac: Color; let blue: Color
    let radiusCard: CGFloat                                  // 18–26pt band
}
```

- `Theme.cloudCream` uses the whitepaper's exact values (ink `#4A3F6B`, inkSoft `#8D81AD`, rose
  `#E88BA0`, peach `#F2B184`, mint `#8FCFAE`, gold `#E9C268`, lilac `#A893DD`, blue `#8EA3D8`).
  The other five are **stub palettes clearly marked STUB (F7)** behind the same tokens.
- `ThemeModel` (`@Observable`) injected via environment; switching theme republishes tokens — the
  live re-skin proof. Weather/state colors map through tokens (warm→mint, quiet→blue, tense→rose).
- Fonts: Fraunces (display) + Quicksand (UI), bundled (both OFL); `UIAppFonts` added via
  `project.yml` info properties; one `Font` accessor namespace, no ad-hoc `Font.custom` at call sites.

## 5. Nav shell + Route/Router (C8)

- Custom 5-slot bottom bar: World · River · **[Pom center button → Tell Pom sheet]** · Wins · You.
  Center button is a placeholder circle until F7 art. Chapters have no tab (entered from globe).
- ```swift
  enum Route: Hashable {
      case world, river, wins, you                       // tabs
      case chapter(UUID), streak                         // M0 defines mechanism; cases grow per milestone
  }
  @Observable final class Router {
      var tab: Route; var path: [Route]
      func open(deepLink: URL) -> Bool                   // every notification routes through here (C8/C10)
  }
  ```
- Tell Pom is a **sheet presentation state on Router**, not a `Route` in `path` (it overlays any tab).
- M0 tab surfaces are token-styled placeholders, each with honest loading/empty/error scaffolding
  (NN#6) — real designs land per milestone.

## 6. App-lock scaffold

- `AppLockModel` (`@Observable`): states `disabled / locked / unlocked`; triggers: cold start +
  background→foreground return; backed by `protocol AuthenticationContext` (LAContext behind it,
  **faked in tests** — C9 spirit). M0 = scaffold + unit tests; the real Face ID screen and
  device-verify belong to M2 (onboarding 4.10).

## 7. Acceptance tests (Swift Testing) + device-verify

1. **Store round-trip:** seed the full object graph (user, chapter, person, folded event, dated
   commitment with evidence, cross-link) → save → reopen a fresh container on the same URL → assert
   graph equality, relationship integrity, enum round-trip.
2. **File protection:** store file exists with `.completeFileProtection` attribute set.
3. **Theme engine:** all 6 themes produce distinct valid token sets; Cloud Cream matches the §2.2
   hex values exactly; switching `ThemeModel.theme` republishes tokens observed by the sample screen.
4. **Router:** tab switching; push/pop; a `kept://chapter/<uuid>` deep link resolves to
   `.chapter(id)`; unknown links refused loudly (NN#7 spirit).
5. **App lock:** state machine transitions with a faked `AuthenticationContext` (success, failure,
   cancel, disabled).

**Device-verify checklist (confirmed build number):** app launches · both fonts render (not
system-serif fallback) · theme switch re-skins the sample screen live · store file protection
attribute present on device · app-lock scaffold locks on cold start + background return when enabled.

## 8. Open questions — RULED by Xavier 2026-07-19

1. **DI: `swift-dependencies` adopted at M0** (as proposed).
2. **Snapshot testing: `swift-snapshot-testing` lands at M0** (against the defer proposal — ruled).
   Pinned to the greenlight simulator; stub-palette snapshots will be re-recorded when F7 lands,
   accepted cost.
3. **Store singletons: fetch-or-create accessors in `Services/Store/`** (as proposed). No
   `AppState` model.
4. **Stub palettes: agent-derived placeholders approved** under F7, marked STUB.
5. **`Dimension config`: deferred to M3-CONTRACTS** (as proposed).
