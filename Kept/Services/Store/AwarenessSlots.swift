import Foundation

/// The awareness slot tables (extraction.md §4 — ruled with M1-CONTRACTS). The model reports
/// WHICH slots an utterance filled (`fillSlots`); every number is computed here at merge time and
/// stored on the chapter (C4/C6). Sensitive types keep internal slots — the §19 never-rule is
/// about display, enforced by the read models never carrying slot counts.
nonisolated enum AwarenessSchema {

    static func slots(for type: ChapterType) -> [String] {
        switch type {
        case .relationship:
            ["partnerName", "duration", "livingSituation", "originStory", "currentState", "positives", "openIssues"]
        case .family:
            ["keyPeople", "homeBase", "dynamics", "currentState", "positives", "openIssues"]
        case .friendship:
            ["keyPeople", "history", "currentState", "positives", "openIssues"]
        case .work:
            ["role", "place", "keyPeople", "ambitions", "currentState", "openIssues"]
        case .health:
            ["focusAreas", "routines", "currentState", "goals", "openIssues"]
        case .money:
            ["situation", "habits", "goals", "openIssues"]
        case .passion:
            ["what", "why", "cadence", "currentState"]
        case .growth:
            ["focus", "why", "practices", "progress", "blockers"]
        case .privateCorner:
            ["topic", "feelings", "needs"]
        case .grief:
            ["whoOrWhat", "relationship", "whereYouAre", "support"]
        }
    }

    static func isValid(slot: String, for type: ChapterType) -> Bool {
        slots(for: type).contains(slot)
    }

    /// `awarenessPct = round(100 × filled / total)` — computed at merge, stored, never re-derived
    /// in a view (C6). Unknown slot strings never reach here (validation rejects the envelope).
    static func awarenessPct(filledSlots: [String], type: ChapterType) -> Int {
        let table = slots(for: type)
        let filled = Set(filledSlots).intersection(table).count
        return Int((Double(filled) / Double(table.count) * 100).rounded())
    }
}
