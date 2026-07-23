import Foundation

// The script-provider seam (M3-CONTRACTS §8 A2): `InterviewEngine` is the ONE scripted-chat
// runner (C1) — the onboarding interview and every new-chapter sequence are just different
// scripts walked by the same engine, writing through the same paths (typed commands for
// chips/fields, the utterance queue for free text). Providers are pure over the answers map so
// resume stays exact.

/// Which chapter's already-filled awareness slots feed branching — a filled slot is never
/// re-asked (the census/extraction got there first).
nonisolated enum InterviewSlotSource: Equatable, Sendable {
    case none
    /// Onboarding: the census-created relationship chapter, if any.
    case relationshipCensus
    /// A specific chapter (new-chapter sequences).
    case chapter(UUID)
}

nonisolated protocol InterviewScriptProviding: Sendable {
    /// Where this script's free-text answers queue (C1 — the only write path for utterances).
    var utteranceSurface: Surface { get }
    var slotSource: InterviewSlotSource { get }
    func firstNode(answers: [String: String]) -> InterviewNode?
    /// Pure branching over the answers map (+ filled slots) — resume-safe by construction.
    func nextNode(answers: [String: String], filledSlots: [String]) -> InterviewNode?
    func node(for id: String) -> InterviewNode?
    func progress(answers: [String: String]) -> Double
}

/// The M2 onboarding interview as a provider — logic moved verbatim from the engine at the A2
/// refactor; the M2 acceptance tests pin that nothing changed.
nonisolated struct OnboardingScript: InterviewScriptProviding {

    var utteranceSurface: Surface { .onboarding }
    var slotSource: InterviewSlotSource { .relationshipCensus }

    func firstNode(answers: [String: String]) -> InterviewNode? {
        answers.isEmpty ? InterviewScript.q1Name : nextNode(answers: answers, filledSlots: [])
    }

    func nextNode(answers: [String: String], filledSlots: [String]) -> InterviewNode? {
        let mode: OnboardingMode = answers[InterviewScript.q2Fork.id] == InterviewScript.fullModeChip.id ? .full : .focus
        let statusChip = answers[InterviewScript.q4Status.id]
        let hasRelationship = ["yes", "married", "complicated"].contains(statusChip ?? "")

        if answers[InterviewScript.q1Name.id] == nil { return InterviewScript.q1Name }
        if answers[InterviewScript.q2Fork.id] == nil { return InterviewScript.q2Fork }
        if answers[InterviewScript.q3Age.id] == nil { return InterviewScript.q3Age }
        if answers[InterviewScript.q3City.id] == nil { return InterviewScript.q3City }
        if answers[InterviewScript.q3OccupationKind.id] == nil { return InterviewScript.q3OccupationKind }
        if ["work", "school", "both"].contains(answers[InterviewScript.q3OccupationKind.id] ?? ""),
           answers[InterviewScript.q3OccupationDetail.id] == nil {
            return InterviewScript.q3OccupationDetail
        }
        if statusChip == nil { return InterviewScript.q4Status }
        if hasRelationship {
            if answers[InterviewScript.q4PartnerName.id] == nil { return InterviewScript.q4PartnerName }
            if answers[InterviewScript.q4Duration.id] == nil { return InterviewScript.q4Duration }
            if answers[InterviewScript.q4State.id] == nil { return InterviewScript.q4State }
            if let stateAnswer = answers[InterviewScript.q4State.id],
               let chip = RelationshipStateChip(rawValue: stateAnswer), chip.isNegative,
               answers[InterviewScript.q4Followup.id] == nil {
                return InterviewScript.q4Followup
            }
            if answers[InterviewScript.q6Positive.id] == nil { return InterviewScript.q6Positive }
        }
        switch mode {
        case .focus:
            if hasRelationship {
                for (slot, prompt) in InterviewScript.deepDiveQuestions(for: .relationship) {
                    let node = InterviewScript.deepDiveNode(slot: slot, prompt: prompt)
                    if answers[node.id] == nil, !filledSlots.contains(slot) {
                        return node
                    }
                }
            }
        case .full:
            for node in InterviewScript.fullCensusNodes where answers[node.id] == nil {
                return node
            }
        }
        if answers[InterviewScript.q8Notifications.id] == nil { return InterviewScript.q8Notifications }
        if answers[InterviewScript.q9Close.id] == nil { return InterviewScript.q9Close }
        return nil
    }

    func node(for id: String) -> InterviewNode? {
        let fixed: [InterviewNode] = [
            InterviewScript.q1Name, InterviewScript.q2Fork, InterviewScript.q3Age,
            InterviewScript.q3City, InterviewScript.q3OccupationKind, InterviewScript.q3OccupationDetail,
            InterviewScript.q4Status, InterviewScript.q4PartnerName, InterviewScript.q4Duration,
            InterviewScript.q4State, InterviewScript.q4Followup, InterviewScript.q6Positive,
            InterviewScript.q8Notifications, InterviewScript.q9Close,
        ] + InterviewScript.fullCensusNodes
        if let match = fixed.first(where: { $0.id == id }) { return match }
        for type in ChapterType.allCases {
            for (slot, prompt) in InterviewScript.deepDiveQuestions(for: type)
            where "q7-deepdive-\(slot)" == id {
                return InterviewScript.deepDiveNode(slot: slot, prompt: prompt)
            }
        }
        return nil
    }

    func progress(answers: [String: String]) -> Double {
        let estimated = answers[InterviewScript.q2Fork.id] == InterviewScript.fullModeChip.id ? 15.0 : 13.0
        return min(1.0, Double(answers.count) / estimated)
    }
}
