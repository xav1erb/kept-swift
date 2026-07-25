import Foundation
import SwiftUI
import Testing
@testable import Kept

// M3-CONTRACTS §6.1–§6.6: orbit golden values, the C9 store-blindness wall, grade mapping,
// next-up selection, the §19 never-tests, and router resolution.

@MainActor
struct GlobeKitTests {

    private let config = GlobeConfig(
        radius: 100, scaleRange: 0.62...1.0, idleRadiansPerSecond: 0.06,
        behindBlurMax: 3, momentumDecayPerSecond: 0.05
    )

    private func pin(lon: Double) -> GlobePin {
        GlobePin(
            id: UUID(), iconRef: "heart.fill", awarenessPct: 50, ringColor: .mint,
            sublineText: "tell me more · 50%", statusLine: nil, lon: lon
        )
    }

    @Test func orbitGoldenValuesAtRotationZero() {
        let engine = GlobeEngine()
        let pins = [pin(lon: 0), pin(lon: .pi / 2), pin(lon: .pi), pin(lon: 3 * .pi / 2)]
        let layouts = engine.layout(pins: pins, config: config)

        // Front center: full scale, full opacity, no blur, top of the z-order.
        #expect(abs(layouts[0].xOffset - 0) < 0.001)
        #expect(abs(layouts[0].scale - 1.0) < 0.001)
        #expect(abs(layouts[0].opacity - 1.0) < 0.001)
        #expect(abs(layouts[0].zIndex - 1.0) < 0.001)
        #expect(layouts[0].blur == 0)
        #expect(!layouts[0].isBehind)

        // Right edge: half depth.
        #expect(abs(layouts[1].xOffset - 100) < 0.001)
        #expect(abs(layouts[1].scale - 0.81) < 0.001)
        #expect(abs(layouts[1].opacity - 0.675) < 0.001)
        #expect(abs(layouts[1].zIndex) < 0.001)
        #expect(!layouts[1].isBehind)

        // Fully behind: min scale, min opacity, max blur, sunk under the globe.
        #expect(abs(layouts[2].xOffset) < 0.001)
        #expect(abs(layouts[2].scale - 0.62) < 0.001)
        #expect(abs(layouts[2].opacity - 0.35) < 0.001)
        #expect(abs(layouts[2].zIndex - (-1.0)) < 0.001)
        #expect(abs(layouts[2].blur - 3.0) < 0.001)
        #expect(layouts[2].isBehind)

        // Left edge mirrors the right.
        #expect(abs(layouts[3].xOffset - (-100)) < 0.001)
        #expect(abs(layouts[3].scale - 0.81) < 0.001)
    }

    @Test func orbitGoldenValuesAtFixedRotation() {
        // Precomputed literals for rotation 0.7 rad, lon 0 (not re-derived from the formula).
        let engine = GlobeEngine()
        engine.drag(deltaX: 70, config: config)  // 70pt / 100radius = 0.7 rad exactly
        let layout = engine.layout(pins: [pin(lon: 0)], config: config)[0]
        #expect(abs(layout.xOffset - 64.42176872) < 0.001)
        #expect(abs(layout.scale - 0.95532002) < 0.001)
        #expect(abs(layout.opacity - 0.92357371) < 0.001)
        #expect(abs(layout.zIndex - 0.76484219) < 0.001)
        #expect(!layout.isBehind)
    }

    @Test func layoutIsDeterministic() {
        // Same ops on two engines → identical layouts, run after run (LOOP.md).
        let pins = [pin(lon: 0.4), pin(lon: 2.1), pin(lon: 4.4)]
        let a = GlobeEngine()
        let b = GlobeEngine()
        for engine in [a, b] {
            engine.drag(deltaX: 33, config: config)
            engine.tick(dt: 0.5, config: config)
        }
        let layoutsA = a.layout(pins: pins, config: config).map { ($0.xOffset, $0.scale, $0.opacity) }
        let layoutsB = b.layout(pins: pins, config: config).map { ($0.xOffset, $0.scale, $0.opacity) }
        #expect(layoutsA.elementsEqual(layoutsB, by: ==))
    }

    @Test func idleTickAdvancesAndMomentumDecays() {
        let engine = GlobeEngine()
        engine.tick(dt: 1.0, config: config)
        #expect(abs(engine.rotation - 0.06) < 0.0001)  // exactly idleRadiansPerSecond × dt

        // A drag then settle imparts momentum that decays across ticks.
        engine.drag(deltaX: 10, config: config)
        engine.settle()
        let beforeMomentumTick = engine.rotation
        engine.tick(dt: 0.1, config: config, idle: false)
        let firstDelta = engine.rotation - beforeMomentumTick
        #expect(firstDelta > 0)
        engine.tick(dt: 0.1, config: config, idle: false)
        let secondDelta = engine.rotation - beforeMomentumTick - firstDelta
        #expect(secondDelta < firstDelta)  // decaying, not constant
    }

    @Test func hitTestFrontMostWinsAndBehindNeverHits() {
        let engine = GlobeEngine()
        let front = pin(lon: 0)
        let behind = pin(lon: .pi)  // xOffset ≈ 0 too — overlapping x-band, but behind
        let layouts = engine.layout(pins: [front, behind], config: config)
        #expect(engine.pinHitTest(at: CGPoint(x: 0, y: 0), layouts: layouts) == front.id)
        #expect(engine.pinHitTest(at: CGPoint(x: 200, y: 0), layouts: layouts) == nil)
    }

    /// §6.2 — the C9 wall, mechanically enforced (§8 A3): no GlobeKit source may import the
    /// data layer or reference store symbols.
    @Test func globeKitIsStoreBlind() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let globeKitDir = repoRoot.appending(path: "Kept/GlobeKit")
        let files = try FileManager.default.contentsOfDirectory(atPath: globeKitDir.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(!files.isEmpty)
        let forbidden = [
            "SwiftData", "KeptStore", "Services/Store", "ChapterSummary", "EventSnapshot",
            "ModelContext", "FetchDescriptor", "import Dependencies", "ThemeTokens",
        ]
        for file in files {
            let source = try String(contentsOf: globeKitDir.appending(path: file), encoding: .utf8)
            for token in forbidden {
                #expect(!source.contains(token), "\(file) breaches the C9 wall: \(token)")
            }
        }
    }
}

@MainActor
struct WorldModelTests {

    private var tokens: ThemeTokens { ThemeModel(theme: .cloudCream).tokens }

    /// Fixed calendar so relative-day strings are deterministic.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US")
        return cal
    }

    /// 2026-07-23 10:00 UTC (a Thursday).
    private var now: Date {
        DateComponents(calendar: calendar, year: 2026, month: 7, day: 23, hour: 10).date!
    }

    private func date(day: Int, hour: Int = 12) -> Date {
        DateComponents(calendar: calendar, year: 2026, month: 7, day: day, hour: hour).date!
    }

    private func chapter(
        id: UUID = UUID(), type: ChapterType = .relationship, title: String = "Us",
        pct: Int = 0, state: ChapterState = .fine, isResting: Bool = false,
        priority: Int = 0, createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> ChapterSummary {
        ChapterSummary(
            id: id, type: type, chapterKind: .dimension, title: title, iconRef: "heart.fill",
            state: state, awarenessPct: pct, isResting: isResting, personIds: [],
            priority: priority, createdAt: createdAt, lastTouchedAt: createdAt
        )
    }

    private func event(chapterId: UUID, date: Date, title: String = "The talk") -> EventSnapshot {
        EventSnapshot(
            id: UUID(), chapterId: chapterId, date: date, title: title, body: "",
            valence: .storm, isOpen: true, isHealed: false, healedReason: nil,
            isUpcoming: true, source: .onboarding, preparedAt: nil, checkInArmed: false
        )
    }

    // §6.3 — grade mapping boundaries + exact subline copy + token colors.
    @Test func gradeMappingBoundaries() {
        #expect(AwarenessGrade.grade(for: 0) == .tellMeMore)
        #expect(AwarenessGrade.grade(for: 54) == .tellMeMore)
        #expect(AwarenessGrade.grade(for: 55) == .gaining)
        #expect(AwarenessGrade.grade(for: 89) == .gaining)
        #expect(AwarenessGrade.grade(for: 90) == .fullyAware)
        #expect(AwarenessGrade.grade(for: 100) == .fullyAware)

        #expect(AwarenessGrade.fullyAware.subline(pct: 100) == "fully aware · 100%")
        #expect(AwarenessGrade.gaining.subline(pct: 71) == "needs a bit more · 71%")
        #expect(AwarenessGrade.tellMeMore.subline(pct: 29) == "tell me more · 29%")

        #expect(AwarenessGrade.fullyAware.ringColor(tokens) == tokens.mint)
        #expect(AwarenessGrade.gaining.ringColor(tokens) == tokens.gold)
        #expect(AwarenessGrade.tellMeMore.ringColor(tokens) == tokens.lilac)
    }

    // §2 — deterministic longitude: priority desc, createdAt asc; same input → same layout.
    @Test func longitudeAssignmentIsDeterministic() {
        let old = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let chapters = [
            chapter(title: "B", priority: 0, createdAt: newer),
            chapter(title: "A", priority: 5, createdAt: old),
            chapter(title: "C", priority: 0, createdAt: old),
        ]
        let pins = WorldModel.buildPins(
            chapters: chapters, upcoming: [], tokens: tokens, now: now, calendar: calendar
        )
        #expect(pins.map(\.title) == ["A", "C", "B"])
        #expect(pins[0].pin.lon == 0)
        #expect(abs(pins[1].pin.lon - 2 * .pi / 3) < 0.0001)
        let again = WorldModel.buildPins(
            chapters: chapters.shuffled(), upcoming: [], tokens: tokens, now: now, calendar: calendar
        )
        #expect(again.map(\.title) == pins.map(\.title))
        #expect(again.map(\.pin.lon) == pins.map(\.pin.lon))
    }

    // §6.4 — next-up: nearest future upcoming, chapter-priority tiebreak, hidden when none.
    @Test func nextUpSelection() {
        let near = chapter(title: "Near", priority: 1)
        let important = chapter(title: "Important", priority: 9)
        let chapters = [near, important]

        // Nearest date wins regardless of priority.
        var picked = WorldModel.selectNextUp(
            events: [
                event(chapterId: important.id, date: date(day: 30)),
                event(chapterId: near.id, date: date(day: 24), title: "Sooner"),
            ],
            chapters: chapters, now: now, calendar: calendar
        )
        #expect(picked?.eventTitle == "Sooner")
        #expect(picked?.relativeDay == "tomorrow")

        // Same date → higher chapter priority wins.
        picked = WorldModel.selectNextUp(
            events: [
                event(chapterId: near.id, date: date(day: 25), title: "Low"),
                event(chapterId: important.id, date: date(day: 25), title: "High"),
            ],
            chapters: chapters, now: now, calendar: calendar
        )
        #expect(picked?.eventTitle == "High")

        // No upcoming → nil (the card hides; no fake line).
        #expect(WorldModel.selectNextUp(events: [], chapters: chapters, now: now, calendar: calendar) == nil)
    }

    @Test func relativeDayDescriptors() {
        #expect(WorldModel.relativeDay(from: now, to: date(day: 23, hour: 12), calendar: calendar) == "today")
        #expect(WorldModel.relativeDay(from: now, to: date(day: 23, hour: 20), calendar: calendar) == "tonight")
        #expect(WorldModel.relativeDay(from: now, to: date(day: 24), calendar: calendar) == "tomorrow")
        #expect(WorldModel.relativeDay(from: now, to: date(day: 26), calendar: calendar) == "sunday")
        #expect(WorldModel.relativeDay(from: now, to: date(day: 31), calendar: calendar) == "Jul 31, 2026")
    }

    // §6.5 — never-tests (C3): resting chapters never pulse; the copy bank holds no guilt.
    @Test func restingChapterNeverPulses() {
        let resting = chapter(title: "Healed", isResting: true)
        let active = chapter(title: "Active")
        let pins = WorldModel.buildPins(
            chapters: [resting, active],
            upcoming: [
                event(chapterId: resting.id, date: date(day: 24)),
                event(chapterId: active.id, date: date(day: 24)),
            ],
            tokens: tokens, now: now, calendar: calendar
        )
        let restingPin = pins.first { $0.title == "Healed" }!
        let activePin = pins.first { $0.title == "Active" }!
        // Even WITH a live status line, resting pins never pulse — structural, not stylistic.
        #expect(restingPin.pin.statusLine != nil)
        #expect(!restingPin.shouldPulse)
        #expect(activePin.shouldPulse)
    }

    @Test func worldCopyBankHasNoGuiltStrings() {
        let forbidden = [
            "we miss you", "miss you", "come back", "don't forget", "you haven't",
            "overdue", "at risk", "last chance", "streak is about to",
        ]
        for line in WorldCopy.all {
            for phrase in forbidden {
                #expect(!line.lowercased().contains(phrase), "guilt copy in World bank: \(phrase)")
            }
        }
    }

    @Test func moodIsAPureFunctionOfWorldState() {
        let imminent = NextUpCard(
            eventId: UUID(), chapterId: UUID(), chapterTitle: "Us", eventTitle: "The talk",
            relativeDay: "tonight", prepArmed: false, checkInArmed: false
        )
        let later = NextUpCard(
            eventId: UUID(), chapterId: UUID(), chapterTitle: "Us", eventTitle: "Dinner",
            relativeDay: "sunday", prepArmed: false, checkInArmed: false
        )
        #expect(WorldModel.mood(nextUp: imminent) == (.alert, WorldCopy.greetingImminent))
        #expect(WorldModel.mood(nextUp: later) == (.cozy, WorldCopy.greetingUpcoming))
        #expect(WorldModel.mood(nextUp: nil) == (.sleepy, WorldCopy.greetingCalm))
    }

    // §6.6 — router resolution for the new route; unknown links refused loudly.
    @Test func routerResolvesNewChapterDeepLink() {
        let router = Router()
        #expect(router.open(deepLink: URL(string: "kept://newchapter")!))
        #expect(router.tab == .world)
        #expect(router.path == [.newChapter])
        #expect(!router.open(deepLink: URL(string: "kept://nope")!))
    }

    // §6.7 — live reactivity: a merge that raises awarenessPct re-grades the ring on refresh.
    @Test func awarenessRaiseRegradesTheRing() async throws {
        let store = try KeptStore(configuration: .inMemory)
        let chapterId = try store.createChapter(
            type: .health, chapterKind: .dimension, title: "Health", iconRef: "leaf.fill"
        )
        let model = WorldModel(store: store)
        model.refresh(tokens: tokens, now: now, calendar: calendar)
        #expect(model.loadState == .ready)
        #expect(model.pins.first?.grade == .tellMeMore)

        // Fill 3 of 5 slots (typed command; pct computed at write, C6) → 60% → gaining.
        try store.fillCensusSlots(chapterId: chapterId, slots: ["focusAreas", "routines", "goals"])
        model.refresh(tokens: tokens, now: now, calendar: calendar)
        #expect(model.pins.first?.grade == .gaining)
        #expect(model.pins.first?.pin.sublineText == "needs a bit more · 60%")
        #expect(model.pins.first?.pin.ringColor == tokens.gold)

        try store.fillCensusSlots(chapterId: chapterId, slots: ["currentState", "openIssues"])
        model.refresh(tokens: tokens, now: now, calendar: calendar)
        #expect(model.pins.first?.grade == .fullyAware)
    }
}
