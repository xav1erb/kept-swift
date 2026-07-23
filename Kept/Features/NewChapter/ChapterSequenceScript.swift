import Foundation

// Per-type chapter-creation sequences (M3-CONTRACTS §5, §8 ruling 1): the SAME InterviewEngine
// walks these — no second runner, no second write path (C1). One warm question per awareness
// slot (AwarenessSchema is the source of truth: the whitepaper §6 question counts ARE the slot
// counts), every answer → the utterance queue → the M1 pipeline fills the slots. Already-filled
// slots are never re-asked (the provider's filledSlots gate).
//
// ⚠ All question copy below is agent-drafted from the slot tables — flagged for Xavier's copy
// review; structural rules (skippable, no counts for sensitive types) are test-enforced.

/// Grid/display metadata per chapter type. Display concern — lives with the feature, not the
/// store. `defaultIconRef` is what `createChapter` stores; the pin renders it.
nonisolated extension ChapterType {

    var displayName: String {
        switch self {
        case .relationship: "Relationship"
        case .family: "Family"
        case .friendship: "Friendship"
        case .work: "Work"
        case .health: "Health"
        case .money: "Money"
        case .passion: "Passion"
        case .growth: "Growth"
        case .privateCorner: "Private corner"
        case .grief: "Grief"
        }
    }

    var gridSymbol: String {
        switch self {
        case .relationship: "heart.fill"
        case .family: "house.fill"
        case .friendship: "person.2.fill"
        case .work: "briefcase.fill"
        case .health: "leaf.fill"
        case .money: "banknote"
        case .passion: "paintpalette.fill"
        case .growth: "sparkles"
        case .privateCorner: "lock.fill"
        case .grief: "moon.stars.fill"
        }
    }

    /// ⚠ agent copy — one-liners for the grid cards.
    var oneLiner: String {
        switch self {
        case .relationship: "The two of you — as it really is."
        case .family: "The people you come from."
        case .friendship: "Your chosen people."
        case .work: "What your days are made of."
        case .health: "Body and mind, looked after."
        case .money: "The honest picture, no judgment."
        case .passion: "The thing you love doing."
        case .growth: "Who you're becoming."
        case .privateCorner: "Only yours."
        case .grief: "For what you carry."
        }
    }
}

nonisolated struct ChapterSequenceScript: InterviewScriptProviding {

    let type: ChapterType
    let chapterId: UUID

    /// Scripted census answers — the proxy's onboarding prompt shape (fx-002); reusing the
    /// surface keeps the wire vocabulary untouched (a seam).
    var utteranceSurface: Surface { .onboarding }
    var slotSource: InterviewSlotSource { .chapter(chapterId) }

    func firstNode(answers: [String: String]) -> InterviewNode? {
        nextNode(answers: answers, filledSlots: [])
    }

    func nextNode(answers: [String: String], filledSlots: [String]) -> InterviewNode? {
        Self.nodes(for: type).first { node in
            answers[node.id] == nil && !filledSlots.contains(Self.slot(ofNodeId: node.id))
        }
    }

    func node(for id: String) -> InterviewNode? {
        Self.nodes(for: type).first { $0.id == id }
    }

    func progress(answers: [String: String]) -> Double {
        let nodes = Self.nodes(for: type)
        guard !nodes.isEmpty else { return 1 }
        return min(1.0, Double(nodes.filter { answers[$0.id] != nil }.count) / Double(nodes.count))
    }

    // MARK: - Node construction (one per awareness slot, order = the schema's order)

    static func nodeId(type: ChapterType, slot: String) -> String { "seq-\(type.rawValue)-\(slot)" }

    /// Node ids carry the slot as the final dash component (slots are single camelCase tokens).
    static func slot(ofNodeId id: String) -> String {
        id.components(separatedBy: "-").last ?? id
    }

    static func nodes(for type: ChapterType) -> [InterviewNode] {
        let slots = AwarenessSchema.slots(for: type)
        let questions = Self.questions(for: type)
        return slots.enumerated().compactMap { index, slot in
            guard let prompt = questions[slot] else { return nil }
            let isLast = index == slots.count - 1
            return InterviewNode(
                id: nodeId(type: type, slot: slot),
                prompts: [prompt],
                input: .freeText(placeholder: "tell me"),
                write: .utterance,
                // One quiet ack at the end; sensitive types close even more gently. ⚠ agent copy.
                acknowledgment: isLast ? (type.isSensitive ? "Kept. Gently." : "Kept. This room is yours now.") : nil,
                skippable: true
            )
        }
    }

    /// ⚠ agent copy — slot → question, per type. Total over each type's schema (a missing slot
    /// would silently shrink the sequence; the acceptance test asserts coverage).
    static func questions(for type: ChapterType) -> [String: String] {
        switch type {
        case .relationship: [
            "partnerName": "Who is this chapter about — what's their name?",
            "duration": "How long have you two been together?",
            "livingSituation": "Do you two live together, or how does that work right now?",
            "originStory": "How did you two meet? I love an origin story.",
            "currentState": "How are things between you right now, honestly?",
            "positives": "When it's good between you, what's it like?",
            "openIssues": "Is there anything between you that feels unfinished?",
        ]
        case .family: [
            "keyPeople": "Who's in the family picture — the people that matter day to day?",
            "homeBase": "Where's home base for the family?",
            "dynamics": "How does the family actually work — who's close to whom?",
            "currentState": "How are things in the family right now?",
            "positives": "What's the good part of this family?",
            "openIssues": "Anything in the family that feels heavy right now?",
        ]
        case .friendship: [
            "keyPeople": "Who are your people — the friends that actually count?",
            "history": "How far back do you go with them?",
            "currentState": "How is it between you all lately?",
            "positives": "What do they give you, these people?",
            "openIssues": "Any friendship that feels off right now?",
        ]
        case .work: [
            "role": "What's your role, officially or actually?",
            "place": "Where's this all happening — company, school, your own thing?",
            "keyPeople": "Who matters there — allies, bosses, the difficult one?",
            "ambitions": "Where do you want this to go?",
            "currentState": "How's work feeling right now?",
            "openIssues": "What's the hardest part at the moment?",
        ]
        case .health: [
            "focusAreas": "What are you paying attention to, health-wise?",
            "routines": "Any routines you're keeping — or trying to?",
            "currentState": "How's your body treating you lately?",
            "goals": "What would better look like?",
            "openIssues": "What gets in the way?",
        ]
        case .money: [
            "situation": "How do things stand with money right now, roughly?",
            "habits": "What are your money habits — the good and the honest?",
            "goals": "What are you working toward?",
            "openIssues": "What's the stressful part?",
        ]
        case .passion: [
            "what": "What's the thing you do just because you love it?",
            "why": "What does it give you?",
            "cadence": "How often do you actually get to it?",
            "currentState": "How's it going with it lately?",
        ]
        case .growth: [
            "focus": "What are you working on in yourself right now?",
            "why": "Why this, why now?",
            "practices": "What are you actually doing about it?",
            "progress": "Where are you on that road, would you say?",
            "blockers": "What keeps getting in the way?",
        ]
        case .privateCorner: [
            "topic": "This corner is only yours. What's it about?",
            "feelings": "How does it sit with you right now?",
            "needs": "What do you need here — even if it's just a place to put it?",
        ]
        case .grief: [
            "whoOrWhat": "Who or what is this room for?",
            "relationship": "What were they to you?",
            "whereYouAre": "Where are you with it, today?",
            "support": "Who or what helps, when anything does?",
        ]
        }
    }
}
