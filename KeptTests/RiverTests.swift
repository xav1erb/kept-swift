import Foundation
import Testing
@testable import Kept

// M5-CONTRACTS §5/§6: the §9 hard grading rules as goldens, structural sensitive suppression,
// the size-class law (positives over-represented), and the deterministic S-curve layout.

@MainActor
struct RiverTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()
    /// 2026-07-25 12:00 UTC — a Saturday in July.
    private let now = Date(timeIntervalSince1970: 1_784_980_800)

    private func chapter(
        _ title: String, type: ChapterType, icon: String = "heart.fill", id: UUID = UUID()
    ) -> ChapterSummary {
        ChapterSummary(
            id: id, type: type, chapterKind: .dimension, title: title, iconRef: icon,
            state: .fine, awarenessPct: 50, isResting: false, personIds: [],
            priority: 0, createdAt: now, lastTouchedAt: now
        )
    }

    private func event(
        _ title: String, body: String = "", valence: Valence, isOpen: Bool = false,
        isHealed: Bool = false, isUpcoming: Bool = false, daysAgo: Double,
        chapterId: UUID
    ) -> EventSnapshot {
        EventSnapshot(
            id: UUID(), chapterId: chapterId, date: now.addingTimeInterval(-daysAgo * 86_400),
            title: title, body: body, valence: valence, isOpen: isOpen, isHealed: isHealed,
            healedReason: isHealed ? "forgiven" : nil, isUpcoming: isUpcoming, source: .chat,
            preparedAt: nil, checkInArmed: false
        )
    }

    // MARK: - §6.7 grading goldens (the §9 hard rules)

    @Test func gradingGoldensAndSizeClasses() throws {
        let daniel = chapter("Daniel", type: .relationship)
        func grade(_ event: EventSnapshot) -> RiverCard? {
            RiverCard.grade(event: event, chapter: daniel, now: now, calendar: calendar)
        }

        let bright = try #require(grade(event("Lisbon", body: "the best", valence: .gold, daysAgo: 30, chapterId: daniel.id)))
        let openStorm = try #require(grade(event("The credit thing", valence: .storm, isOpen: true, daysAgo: 2, chapterId: daniel.id)))
        let calmStorm = try #require(grade(event("The credit thing", valence: .storm, isOpen: false, daysAgo: 9, chapterId: daniel.id)))
        let folded = try #require(grade(event("The March bump", valence: .storm, isHealed: true, daysAgo: 100, chapterId: daniel.id)))
        let receipt = try #require(grade(event("The promise", valence: .neutral, daysAgo: 19, chapterId: daniel.id)))
        let gentle = try #require(grade(event("Quiet evening", valence: .soft, daysAgo: 5, chapterId: daniel.id)))

        // Positives over-represented is a size LAW: bright always large, negatives always small.
        #expect(bright.sizeClass == .large)
        #expect(openStorm.sizeClass == .standard)
        #expect(calmStorm.sizeClass == .small)
        #expect(folded.sizeClass == .pill)
        #expect(receipt.sizeClass == .standard)
        #expect(gentle.sizeClass == .standard)

        // Only the true open wound pulses (§9/§19).
        let all = [bright, openStorm, calmStorm, folded, receipt, gentle]
        #expect(all.filter(\.pulses).map(\.id) == [openStorm.id])

        // Healed overrides storm — the fold leads even on the river.
        if case .folded = folded.kind {} else { Issue.record("healed storm must grade folded") }
    }

    @Test func futurePinnedEventsStayOffTheRiver() {
        let daniel = chapter("Daniel", type: .relationship)
        let future = event("The talk", valence: .neutral, isUpcoming: true, daysAgo: -1, chapterId: daniel.id)
        #expect(RiverCard.grade(event: future, chapter: daniel, now: now, calendar: calendar) == nil)
        // ...but a PASSED pinned event flows normally (the river is history).
        let passed = event("The talk", valence: .neutral, isUpcoming: true, daysAgo: 1, chapterId: daniel.id)
        #expect(RiverCard.grade(event: passed, chapter: daniel, now: now, calendar: calendar) != nil)
    }

    // MARK: - §6.7 sensitive suppression is structural (§8.3 ruling)

    @Test func sensitiveChaptersAreStructurallySuppressed() throws {
        let grief = chapter("Losing Dad", type: .grief, icon: "moon.stars.fill")
        // Even a BRIGHT memory of a sensitive chapter stays sealed on the shared surface.
        for (valence, isOpen) in [(Valence.storm, true), (.bright, false), (.neutral, false)] {
            let sensitive = event(
                "The hospital call", body: "the hardest day", valence: valence,
                isOpen: isOpen, daysAgo: 40, chapterId: grief.id
            )
            let card = try #require(RiverCard.grade(event: sensitive, chapter: grief, now: now, calendar: calendar))
            #expect(card.kind == .sensitiveSilence)
            #expect(card.sizeClass == .small)
            #expect(!card.pulses)             // never storm-styled, never pulsing
            #expect(card.chapterTitle.isEmpty) // even the chapter's own name stays off
            // The card VALUE carries no leak — not the title, not the body, not the name.
            let rendered = String(describing: card)
            #expect(!rendered.contains("The hospital call"))
            #expect(!rendered.contains("the hardest day"))
            #expect(!rendered.contains("Losing Dad"))
        }
    }

    // MARK: - §6.8 layout determinism

    @Test func layoutIsDeterministicWithExactMarkers() throws {
        let daniel = chapter("Daniel", type: .relationship)
        // Newest-first, crafted to cross every bucket boundary.
        let events = [
            event("Today thing", valence: .soft, daysAgo: 0, chapterId: daniel.id),
            event("Mid-July", valence: .gold, daysAgo: 15, chapterId: daniel.id),      // 2026-07-10
            event("June receipt", valence: .neutral, daysAgo: 50, chapterId: daniel.id), // 2026-06-05
            event("Last year", valence: .soft, daysAgo: 300, chapterId: daniel.id),      // 2025-09-28
            event("Old gold", valence: .gold, daysAgo: 700, chapterId: daniel.id),       // 2024-08-25
        ]
        let cards = events.compactMap {
            RiverCard.grade(event: $0, chapter: daniel, now: now, calendar: calendar)
        }
        #expect(cards.count == 5)

        let layout = RiverLayout.layout(cards: cards, now: now, calendar: calendar)
        let again = RiverLayout.layout(cards: cards, now: now, calendar: calendar)
        #expect(layout == again)

        #expect(layout.markers.map(\.label) == [
            RiverCopy.markerToday, "EARLIER IN JULY", "JUNE", RiverCopy.markerLastYear, "2024",
        ])
        // Banks alternate; the stream never overlaps itself.
        #expect(layout.slots.map(\.bank) == [.left, .right, .left, .right, .left])
        for (current, next) in zip(layout.slots, layout.slots.dropFirst()) {
            #expect(next.y >= current.y + current.height)
        }
        #expect(layout.totalHeight > layout.slots.last!.y + layout.slots.last!.height)
    }

    // MARK: - filters (store-backed, deterministic)

    @Test func chapterFilterIsAPureRefilter() async throws {
        let store = try KeptStore(configuration: .inMemory)
        try store.setUserName("Maya")
        try store.grantAIConsent()
        try store.completeOnboarding()
        let danielId = try store.createChapter(type: .relationship, chapterKind: .dimension, title: "Daniel", iconRef: "heart.fill")
        let workId = try store.createChapter(type: .work, chapterKind: .dimension, title: "Work", iconRef: "briefcase.fill")
        _ = try store.addEvent(chapterId: danielId, date: now.addingTimeInterval(-86_400), title: "Dinner", body: "", valence: .bright, isOpen: false, isUpcoming: false, source: .chat)
        _ = try store.addEvent(chapterId: workId, date: now.addingTimeInterval(-2 * 86_400), title: "Review", body: "", valence: .neutral, isOpen: false, isUpcoming: false, source: .chat)

        let model = RiverModel(store: store)
        model.refresh(now: now, calendar: calendar)
        #expect(model.state == .ready)
        #expect(model.cards.count == 2)
        #expect(model.chapterFilters.map(\.title) == ["Daniel", "Work"])

        model.selectedChapterId = workId
        #expect(model.cards.count == 1)
        #expect(model.cards.first?.chapterId == workId)

        model.selectedChapterId = nil
        #expect(model.cards.count == 2)
    }

    // MARK: - §6.9 the copy bank holds no guilt

    @Test func riverCopyBankHasNoGuiltStrings() {
        let forbidden = [
            "we miss you", "miss you", "come back", "don't forget", "you haven't",
            "overdue", "at risk", "last chance", "streak is about to",
        ]
        for line in RiverCopy.all {
            for phrase in forbidden {
                #expect(!line.lowercased().contains(phrase), "guilt copy in river bank: \(phrase)")
            }
        }
    }
}
