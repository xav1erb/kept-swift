import Foundation
import Testing
@testable import Kept

// M2-CONTRACTS §9.2/§9.5: the interview engine walked headlessly in both forks — chips/fields
// land as typed store writes the moment they're given, free text queues, skips write nothing,
// the F6 gate stops-and-wipes, resume rebuilds the exact position.

@MainActor
struct OnboardingEngineTests {

    private func makeEngine() throws -> (KeptStore, InterviewEngine, FakeNotificationPermission) {
        let store = try KeptStore(configuration: .inMemory)
        try store.grantAIConsent()  // 4.5 precedes the interview in the flow
        let notifications = FakeNotificationPermission()
        let engine = InterviewEngine(store: store, notifications: notifications)
        engine.start()
        return (store, engine, notifications)
    }

    @Test func focusForkWalkProducesCensusGraphAndQueue() async throws {
        let (store, engine, notifications) = try makeEngine()

        await engine.submitText("Maya")                                   // q1
        await engine.tapChip(InterviewScript.focusModeChip)               // q2
        await engine.submitText("24")                                     // q3 age
        await engine.submitText("Amsterdam")                              // q3 city
        await engine.tapChip(InterviewChip(id: "work", label: "Work"))    // q3 kind
        await engine.submitText("designer")                               // q3 detail
        await engine.tapChip(InterviewChip(id: "yes", label: "Yes"))      // q4 status
        await engine.submitText("Daniel")                                 // q4 partner
        await engine.submitText("2 years")                                // q4 duration
        await engine.tapChip(InterviewChip(id: "Confusing", label: "Confusing"))  // q4 state
        await engine.submitText("He promised to stop following those girls and I saw he didn't.")  // q4 followup
        await engine.submitText("When it's good he makes me laugh until I cry.")  // q6

        // Deep-dive: census filled partnerName/duration/currentState → three remaining slots.
        #expect(engine.currentNode?.id == "q7-deepdive-livingSituation")
        await engine.submitText("We live together since spring.")
        #expect(engine.currentNode?.id == "q7-deepdive-originStory")
        await engine.submitText("We met at a friend's dinner.")
        #expect(engine.currentNode?.id == "q7-deepdive-openIssues")
        await engine.submitText("The Instagram thing is still open.")

        await engine.tapChip(InterviewChip(id: "yes", label: "Yes"))      // q8
        await engine.tapChip(InterviewChip(id: "ready", label: "I'm ready ✨"))  // q9
        #expect(engine.isComplete)

        // Typed census writes landed the moment they were given.
        let profile = try store.userProfile()
        #expect(profile.name == "Maya")
        #expect(profile.age == 24)
        #expect(profile.city == "Amsterdam")
        #expect(profile.occupation == "designer")
        #expect(profile.onboardingMode == .focus)
        #expect(profile.isMinor == false)

        let chapters = try store.chapterSummaries()
        #expect(chapters.count == 1)
        let relationship = try #require(chapters.first)
        #expect(relationship.type == .relationship)
        #expect(relationship.state == .complicated)
        #expect(relationship.awarenessPct == 43)  // 3 of 7 slots, computed at write (C6)

        let people = try store.people()
        #expect(people.map(\.name) == ["Daniel"])
        #expect(people.first?.relation == "partner")

        // Free text queued FIFO — nothing extracted before sign-in (§8.1).
        let queued = try store.pendingUtterances()
        #expect(queued.count == 5)
        #expect(queued.map(\.nodeId) == [
            "q4-followup", "q6-positive",
            "q7-deepdive-livingSituation", "q7-deepdive-originStory", "q7-deepdive-openIssues",
        ])
        #expect(queued.map(\.order) == Array(0..<5))

        #expect(notifications.requested)  // Yes chip → system prompt (pre-permission pattern)
    }

    @Test func fullForkWithoutRelationshipSkipsCoupleBlocks() async throws {
        let (store, engine, notifications) = try makeEngine()

        await engine.submitText("Sam")
        await engine.tapChip(InterviewScript.fullModeChip)
        await engine.submitText("30")
        await engine.submitText("Utrecht")
        await engine.tapChip(InterviewChip(id: "between", label: "In between"))
        await engine.tapChip(InterviewChip(id: "no", label: "No"))         // q4 status: No

        // Straight into the census blocks — no partner questions, no q6.
        #expect(engine.currentNode?.id == "q7-family")
        await engine.submitText("Mom and my sister Lena; mom worries too much.")
        await engine.submitText("Between jobs, interviewing at two places.")
        await engine.submitText("Sleeping badly lately.")
        await engine.submitText("Trying to save six thousand for the move.")
        await engine.tapChip(InterviewChip(id: "no", label: "No"))          // q8: No
        await engine.tapChip(InterviewChip(id: "ready", label: "I'm ready ✨"))

        #expect(engine.isComplete)
        #expect(try store.chapterSummaries().isEmpty)  // chapters come from extraction at flush
        #expect(try store.pendingUtterances().count == 4)
        #expect(notifications.requested == false)  // No chip → NO system prompt (§13.7)
        #expect(try store.userProfile().occupation == "in between")
    }

    @Test func skipsWriteNothingAndPomNeverComments() async throws {
        let (store, engine, _) = try makeEngine()

        engine.skip()  // q1 name
        // No user bubble, no acknowledgment for a skip — only Pom's next prompts appear.
        #expect(engine.bubbles.allSatisfy { $0.author == .pom })

        await engine.tapChip(InterviewScript.focusModeChip)
        engine.skip()  // q3 age
        engine.skip()  // q3 city
        engine.skip()  // q3 occupation kind
        engine.skip()  // q4 status
        // No relationship → q8 next in focus mode.
        #expect(engine.currentNode?.id == "q8-notifications")

        let profile = try store.userProfile()
        #expect(profile.name.isEmpty)
        #expect(profile.age == nil)
        #expect(profile.city == nil)
        #expect(profile.occupation == nil)
        #expect(profile.isMinor == false)  // skipped age = unrestricted (§8.3 ruling)
        #expect(try store.pendingUtterances().isEmpty)
    }

    @Test func under13HardStopsAndWipes() async throws {
        let (store, engine, _) = try makeEngine()

        await engine.submitText("Kid")
        await engine.tapChip(InterviewScript.focusModeChip)
        await engine.submitText("12")

        #expect(engine.restrictedStop)
        let profile = try store.userProfile()
        #expect(profile.name.isEmpty)          // wiped — nothing retained (F6)
        #expect(profile.age == nil)
        #expect(profile.aiConsentGranted == false)
        #expect(try store.pendingUtterances().isEmpty)
        #expect(try store.onboardingDraft() == nil)
    }

    @Test func minorAgeDerivesIsMinorAtWrite() async throws {
        let (store, engine, _) = try makeEngine()
        await engine.submitText("Teen")
        await engine.tapChip(InterviewScript.focusModeChip)
        await engine.submitText("15")
        #expect(engine.restrictedStop == false)  // silent — no callout, no stop (F6)
        #expect(try store.userProfile().isMinor)
    }

    @Test func resumeRebuildsExactPosition() async throws {
        let (store, engine, _) = try makeEngine()
        await engine.submitText("Maya")
        await engine.tapChip(InterviewScript.focusModeChip)
        await engine.submitText("24")

        let savedBubbles = engine.bubbles
        let savedAnswers = engine.answers
        let savedNode = engine.currentNode?.id

        let revived = InterviewEngine(store: store, notifications: FakeNotificationPermission())
        revived.resume(bubbles: savedBubbles, answers: savedAnswers, nodeId: savedNode)
        #expect(revived.currentNode?.id == "q3-city")
        #expect(revived.bubbles == savedBubbles)

        await revived.submitText("Amsterdam")
        #expect(revived.currentNode?.id == "q3-occupation-kind")
        #expect(try store.userProfile().city == "Amsterdam")
    }
}
