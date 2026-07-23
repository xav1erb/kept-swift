import Foundation
import Testing
@testable import Kept

// M2-CONTRACTS §9.1 headless analog of the §13 device click-through: the WHOLE flow driven
// through OnboardingModel — census commands, the §8.1 queue, sign-in (FakeBackend), the flush
// through the real merge, initial backup, worldContents → followupQueue, reveal routing — and
// the returning-user restore path ("new phone, story follows you").

@MainActor
struct OnboardingFlowTests {

    private static let disclosureEnvelope = """
    {"schemaVersion": 1, "utteranceId": "$UTTERANCE_ID", "disambiguations": [], "deltas": [
      {"kind": "addEvent", "ref": "e1", "chapterRef": {"id": "$CHAPTER_ID"}, "datePrecision": "day",
       "title": "The talk", "body": "Talking to him tonight about the Instagram thing.",
       "valence": "storm", "isOpen": true, "isUpcoming": true}
    ]}
    """

    private static let positiveEnvelope = """
    {"schemaVersion": 1, "utteranceId": "$UTTERANCE_ID", "disambiguations": [], "deltas": [
      {"kind": "addEvent", "ref": "e1", "chapterRef": {"id": "$CHAPTER_ID"}, "datePrecision": "day",
       "title": "Laughing until crying", "body": "When it's good he makes me laugh until I cry.",
       "valence": "bright", "isOpen": false, "isUpcoming": false},
      {"kind": "fillSlots", "chapterRef": {"id": "$CHAPTER_ID"}, "slots": ["positives"]}
    ]}
    """

    /// Scripted proxy that also substitutes the census-created chapter id from the sent context —
    /// exactly what the live model does with the context we send (M1 §4).
    nonisolated struct ContextAwareExtraction: ExtractionServicing {
        let envelopeByUtterance: [String: String]

        func extract(_ request: ExtractionRequest) async throws -> ExtractionEnvelope {
            guard let template = envelopeByUtterance[request.utterance] else {
                throw ExtractionError.upstreamUnavailable
            }
            guard let chapterId = request.context.chapters.first?.id else {
                throw ExtractionError.upstreamUnavailable
            }
            let json = template
                .replacingOccurrences(of: "$UTTERANCE_ID", with: request.utteranceId.uuidString)
                .replacingOccurrences(of: "$CHAPTER_ID", with: chapterId.uuidString)
            return try JSONDecoder().decode(ExtractionEnvelope.self, from: Data(json.utf8))
        }
    }

    private func makeModel(
        store: KeptStore,
        backend: FakeBackend,
        masterKey: InMemoryMasterKey,
        extraction: any ExtractionServicing
    ) -> (OnboardingModel, FakeNotificationPermission, FakeAppIconApplier) {
        let notifications = FakeNotificationPermission()
        let icons = FakeAppIconApplier()
        let model = OnboardingModel(
            store: store, backend: backend, extraction: extraction,
            masterKey: masterKey, notifications: notifications, iconApplier: icons
        )
        return (model, notifications, icons)
    }

    @Test func focusForkEndToEnd() async throws {
        let store = try KeptStore(configuration: .inMemory)
        let backend = FakeBackend()
        let masterKey = InMemoryMasterKey()
        let extraction = ContextAwareExtraction(envelopeByUtterance: [
            "Talking to him tonight about the Instagram thing.": Self.disclosureEnvelope,
            "When it's good he makes me laugh until I cry.": Self.positiveEnvelope,
        ])
        let (model, _, icons) = makeModel(
            store: store, backend: backend, masterKey: masterKey, extraction: extraction
        )

        // 4.1 → 4.5
        model.advance()                       // splash → meetPom
        model.setName("Maya")                 // → themePicker
        model.advance()                       // → iconPicker
        await model.confirmIcon("IconMidnight")  // → aiConsent
        #expect(icons.applied == "IconMidnight")
        model.confirmConsent()                // → interview
        #expect(model.step == .interview)
        #expect(try store.userProfile().aiConsentGranted)

        // 4.6 — the interview (focus fork, relationship, negative word → one follow-up)
        await model.interviewSubmitText("Maya")
        await model.interviewTapChip(InterviewScript.focusModeChip)
        await model.interviewSubmitText("24")
        await model.interviewSubmitText("Amsterdam")
        await model.interviewTapChip(InterviewChip(id: "work", label: "Work"))
        await model.interviewSubmitText("designer")
        await model.interviewTapChip(InterviewChip(id: "yes", label: "Yes"))
        await model.interviewSubmitText("Daniel")
        await model.interviewSubmitText("2 years")
        await model.interviewTapChip(InterviewChip(id: "Confusing", label: "Confusing"))
        await model.interviewSubmitText("Talking to him tonight about the Instagram thing.")
        await model.interviewSubmitText("When it's good he makes me laugh until I cry.")
        model.interviewSkip()  // deep-dive livingSituation
        model.interviewSkip()  // deep-dive originStory
        model.interviewSkip()  // deep-dive openIssues
        await model.interviewTapChip(InterviewChip(id: "no", label: "No"))
        await model.interviewTapChip(InterviewChip(id: "ready", label: "I'm ready ✨"))

        // §8.1 amended order: pledge → faceID → signIn, queue still unflushed.
        #expect(model.step == .privacyPledge)
        #expect(try store.pendingUtterances().count == 2)
        model.advance()  // → faceID
        model.advance()  // → signIn

        // Sign-in triggers the flush + initial backup, then worldContents.
        await model.signInWithApple(idToken: "fake-token", nonce: nil)
        #expect(model.step == .worldContents)
        #expect(model.generatingPhase == .done)
        #expect(try store.pendingUtterances().isEmpty)
        #expect(!model.generatingLines.isEmpty)
        #expect(!backend.blobs.isEmpty)  // the first upload IS the built world

        // The queued disclosure filed into the census chapter: pinned upcoming event + bright event.
        let chapter = try #require(try store.chapterSummaries().first)
        let events = try store.events(inChapter: chapter.id)
        #expect(events.count == 2)
        #expect(events.contains { $0.isUpcoming && $0.title == "The talk" })
        #expect(events.contains { $0.valence == .bright })

        // 4.8 — unselecting a type keeps it out of the queue; selected-unbuilt types enqueue.
        model.selectedTypes = [.family, .money]
        model.confirmWorldContents()
        #expect(try store.userProfile().followupQueue == [.family, .money])
        #expect(model.step == .reveal)

        // 4.12 — a pinned upcoming event routes to prep (§13.9).
        #expect(model.revealRoutesToPrep)
        model.finishOnboarding()
        #expect(model.isFinished)
        #expect(try store.userProfile().hasCompletedOnboarding)
        #expect(try store.onboardingDraft() == nil)  // draft deleted at reveal
    }

    @Test func returningAccountRestoresTheWorld() async throws {
        // Device A: a lived-in world, backed up.
        let deviceA = try KeptStore(configuration: .inMemory)
        try deviceA.setUserName("Maya")
        let chapterId = try deviceA.createChapter(
            type: .relationship, chapterKind: .dimension, title: "Daniel · the Instagram thing", iconRef: "heart"
        )
        try deviceA.fillCensusSlots(chapterId: chapterId, slots: ["currentState", "partnerName"])
        try deviceA.completeOnboarding()

        let backend = FakeBackend()
        backend.seed(blobs: [], signedIn: true)
        let masterKey = InMemoryMasterKey()  // "synced iCloud Keychain": same key on both devices
        try await BackupService(store: deviceA, backend: backend, masterKey: masterKey).initialBackup()
        try await backend.signOut()

        // Device B: fresh install, walks to sign-in with minimal answers.
        let deviceB = try KeptStore(configuration: .inMemory)
        let (model, _, _) = makeModel(
            store: deviceB, backend: backend, masterKey: masterKey,
            extraction: ContextAwareExtraction(envelopeByUtterance: [:])
        )
        model.advance()
        model.setName("Maya")
        model.advance()
        await model.confirmIcon(nil)
        model.confirmConsent()
        await model.interviewSubmitText("Maya")
        await model.interviewTapChip(InterviewScript.focusModeChip)
        model.interviewSkip()   // age
        model.interviewSkip()   // city
        model.interviewSkip()   // occupation
        model.interviewSkip()   // relationship status → no couple blocks
        await model.interviewTapChip(InterviewChip(id: "no", label: "No"))   // q8
        await model.interviewTapChip(InterviewChip(id: "ready", label: "I'm ready ✨"))
        model.advance()  // pledge → faceID
        model.advance()  // faceID → signIn

        await model.signInWithApple(idToken: "fake-token", nonce: nil)

        // The story followed her: restored world, straight past worldContents to reveal.
        #expect(model.didRestoreExistingWorld)
        #expect(model.step == .reveal)
        #expect(try deviceB.userProfile().name == "Maya")
        #expect(try deviceB.userProfile().hasCompletedOnboarding)
        let restored = try #require(try deviceB.chapterSummaries().first)
        #expect(restored.title == "Daniel · the Instagram thing")
        #expect(restored.awarenessPct == 29)  // 2 of 7, computed at the original write (C6)
    }
}
