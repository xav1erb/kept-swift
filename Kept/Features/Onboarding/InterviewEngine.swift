import Foundation
import UserNotifications

// The interview sub-machine (M2-CONTRACTS §2/§3). Walks InterviewScript deterministically:
// chips/fields → typed store commands the moment they're given; free text → the PendingUtterance
// queue (§8.1 — extraction runs at sign-in). Branching is a pure function of the answers map, so
// resume rebuilds the exact position from the persisted draft. Skips write nothing, queue
// nothing, and Pom never comments (§13.10).

protocol NotificationPermissionRequesting: AnyObject {
    /// The iOS system prompt — called ONLY after an explicit Yes chip (pre-permission pattern).
    func requestAuthorization() async -> Bool
}

final class LiveNotificationPermission: NotificationPermissionRequesting {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }
}

final class FakeNotificationPermission: NotificationPermissionRequesting {
    private(set) var requested = false
    var grants = true
    func requestAuthorization() async -> Bool {
        requested = true
        return grants
    }
}

@Observable
final class InterviewEngine {

    private let store: KeptStore
    private let notifications: any NotificationPermissionRequesting

    private(set) var bubbles: [DraftBubble] = []
    private(set) var currentNode: InterviewNode?
    private(set) var answers: [String: String] = [:]
    private(set) var isComplete = false
    /// F6 under-13 hard stop: the model layer routes to the soft landing; data already wiped.
    private(set) var restrictedStop = false

    /// Skipped chip id marker — never written anywhere, only used for branch decisions.
    private static let skipMarker = "\u{0}skip"

    init(store: KeptStore, notifications: any NotificationPermissionRequesting = LiveNotificationPermission()) {
        self.store = store
        self.notifications = notifications
    }

    // MARK: - Lifecycle

    func start() {
        guard currentNode == nil, !isComplete else { return }
        show(node: InterviewScript.q1Name)
    }

    /// Rebuild from the persisted draft (kill/relaunch mid-interview, §13.6).
    func resume(bubbles: [DraftBubble], answers: [String: String], nodeId: String?) {
        self.bubbles = bubbles
        self.answers = answers
        if let nodeId, let node = node(for: nodeId) {
            self.currentNode = node
        } else if nodeId == nil, answers.isEmpty {
            start()
        } else {
            advance()
        }
    }

    /// Fraction of the active path consumed — drives the interview's progress segment.
    var progress: Double {
        let estimated = answers[InterviewScript.q2Fork.id] == InterviewScript.fullModeChip.id ? 15.0 : 13.0
        return min(1.0, Double(answers.count) / estimated)
    }

    // MARK: - Input

    func submitText(_ text: String) async {
        guard let node = currentNode else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendUser(trimmed)
        answers[node.id] = trimmed
        await write(node: node, answer: trimmed)
        guard !restrictedStop else { return }
        acknowledge(node)
        advance()
    }

    func tapChip(_ chip: InterviewChip) async {
        guard let node = currentNode else { return }
        appendUser(chip.label)
        answers[node.id] = chip.id
        await write(node: node, answer: chip.id)
        acknowledge(node)
        advance()
    }

    /// A skip advances with no write, no queue entry, no comment from Pom (§13.10).
    func skip() {
        guard let node = currentNode, node.skippable else { return }
        answers[node.id] = Self.skipMarker
        advance()
    }

    // MARK: - Writes (chips/fields → commands; free text → the queue)

    private func write(node: InterviewNode, answer: String) async {
        do {
            switch node.write {
            case .none:
                break
            case .userName:
                try store.setUserName(answer)
            case .onboardingMode:
                try store.setOnboardingMode(answer == InterviewScript.focusModeChip.id ? .focus : .full)
            case .age:
                guard let age = Int(answer), age > 0, age < 120 else { break }
                if age < 13 {
                    // F6 hard stop: nothing retained (M2-CONTRACTS §6).
                    try store.wipeOnboardingData()
                    restrictedStop = true
                } else {
                    try store.setUserBasics(age: age)
                }
            case .city:
                try store.setUserBasics(city: answer)
            case .occupationKind:
                // work/school/both branch into the detail question; the other chips ARE the answer.
                if answer == "between" { try store.setUserBasics(occupation: "in between") }
                if answer == "none" { try store.setUserBasics(occupation: "living my best life") }
            case .occupationDetail:
                try store.setUserBasics(occupation: answer)
            case .relationshipStatus, .partnerName, .relationshipDuration:
                break  // accumulate; materialized at q4-state
            case .relationshipState:
                guard let chip = RelationshipStateChip(rawValue: answer) else { break }
                try store.applyRelationshipCensus(
                    partnerName: cleanAnswer(InterviewScript.q4PartnerName.id),
                    duration: cleanAnswer(InterviewScript.q4Duration.id),
                    stateChip: chip
                )
            case .utterance:
                try store.enqueueUtterance(surface: .onboarding, nodeId: node.id, text: answer)
            case .notificationChoice:
                if answer == "yes" {
                    _ = await notifications.requestAuthorization()
                }
            }
        } catch {
            // A failed structured write is a script/store bug — surface it in the transcript
            // honestly rather than pretending the answer was kept.
            appendPom("Something went wrong keeping that — let's keep going, I'll ask again later.")
        }
    }

    // MARK: - Path (pure over the answers map)

    private func advance() {
        if let next = nextNode() {
            show(node: next)
        } else {
            currentNode = nil
            isComplete = true
        }
    }

    private func nextNode() -> InterviewNode? {
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
                    if answers[node.id] == nil, !censusFilledSlots().contains(slot) {
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

    private func node(for id: String) -> InterviewNode? {
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

    private func censusFilledSlots() -> [String] {
        (try? store.chapterSummaries().first(where: { $0.type == .relationship })).flatMap { summary in
            try? store.extractionContext().chapters.first(where: { $0.id == summary.id })?.filledSlots
        } ?? []
    }

    // MARK: - Transcript

    private func show(node: InterviewNode) {
        currentNode = node
        for prompt in node.prompts {
            appendPom(substitute(prompt))
        }
    }

    private func acknowledge(_ node: InterviewNode) {
        if let ack = node.acknowledgment {
            appendPom(substitute(ack))
        }
    }

    private func appendPom(_ text: String) {
        bubbles.append(DraftBubble(author: .pom, text: text))
    }

    private func appendUser(_ text: String) {
        bubbles.append(DraftBubble(author: .user, text: text))
    }

    private func substitute(_ text: String) -> String {
        let name = cleanAnswer(InterviewScript.q1Name.id) ?? ""
        let partner = cleanAnswer(InterviewScript.q4PartnerName.id) ?? "them"
        return text
            .replacingOccurrences(of: "{name}", with: name.isEmpty ? "friend" : name)
            .replacingOccurrences(of: "{partner}", with: partner)
    }

    private func cleanAnswer(_ nodeId: String) -> String? {
        guard let answer = answers[nodeId], answer != Self.skipMarker else { return nil }
        return answer
    }
}
