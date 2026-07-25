import Foundation
import Observation

// The River (M5-CONTRACTS §5) — the master timeline under the §9 HARD grading rules. The card
// grammar and the S-curve layout are pure functions (LOOP-safe, golden-tested); the view only
// draws. Sensitive chapters are structurally suppressed (§8.3 ruling): their card kind carries
// no title, no body, no chapter name — the type cannot leak what it does not hold.

/// The River copy bank (C3: guilt-scanned; ⚠ agent-drafted, flagged for review).
nonisolated enum RiverCopy {
    static let sensitiveSilence = "It went quiet — a hard talk. The door stays open, no rush."
    static let onRecordCalmly = "Kept, calmly."
    static let endCap = "where your river begins"
    static let everythingChip = "✨ Everything"
    static let emptyRiver = "The river starts with whatever you tell me — it all flows here."
    static let markerToday = "TODAY"
    static let markerEarlierPrefix = "EARLIER IN"
    static let markerLastYear = "LAST YEAR"

    static var all: [String] {
        [sensitiveSilence, onRecordCalmly, endCap, everythingChip, emptyRiver,
         markerToday, markerEarlierPrefix, markerLastYear]
    }
}

/// One card on the river. §9 grading is the constructor; §19 lives in the types: only
/// `openStorm` may pulse, and `sensitiveSilence` has no content fields to show.
nonisolated struct RiverCard: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case bright(EventSnapshot)            // LARGE — positives over-represented is a size law
        case gentle(EventSnapshot)
        case receipt(EventSnapshot)
        case calmReceipt(EventSnapshot)       // factual negative: SMALL, calm, never storm-dressed
        case openStorm(EventSnapshot)         // the ONLY pulsing card
        case folded(EventSnapshot)            // the 🌱 pill (M4 behavior — structural refold)
        case sensitiveSilence                 // fixed copy; NO title/body/chapter-title BY TYPE
    }

    enum SizeClass: Equatable, Sendable { case large, standard, small, pill }

    let id: UUID
    let kind: Kind
    let date: Date
    let chapterId: UUID
    /// Empty for sensitive cards — the badge shows an icon only (§8.3: even the chapter's own
    /// title stays off the shared surface).
    let chapterTitle: String
    let chapterIcon: String

    var sizeClass: SizeClass {
        switch kind {
        case .bright: .large
        case .gentle, .receipt: .standard
        case .calmReceipt, .sensitiveSilence: .small
        case .openStorm: .standard
        case .folded: .pill
        }
    }

    var pulses: Bool {
        if case .openStorm = kind { return true }
        return false
    }

    /// The §9 grading rules as the single constructor. Future-dated pinned events stay off the
    /// river (it flows backward from today); the chapter's own timeline shows them.
    static func grade(
        event: EventSnapshot,
        chapter: ChapterSummary,
        now: Date,
        calendar: Calendar
    ) -> RiverCard? {
        if event.isUpcoming && event.date >= calendar.startOfDay(for: now) { return nil }
        if chapter.type.isSensitive {
            return RiverCard(
                id: event.id, kind: .sensitiveSilence, date: event.date,
                chapterId: chapter.id, chapterTitle: "", chapterIcon: chapter.iconRef
            )
        }
        let kind: Kind = if event.isHealed {
            .folded(event)
        } else if event.valence == .storm {
            event.isOpen ? .openStorm(event) : .calmReceipt(event)
        } else {
            switch event.valence {
            case .bright, .gold: .bright(event)
            case .soft: .gentle(event)
            case .neutral, .storm: .receipt(event)
            }
        }
        return RiverCard(
            id: event.id, kind: kind, date: event.date,
            chapterId: chapter.id, chapterTitle: chapter.title, chapterIcon: chapter.iconRef
        )
    }
}

/// The deterministic S-curve layout: banks alternate, heights are fixed per size class, time
/// markers land at calendar bucket boundaries. Same input → same layout, always (LOOP.md).
nonisolated struct RiverLayout: Equatable, Sendable {
    enum Bank: Equatable, Sendable { case left, right }

    struct Slot: Equatable, Identifiable, Sendable {
        let cardId: UUID
        let bank: Bank
        let y: CGFloat
        let height: CGFloat
        var id: UUID { cardId }
    }

    struct Marker: Equatable, Identifiable, Sendable {
        let label: String
        let y: CGFloat
        var id: String { "\(label)-\(y)" }
    }

    struct Config: Equatable, Sendable {
        var topInset: CGFloat = 70          // Pom floats at Today above the first card
        var spacing: CGFloat = 18
        var markerHeight: CGFloat = 34
        var heights: [RiverCard.SizeClass: CGFloat] = [
            .large: 118, .standard: 88, .small: 60, .pill: 46,
        ]
        var amplitude: CGFloat = 34         // the S-curve swing
        var period: CGFloat = 560           // one full bend
        var endCapHeight: CGFloat = 120

        init() {}
    }

    let slots: [Slot]
    let markers: [Marker]
    let totalHeight: CGFloat

    static func layout(
        cards: [RiverCard],
        now: Date,
        calendar: Calendar,
        config: Config = Config()
    ) -> RiverLayout {
        var slots: [Slot] = []
        var markers: [Marker] = []
        var y = config.topInset
        var lastBucket: String?

        for (index, card) in cards.enumerated() {
            let bucket = bucketLabel(for: card.date, now: now, calendar: calendar)
            if bucket != lastBucket {
                markers.append(Marker(label: bucket, y: y))
                y += config.markerHeight + config.spacing
                lastBucket = bucket
            }
            let height = config.heights[card.sizeClass] ?? 88
            slots.append(Slot(
                cardId: card.id,
                bank: index.isMultiple(of: 2) ? .left : .right,
                y: y,
                height: height
            ))
            y += height + config.spacing
        }
        return RiverLayout(slots: slots, markers: markers, totalHeight: y + config.endCapHeight)
    }

    /// TODAY · EARLIER IN {MONTH} · {MONTH} · LAST YEAR · {YEAR}. Deterministic, calendar-fed.
    static func bucketLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return RiverCopy.markerToday }
        let nowYear = calendar.component(.year, from: now)
        let dateYear = calendar.component(.year, from: date)
        let locale = calendar.locale ?? .current
        let monthName = date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar).month(.wide)
        ).uppercased()
        if dateYear == nowYear {
            if calendar.isDate(date, equalTo: now, toGranularity: .month) {
                return "\(RiverCopy.markerEarlierPrefix) \(monthName)"
            }
            return monthName
        }
        if dateYear == nowYear - 1 { return RiverCopy.markerLastYear }
        return String(dateYear)
    }

    /// The curve's x-offset at a given y — the view draws the path and offsets cards with it.
    static func curveOffset(y: CGFloat, config: Config = Config()) -> CGFloat {
        config.amplitude * sin((2 * .pi * y) / config.period)
    }
}

@Observable
@MainActor
final class RiverModel {

    enum LoadState: Equatable { case loading, ready, failed }

    private let store: KeptStore

    private(set) var state: LoadState = .loading
    private(set) var cards: [RiverCard] = []
    private(set) var layout = RiverLayout(slots: [], markers: [], totalHeight: 0)
    private(set) var chapterFilters: [(id: UUID, title: String, iconRef: String)] = []
    var selectedChapterId: UUID? {
        didSet { rebuild() }
    }

    private var allCards: [RiverCard] = []
    private var now: Date = .now
    private var calendar: Calendar = .current

    init(store: KeptStore) {
        self.store = store
    }

    func refresh(now: Date = .now, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        do {
            let chapters = try store.chapterSummaries()
            let byId = Dictionary(uniqueKeysWithValues: chapters.map { ($0.id, $0) })
            allCards = try store.riverEvents().compactMap { event in
                guard let chapterId = event.chapterId, let chapter = byId[chapterId] else { return nil }
                return RiverCard.grade(event: event, chapter: chapter, now: now, calendar: calendar)
            }
            chapterFilters = chapters.map { ($0.id, $0.title, $0.iconRef) }
            state = .ready
            rebuild()
        } catch {
            state = .failed
        }
    }

    private func rebuild() {
        cards = allCards.filter { selectedChapterId == nil || $0.chapterId == selectedChapterId }
        layout = RiverLayout.layout(cards: cards, now: now, calendar: calendar)
    }
}
