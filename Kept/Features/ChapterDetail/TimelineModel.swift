import Foundation

// The timeline's typed node grammar (M4-CONTRACTS §7) — a PURE mapping over EventSnapshots,
// no model involvement (C3/C4). Only the open storm may pulse; folded overrides everything.
// Expansion of a folded pill is view-local @State — no store field exists, so every fresh
// render leads folded (structural refold, never-test).

nonisolated enum TimelineNode: Equatable, Identifiable {
    case folded(EventSnapshot)
    case openStorm(EventSnapshot)
    case calmReceipt(EventSnapshot)
    case upcoming(EventSnapshot, prepped: Bool)
    case bright(EventSnapshot)
    case receipt(EventSnapshot)
    case gentle(EventSnapshot)

    var event: EventSnapshot {
        switch self {
        case .folded(let event), .openStorm(let event), .calmReceipt(let event),
             .upcoming(let event, _), .bright(let event), .receipt(let event),
             .gentle(let event):
            event
        }
    }

    var id: UUID { event.id }

    /// The §19 grammar: the open storm is the ONLY node allowed a pulsing dot.
    var pulses: Bool {
        if case .openStorm = self { return true }
        return false
    }

    /// Row order is the contract (M4-CONTRACTS §7 table): folded overrides everything;
    /// storms split on isOpen; then upcoming; then valence.
    static func node(for event: EventSnapshot, now: Date, calendar: Calendar) -> TimelineNode {
        if event.isHealed { return .folded(event) }
        if event.valence == .storm { return event.isOpen ? .openStorm(event) : .calmReceipt(event) }
        if event.isUpcoming && event.date >= calendar.startOfDay(for: now) {
            return .upcoming(event, prepped: event.preparedAt != nil)
        }
        switch event.valence {
        case .bright, .gold: return .bright(event)
        case .neutral: return .receipt(event)
        case .soft: return .gentle(event)
        case .storm: return .calmReceipt(event) // unreachable; the storm branch above owns it
        }
    }

    static func nodes(for events: [EventSnapshot], now: Date, calendar: Calendar) -> [TimelineNode] {
        events.map { node(for: $0, now: now, calendar: calendar) }
    }
}
