import Foundation
import SwiftUI

// The World home surface's model (M3-CONTRACTS §3/§4, C8). A read over the store: every number
// on screen was computed at write time (C6) — this file only *displays* stored state. The
// store→globe mapping lives here because GlobeKit can't see the store (C9) and the store can't
// see pixels (C7).

/// Whitepaper §3 awareness grades — deterministic display of an already-stored pct, not a C6
/// violation (no number is recomputed; the pct comes straight off the snapshot).
nonisolated enum AwarenessGrade: Equatable, Sendable {
    case fullyAware, gaining, tellMeMore

    static func grade(for pct: Int) -> AwarenessGrade {
        switch pct {
        case 90...: .fullyAware
        case 55...89: .gaining
        default: .tellMeMore
        }
    }

    /// Verbatim grade phrasing (whitepaper §5).
    var sublinePrefix: String {
        switch self {
        case .fullyAware: "fully aware"
        case .gaining: "needs a bit more"
        case .tellMeMore: "tell me more"
        }
    }

    func subline(pct: Int) -> String { "\(sublinePrefix) · \(pct)%" }

    /// Grade → token color (mint/gold/lilac) — resolved here so GlobeKit never sees ThemeTokens.
    func ringColor(_ tokens: ThemeTokens) -> Color {
        switch self {
        case .fullyAware: tokens.mint
        case .gaining: tokens.gold
        case .tellMeMore: tokens.lilac
        }
    }
}

nonisolated extension ChapterState {
    /// M0 §4 state→accent mapping, total over the vocabulary — no hardcoded hex at call sites.
    func accentColor(_ tokens: ThemeTokens) -> Color {
        switch self {
        case .warm: tokens.mint
        case .fine: tokens.peach
        case .quiet: tokens.blue
        case .tense: tokens.rose
        case .complicated: tokens.lilac
        }
    }
}

/// A GlobePin plus the host-side facts GlobeKit deliberately doesn't know.
struct WorldPin: Identifiable, Equatable {
    let pin: GlobePin
    let title: String
    let grade: AwarenessGrade
    let isResting: Bool
    /// §19 never-rule: a resting (healed/closed) chapter NEVER pulses — enforced at construction,
    /// asserted by the never-test.
    let shouldPulse: Bool

    var id: UUID { pin.id }
}

/// The Next-up card's typed fields (C4: the engine SELECTS, nothing is model-estimated). The
/// rendered sentence is a typed template over these — §8 ruling 2: assembled in-app, offline.
nonisolated struct NextUpCard: Equatable, Sendable {
    let eventId: UUID
    let chapterId: UUID
    let chapterTitle: String
    let eventTitle: String
    let relativeDay: String
    /// Typed-but-dormant until their milestones: prep mode arms at M4, check-ins at M6.
    let prepArmed: Bool
    let checkInArmed: Bool
}

nonisolated enum PomPose: String, Equatable, Sendable {
    case alert, cozy, sleepy
}

/// The World's typed copy bank (C3: the §19 never-bank test scans THIS type — greeting copy is
/// never assembled anywhere else).
nonisolated enum WorldCopy {
    static let subtitle = "everything in its place"
    static let greetingImminent = "Big evening. I'm right here."
    static let greetingUpcoming = "Something's coming up — I'm holding the details."
    static let greetingCalm = "All quiet in your world. I like these days."
    static let emptyWorld = "The rest, we'll light together."
    static let newChapterRow = "＋ Start a new chapter"
    static let loadError = "Your world is safe — it just didn't load. Try again?"
    static let nextUpHeader = "Next up"

    static var all: [String] {
        [subtitle, greetingImminent, greetingUpcoming, greetingCalm, emptyWorld,
         newChapterRow, loadError, nextUpHeader]
    }
}

@Observable
final class WorldModel {

    enum LoadState: Equatable { case loading, ready, failed }

    private let store: KeptStore
    let globe = GlobeEngine()

    private(set) var loadState: LoadState = .loading
    private(set) var pins: [WorldPin] = []
    private(set) var nextUp: NextUpCard?
    private(set) var pose: PomPose = .sleepy
    private(set) var greeting = WorldCopy.greetingCalm
    private(set) var userName = ""
    private(set) var streakCount = 0
    private(set) var recentChapters: [ChapterSummary] = []

    init(store: KeptStore) {
        self.store = store
    }

    /// Rebuild every read model from the store. Tokens come in because ring colors resolve here
    /// (theme switch → refresh re-skins the rings live).
    func refresh(tokens: ThemeTokens, now: Date = .now, calendar: Calendar = .current) {
        do {
            let profile = try store.userProfile()
            let chapters = try store.chapterSummaries()
            let upcoming = try store.upcomingEvents()

            userName = profile.name
            streakCount = profile.streakCount
            recentChapters = chapters
                .sorted { ($0.lastTouchedAt, $0.id.uuidString) > ($1.lastTouchedAt, $1.id.uuidString) }
                .prefix(4).map { $0 }
            nextUp = Self.selectNextUp(events: upcoming, chapters: chapters, now: now, calendar: calendar)
            pins = Self.buildPins(
                chapters: chapters, upcoming: upcoming, tokens: tokens, now: now, calendar: calendar
            )
            (pose, greeting) = Self.mood(nextUp: nextUp)
            loadState = .ready
        } catch {
            loadState = .failed
        }
    }

    // MARK: - Pure mapping (all static, all golden-testable)

    /// §2: longitude is deterministic, never random — stableIndex = priority desc, createdAt asc,
    /// id tiebreak; lon = 2π × index / count. The same world lays out identically every launch.
    static func buildPins(
        chapters: [ChapterSummary],
        upcoming: [EventSnapshot],
        tokens: ThemeTokens,
        now: Date,
        calendar: Calendar
    ) -> [WorldPin] {
        let ordered = chapters.sorted {
            ($1.priority, $0.createdAt, $0.id.uuidString) < ($0.priority, $1.createdAt, $1.id.uuidString)
        }
        let count = max(1, ordered.count)
        return ordered.enumerated().map { index, chapter in
            let grade = AwarenessGrade.grade(for: chapter.awarenessPct)
            let status = statusLine(for: chapter, upcoming: upcoming, now: now, calendar: calendar)
            return WorldPin(
                pin: GlobePin(
                    id: chapter.id,
                    iconRef: chapter.iconRef,
                    awarenessPct: chapter.awarenessPct,
                    ringColor: grade.ringColor(tokens),
                    sublineText: grade.subline(pct: chapter.awarenessPct),
                    statusLine: status,
                    lon: 2 * .pi * Double(index) / Double(count)
                ),
                title: chapter.title,
                grade: grade,
                isResting: chapter.isResting,
                shouldPulse: status != nil && !chapter.isResting
            )
        }
    }

    /// Live status: the chapter's nearest upcoming event within a week — "The talk · tonight".
    static func statusLine(
        for chapter: ChapterSummary,
        upcoming: [EventSnapshot],
        now: Date,
        calendar: Calendar
    ) -> String? {
        guard let event = upcoming.first(where: { $0.chapterId == chapter.id && $0.date >= calendar.startOfDay(for: now) })
        else { return nil }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: event.date)
        ).day ?? 0
        guard days < 7 else { return nil }
        return "\(event.title) · \(relativeDay(from: now, to: event.date, calendar: calendar))"
    }

    /// C4: a deterministic pick, never an estimate — nearest future upcoming event, chapter
    /// priority tiebreak, id tiebreak. No upcoming → nil (the card hides; no fake line).
    static func selectNextUp(
        events: [EventSnapshot],
        chapters: [ChapterSummary],
        now: Date,
        calendar: Calendar
    ) -> NextUpCard? {
        let chaptersById = Dictionary(uniqueKeysWithValues: chapters.map { ($0.id, $0) })
        let candidates = events
            .filter { $0.date >= calendar.startOfDay(for: now) }
            .compactMap { event -> (EventSnapshot, ChapterSummary)? in
                guard let chapterId = event.chapterId, let chapter = chaptersById[chapterId]
                else { return nil }
                return (event, chapter)
            }
        guard let (event, chapter) = candidates.min(by: {
            ($0.0.date, $1.1.priority, $0.0.id.uuidString) < ($1.0.date, $0.1.priority, $1.0.id.uuidString)
        }) else { return nil }
        return NextUpCard(
            eventId: event.id,
            chapterId: chapter.id,
            chapterTitle: chapter.title,
            eventTitle: event.title,
            relativeDay: relativeDay(from: now, to: event.date, calendar: calendar),
            // M4: prep now really arms (Event.preparedAt); check-in intent stores at M4, fires M6.
            prepArmed: event.preparedAt != nil,
            checkInArmed: event.checkInArmed
        )
    }

    /// Typed relative-day descriptor: today/tonight/tomorrow/weekday/short date.
    static func relativeDay(from now: Date, to date: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return calendar.component(.hour, from: date) >= 17 ? "tonight" : "today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0
        let locale = calendar.locale ?? .current
        if (2..<7).contains(days) {
            return date.formatted(
                Date.FormatStyle(locale: locale, calendar: calendar).weekday(.wide)
            ).lowercased()
        }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar)
        )
    }

    /// Whitepaper §5 state-reactivity: greeting + pose are a pure function of world state.
    static func mood(nextUp: NextUpCard?) -> (PomPose, String) {
        guard let nextUp else { return (.sleepy, WorldCopy.greetingCalm) }
        if ["today", "tonight", "tomorrow"].contains(nextUp.relativeDay) {
            return (.alert, WorldCopy.greetingImminent)
        }
        return (.cozy, WorldCopy.greetingUpcoming)
    }
}
