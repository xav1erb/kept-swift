import Foundation
import SwiftUI

// The onboarding step machine (M2-CONTRACTS §2, §8.1 amended order): interview → pledge →
// Face ID → sign-in → world-generating (the queue flushes here, so the dwell is real work) →
// world-contents → reveal. Every transition persists the draft; kill/relaunch resumes exactly.

enum OnboardingStep: Int, CaseIterable, Codable {
    case splash, meetPom, themePicker, iconPicker, aiConsent,
         interview, privacyPledge, faceID, signIn,
         worldGenerating, worldContents, reveal
}

protocol AppIconApplying: AnyObject {
    /// nil = the primary (Pom) icon. Async, can fail — the caller keeps the default + soft note.
    func applyIcon(named name: String?) async throws
}

final class LiveAppIconApplier: AppIconApplying {
    func applyIcon(named name: String?) async throws {
        try await UIApplication.shared.setAlternateIconName(name)
    }
}

final class FakeAppIconApplier: AppIconApplying {
    private(set) var applied: String??
    func applyIcon(named name: String?) async throws { applied = name }
}

@Observable
final class OnboardingModel {

    enum SignInPhase: Equatable {
        case idle, working, linkSent, failed(String)
    }

    enum GeneratingPhase: Equatable {
        case idle
        case flushing
        case askingQuestions
        case done
        /// Extraction failed for some utterances — filing lags, never silently drops (NN#7).
        case partial(failedCount: Int)
    }

    private let store: KeptStore
    private let backend: any BackendServicing
    private let flusher: UtteranceFlusher
    private let backup: BackupService
    private let iconApplier: any AppIconApplying

    let interview: InterviewEngine

    private(set) var step: OnboardingStep = .splash
    private(set) var signInPhase: SignInPhase = .idle
    private(set) var generatingPhase: GeneratingPhase = .idle
    private(set) var generatingLines: [String] = []
    private(set) var pendingQuestions: [PendingDisambiguation] = []
    private(set) var didRestoreExistingWorld = false
    /// Flips at reveal — RootView's observable signal to leave onboarding.
    private(set) var isFinished = false
    var selectedTypes: Set<ChapterType> = []

    var restrictedStop: Bool { interview.restrictedStop }

    init(
        store: KeptStore,
        backend: any BackendServicing,
        extraction: any ExtractionServicing,
        masterKey: any MasterKeyProviding,
        notifications: any NotificationPermissionRequesting = LiveNotificationPermission(),
        iconApplier: any AppIconApplying = LiveAppIconApplier()
    ) {
        self.store = store
        self.backend = backend
        self.flusher = UtteranceFlusher(store: store, extraction: extraction)
        self.backup = BackupService(store: store, backend: backend, masterKey: masterKey)
        self.iconApplier = iconApplier
        self.interview = InterviewEngine(store: store, notifications: notifications)
        resumeFromDraftIfPresent()
    }

    // MARK: - Resume (§13.6)

    private func resumeFromDraftIfPresent() {
        guard let draft = try? store.onboardingDraft(),
              let savedStep = OnboardingStep(rawValue: draft.stepRaw)
        else { return }
        step = savedStep
        guard savedStep == .interview else { return }
        let decoder = JSONDecoder()
        let bubbles = (try? decoder.decode([DraftBubble].self, from: draft.bubblesJSON)) ?? []
        let answers = (try? decoder.decode([String: String].self, from: draft.answersJSON)) ?? [:]
        interview.resume(bubbles: bubbles, answers: answers, nodeId: draft.nodeId)
    }

    private func persistDraft() {
        let encoder = JSONEncoder()
        let bubbles = (try? encoder.encode(interview.bubbles)) ?? Data()
        let answers = (try? encoder.encode(interview.answers)) ?? Data()
        try? store.saveOnboardingDraft(
            stepRaw: step.rawValue, nodeId: interview.currentNode?.id,
            bubblesJSON: bubbles, answersJSON: answers
        )
    }

    // MARK: - Step transitions

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
        persistDraft()
        if next == .interview { interview.start(); persistDraft() }
    }

    // MARK: - Per-screen commands

    func setName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { try? store.setUserName(trimmed) }
        advance()
    }

    func pickTheme(_ theme: Theme, themeModel: ThemeModel) {
        try? store.setTheme(theme)
        themeModel.theme = theme
    }

    func confirmIcon(_ iconName: String?) async {
        // Failure keeps the default icon + a soft retry note lives in the view (spec 4.4).
        try? await iconApplier.applyIcon(named: iconName)
        advance()
    }

    /// The 4.5 legal gate — no skip; declining means not proceeding past it.
    func confirmConsent() {
        try? store.grantAIConsent()
        advance()
    }

    func interviewSubmitText(_ text: String) async {
        await interview.submitText(text)
        afterInterviewInteraction()
    }

    func interviewTapChip(_ chip: InterviewChip) async {
        await interview.tapChip(chip)
        afterInterviewInteraction()
    }

    func interviewSkip() {
        interview.skip()
        afterInterviewInteraction()
    }

    private func afterInterviewInteraction() {
        persistDraft()
        if interview.isComplete {
            advance()  // → privacyPledge
        }
    }

    // MARK: - Sign-in (4.11) + the §8.1 flush

    func signInWithApple(idToken: String, nonce: String?) async {
        signInPhase = .working
        do {
            try await backend.signInWithApple(idToken: idToken, nonce: nonce)
            await onSignedIn()
        } catch {
            signInPhase = .failed(Self.message(for: error))
        }
    }

    func sendMagicLink(email: String) async {
        signInPhase = .working
        do {
            try await backend.sendMagicLink(email: email)
            signInPhase = .linkSent
        } catch {
            signInPhase = .failed(Self.message(for: error))
        }
    }

    func handleAuthCallback(url: URL) async {
        guard step == .signIn else { return }
        do {
            if try await backend.handleAuthCallback(url: url) {
                await onSignedIn()
            }
        } catch {
            signInPhase = .failed(Self.message(for: error))
        }
    }

    private func onSignedIn() async {
        signInPhase = .idle
        advance()  // → worldGenerating
        await runWorldGenerating()
    }

    /// worldGenerating (§8.1): restore-or-flush, then narrate from REAL store state (C4 — no
    /// fake progress; the dwell is the actual work).
    private func runWorldGenerating() async {
        generatingPhase = .flushing
        // Minimum dwell for the breathing-globe moment (spec 4.7) — a floor, never fake progress.
        async let dwell: Void? = try? await Task.sleep(for: .seconds(1.5))
        // Returning account? The story follows you (M2 §7.3) — restore first, then the new
        // answers flush into the restored world.
        if let exists = try? await backup.serverWorldExists(), exists {
            do {
                try await backup.restoreServerWorld()
                didRestoreExistingWorld = true
            } catch {
                generatingPhase = .partial(failedCount: 0)
            }
        }
        let result = await flusher.flush()
        _ = await dwell
        pendingQuestions = result.pendingQuestions
        narrateFromStore()
        if !result.pendingQuestions.isEmpty {
            generatingPhase = .askingQuestions
            return
        }
        await finishGenerating(failedCount: result.failedUtteranceIds.count)
    }

    func resolveQuestion(_ question: PendingDisambiguation, resolution: PersonResolution) async {
        _ = try? store.resolveDisambiguation(batchId: question.id, resolution: resolution)
        pendingQuestions.removeAll { $0.id == question.id }
        if pendingQuestions.isEmpty {
            narrateFromStore()
            await finishGenerating(failedCount: 0)
        }
    }

    private func finishGenerating(failedCount: Int) async {
        // The initial full backup (§7.3) — after flush so the first upload IS the built world.
        try? await backup.initialBackup()
        generatingPhase = failedCount > 0 ? .partial(failedCount: failedCount) : .done
        advance()  // → worldContents
        if didRestoreExistingWorld {
            advance()  // world already confirmed once — straight to reveal
        }
    }

    private func narrateFromStore() {
        var lines: [String] = []
        if let chapters = try? store.chapterSummaries(), !chapters.isEmpty {
            for chapter in chapters {
                lines.append("✓ planting \(chapter.title)")
            }
        }
        if let people = try? store.people(), !people.isEmpty {
            lines.append("✓ remembering \(people.map(\.name).joined(separator: ", "))")
        }
        let themeName = ((try? store.userProfile())?.theme.displayName) ?? "your colors"
        lines.append("✦ painting the sky in \(themeName)…")
        generatingLines = lines
    }

    // MARK: - World contents (4.8) → reveal

    func confirmWorldContents() {
        let built = Set((try? store.chapterSummaries())?.map(\.type) ?? [])
        let unbuilt = selectedTypes.subtracting(built)
        try? store.enqueueFollowups(Array(unbuilt))
        advance()  // → reveal
    }

    /// Reveal routing (§13.9): pinned upcoming event → prep; else vent offer.
    var revealRoutesToPrep: Bool {
        guard let chapters = try? store.chapterSummaries() else { return false }
        for chapter in chapters {
            if let events = try? store.events(inChapter: chapter.id),
               events.contains(where: { $0.isUpcoming }) {
                return true
            }
        }
        return false
    }

    func finishOnboarding() {
        try? store.completeOnboarding()
        isFinished = true
    }

    func candidateName(_ id: UUID) -> String {
        ((try? store.people()) ?? []).first { $0.id == id }?.name ?? "someone"
    }

    private static func message(for error: Error) -> String {
        switch error {
        case BackendError.unconfigured:
            "Sign-in isn't configured in this build yet."
        case BackendError.notSignedIn:
            "That didn't stick — try once more?"
        default:
            "Something in the connection didn't cooperate. Try again in a moment."
        }
    }
}
