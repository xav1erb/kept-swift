import Foundation
import SwiftData

// Structured census writes (M1-CONTRACTS §8 amendment: a chip tap is not an utterance — C1
// governs utterances). Deterministic typed code computes everything here (C4): chapter, person,
// slots, awareness. Free-text answers NEVER come through this path.

extension KeptStore {

    /// The Q4 relationship block materialized: chapter + partner person + census slots + state.
    /// Idempotent-ish for onboarding: reuses an existing relationship chapter if one exists.
    @discardableResult
    func applyRelationshipCensus(
        partnerName: String?,
        duration: String?,
        stateChip: RelationshipStateChip
    ) throws -> UUID {
        let chapterId: UUID
        if let existing = try chapterSummaries().first(where: { $0.type == .relationship }) {
            chapterId = existing.id
        } else {
            chapterId = try createChapter(
                type: .relationship, chapterKind: .dimension,
                title: "Us", iconRef: "heart"
            )
        }
        var slots: [String] = ["currentState"]
        if let partnerName, !partnerName.isEmpty {
            let personId = try addPerson(name: partnerName, relation: "partner")
            try attach(personId: personId, toChapter: chapterId)
            slots.append("partnerName")
        }
        if let duration, !duration.isEmpty {
            slots.append("duration")
        }
        try fillCensusSlots(chapterId: chapterId, slots: slots)
        try setChapterState(chapterId, state: stateChip.chapterState)
        return chapterId
    }

    /// Census slot fill with the same validation + recompute the merge uses (C6: computed at
    /// write). Invalid slots throw — a script bug fails loudly, never a wrong percentage.
    func fillCensusSlots(chapterId: UUID, slots: [String]) throws {
        let chapter = try fetchChapterModel(chapterId)
        for slot in slots {
            guard AwarenessSchema.isValid(slot: slot, for: chapter.type) else {
                throw MergeError.invalidSlot(slot: slot, chapterType: chapter.type)
            }
            if !chapter.filledSlots.contains(slot) {
                chapter.filledSlots.append(slot)
            }
        }
        chapter.awarenessPct = AwarenessSchema.awarenessPct(
            filledSlots: chapter.filledSlots, type: chapter.type
        )
        chapter.lastTouchedAt = .now
        noteBlobDirty(.chapter, chapter.id)
        try modelContext.save()
    }
}

/// The Q4 one-word chips (docs/onboarding.md §6 Q4, verbatim) mapped to the soft state
/// vocabulary — a typed table, never model-estimated (C4).
nonisolated enum RelationshipStateChip: String, CaseIterable, Sendable {
    case good = "Good"
    case fine = "Fine"
    case tense = "Tense"
    case confusing = "Confusing"
    case fragile = "Fragile"

    var chapterState: ChapterState {
        switch self {
        case .good: .warm
        case .fine: .fine
        case .tense: .tense
        case .confusing: .complicated
        case .fragile: .tense
        }
    }

    /// The one optional open follow-up fires only on a negative word (Q4: "Never more than
    /// one push").
    var isNegative: Bool {
        switch self {
        case .good, .fine: false
        case .tense, .confusing, .fragile: true
        }
    }
}
