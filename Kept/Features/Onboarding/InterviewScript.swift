import Foundation

// The interview script (M2-CONTRACTS §3): FIXED questions verbatim from docs/onboarding.md §6 —
// the copy source of truth — as a typed data structure, never prompt-engineered. Acknowledgments
// are fixed script lines in v1 (§8.1 ruling: no AI call before sign-in; /acknowledge deferred).
// Free-text answers queue for extraction at sign-in; chips/fields write via typed commands.
//
// Copy NOT in docs/onboarding.md (deep-dive + census-block questions, marked ⚠) is agent-drafted
// from the awareness slot tables — flagged for Xavier's copy review, structural rules unaffected.

nonisolated struct DraftBubble: Codable, Equatable, Identifiable, Sendable {
    enum Author: String, Codable, Sendable { case pom, user }
    let id: UUID
    let author: Author
    let text: String

    init(id: UUID = UUID(), author: Author, text: String) {
        self.id = id
        self.author = author
        self.text = text
    }
}

nonisolated struct InterviewChip: Equatable, Identifiable, Sendable {
    let id: String
    let label: String
}

nonisolated enum InterviewInput: Equatable, Sendable {
    case chips([InterviewChip])
    case field(placeholder: String, keyboard: FieldKeyboard)
    case freeText(placeholder: String)

    enum FieldKeyboard: Equatable, Sendable { case text, number }
}

nonisolated enum InterviewWrite: Equatable, Sendable {
    case none
    case userName
    case onboardingMode
    case age
    case city
    case occupationKind
    case occupationDetail
    case relationshipStatus
    case partnerName
    case relationshipDuration
    case relationshipState
    /// Queue for extraction at sign-in (§8.1). The engine enqueues with this node's id.
    case utterance
    case notificationChoice
}

nonisolated struct InterviewNode: Equatable, Identifiable, Sendable {
    let id: String
    /// Pom bubbles, in order, shown with typing cadence. `{name}` is substituted.
    let prompts: [String]
    let input: InterviewInput
    let write: InterviewWrite
    /// Fixed acknowledgment bubble after the answer (nil = advance silently). v1 rule (§8.1):
    /// always fixed, never AI.
    let acknowledgment: String?
    let skippable: Bool
}

nonisolated enum InterviewScript {

    static let focusModeChip = InterviewChip(id: "focus", label: "⚡ Focus on the most important chapter now")
    static let fullModeChip = InterviewChip(id: "full", label: "🗺 Fill me in on everything now")
    static let leaveItChip = InterviewChip(id: "later", label: "Leave it for later")

    // MARK: - Fixed nodes (verbatim where docs/onboarding.md §6 provides copy)

    static let q1Name = InterviewNode(
        id: "q1-name",
        prompts: ["What would you like me to call you from now on?"],
        input: .field(placeholder: "your name (or a name you like)", keyboard: .text),
        write: .userName,
        acknowledgment: "Good name for a main character :)",
        skippable: true
    )

    static let q2Fork = InterviewNode(
        id: "q2-fork",
        prompts: ["We can do this in 2 ways:"],
        input: .chips([focusModeChip, fullModeChip]),
        write: .onboardingMode,
        acknowledgment: nil,
        skippable: false
    )

    static let q3Age = InterviewNode(
        id: "q3-age",
        prompts: ["First, the quick basics. How old are you?"],  // ⚠ agent copy (spec: "Age →")
        input: .field(placeholder: "age", keyboard: .number),
        write: .age,
        acknowledgment: nil,
        skippable: true
    )

    static let q3City = InterviewNode(
        id: "q3-city",
        prompts: ["Where in the world is your world?"],
        input: .field(placeholder: "city", keyboard: .text),
        write: .city,
        acknowledgment: nil,
        skippable: true
    )

    static let q3OccupationKind = InterviewNode(
        id: "q3-occupation-kind",
        prompts: ["What do you do: work, school, both, in between?"],
        input: .chips([
            InterviewChip(id: "work", label: "Work"),
            InterviewChip(id: "school", label: "School"),
            InterviewChip(id: "both", label: "Both"),
            InterviewChip(id: "between", label: "In between"),
            InterviewChip(id: "none", label: "Living my best life (none)"),
        ]),
        write: .occupationKind,
        acknowledgment: nil,
        skippable: true
    )

    static let q3OccupationDetail = InterviewNode(
        id: "q3-occupation-detail",
        prompts: ["And what is it you do, exactly?"],  // ⚠ agent copy (spec: "follow-up on occupation")
        input: .field(placeholder: "what you do", keyboard: .text),
        write: .occupationDetail,
        acknowledgment: nil,
        skippable: true
    )

    static let q4Status = InterviewNode(
        id: "q4-status",
        prompts: ["Are you in a relationship?"],
        input: .chips([
            InterviewChip(id: "yes", label: "Yes"),
            InterviewChip(id: "no", label: "No"),
            InterviewChip(id: "married", label: "I'm married"),
            InterviewChip(id: "complicated", label: "It's complicated rn"),
        ]),
        write: .relationshipStatus,
        acknowledgment: nil,
        skippable: true
    )

    static let q4PartnerName = InterviewNode(
        id: "q4-partner-name",
        prompts: ["What's their name?"],  // ⚠ agent copy (spec: "→ partner name")
        input: .field(placeholder: "their name", keyboard: .text),
        write: .partnerName,
        acknowledgment: nil,
        skippable: true
    )

    static let q4Duration = InterviewNode(
        id: "q4-duration",
        prompts: ["How long have you two been together?"],  // ⚠ agent copy (spec: "→ duration")
        input: .field(placeholder: "how long", keyboard: .text),
        write: .relationshipDuration,
        acknowledgment: nil,
        skippable: true
    )

    static let q4State = InterviewNode(
        id: "q4-state",
        prompts: ["How are things between you and {partner} right now, today, in one word?"],
        input: .chips(RelationshipStateChip.allCases.map { InterviewChip(id: $0.rawValue, label: $0.rawValue) }),
        write: .relationshipState,
        acknowledgment: nil,
        skippable: true
    )

    static let q4Followup = InterviewNode(
        id: "q4-followup",
        prompts: ["what's confusing about it — one or two sentences — or leave it for later."],
        input: .freeText(placeholder: "one or two sentences"),
        write: .utterance,
        acknowledgment: "Kept. All of it — safe with me.",  // ⚠ agent copy (fixed ack, §8.1)
        skippable: true
    )

    static let q6Positive = InterviewNode(
        id: "q6-positive",
        prompts: ["One more: when it's good between you two, what's it like?"],
        input: .freeText(placeholder: "what it's like"),
        write: .utterance,
        acknowledgment: "That's the part worth protecting. Noted 🤍",  // ⚠ agent copy (fixed ack)
        skippable: false  // script never skips Q6 (spec); the user may still answer minimally
    )

    static let q8Notifications = InterviewNode(
        id: "q8-notifications",
        prompts: [
            "One thing — my whole point is that I follow up. 'How did the talk go?' For that, I need to be able to reach you."
        ],
        input: .chips([
            InterviewChip(id: "yes", label: "Yes"),
            InterviewChip(id: "no", label: "No"),
        ]),
        write: .notificationChoice,
        acknowledgment: nil,
        skippable: true
    )

    static let q9Close = InterviewNode(
        id: "q9-close",
        prompts: ["Perfect {name}, I hope you're ready to see your world :)"],
        input: .chips([InterviewChip(id: "ready", label: "I'm ready ✨")]),
        write: .none,
        acknowledgment: nil,
        skippable: false
    )

    // MARK: - Deep-dive (focus mode Q7) — one warm question per unfilled slot, derived from the
    // awareness slot tables (AwarenessSlots.swift). ⚠ agent copy throughout; sensitive types are
    // NEVER deep-dive targets in onboarding (they are user-opened only, C3).

    static func deepDiveQuestions(for type: ChapterType) -> [(slot: String, prompt: String)] {
        switch type {
        case .relationship: [
            ("livingSituation", "Do you two live together, or how does that work right now?"),
            ("originStory", "How did you two meet? I love an origin story."),
            ("openIssues", "Is there anything between you two that feels unfinished right now?"),
        ]
        case .family: [
            ("keyPeople", "Who's in the family picture — the people that matter day to day?"),
            ("homeBase", "Where's home base for the family?"),
            ("dynamics", "How does the family actually work — who's close to whom?"),
            ("openIssues", "Anything in the family that feels heavy right now?"),
        ]
        case .friendship: [
            ("keyPeople", "Who are your people — the friends that actually count?"),
            ("history", "How far back do you go with them?"),
            ("openIssues", "Any friendship that feels off lately?"),
        ]
        case .work: [
            ("role", "What's your role, officially or actually?"),
            ("place", "Where's this all happening — company, school, your own thing?"),
            ("keyPeople", "Who matters there — allies, bosses, the difficult one?"),
            ("ambitions", "Where do you want this to go?"),
            ("openIssues", "What's the hardest part right now?"),
        ]
        case .health: [
            ("focusAreas", "What are you paying attention to, health-wise?"),
            ("routines", "Any routines you're keeping — or trying to?"),
            ("goals", "What would better look like?"),
            ("openIssues", "What gets in the way?"),
        ]
        case .money: [
            ("situation", "How do things stand with money right now, roughly?"),
            ("habits", "What are your money habits — the good and the honest?"),
            ("goals", "What are you working toward?"),
            ("openIssues", "What's the stressful part?"),
        ]
        case .passion: [
            ("what", "What's the thing you do just because you love it?"),
            ("why", "What does it give you?"),
            ("cadence", "How often do you actually get to it?"),
        ]
        case .growth: [
            ("focus", "What are you working on in yourself right now?"),
            ("why", "Why this, why now?"),
            ("practices", "What are you actually doing about it?"),
            ("blockers", "What keeps getting in the way?"),
        ]
        case .privateCorner, .grief: []
        }
    }

    static func deepDiveNode(slot: String, prompt: String) -> InterviewNode {
        InterviewNode(
            id: "q7-deepdive-\(slot)",
            prompts: [prompt],
            input: .freeText(placeholder: "tell me"),
            write: .utterance,
            acknowledgment: "Got it — building this room properly.",  // ⚠ agent copy (fixed ack)
            skippable: true
        )
    }

    // MARK: - Full-fork census blocks (Q7 full mode, survey depth) — ⚠ agent copy from the slot
    // tables; free text → extraction at flush (fx-002's shape).

    static let fullCensusNodes: [InterviewNode] = [
        InterviewNode(
            id: "q7-family",
            prompts: ["Now the wider picture. Family — who matters, and how is it between you all?"],
            input: .freeText(placeholder: "the family picture"),
            write: .utterance,
            acknowledgment: "Filed under family — safe.",
            skippable: true
        ),
        InterviewNode(
            id: "q7-work",
            prompts: ["Work or school — what do your days actually look like, and how's it going?"],
            input: .freeText(placeholder: "the work picture"),
            write: .utterance,
            acknowledgment: "Noted. Your world is filling in.",
            skippable: true
        ),
        InterviewNode(
            id: "q7-health",
            prompts: ["Health — anything you're working on or watching?"],
            input: .freeText(placeholder: "the health picture"),
            write: .utterance,
            acknowledgment: "Kept.",
            skippable: true
        ),
        InterviewNode(
            id: "q7-money",
            prompts: ["And money — how do things stand, and is there something you're saving toward?"],
            input: .freeText(placeholder: "the money picture"),
            write: .utterance,
            acknowledgment: "Good to know. Almost there.",
            skippable: true
        ),
    ]
}
