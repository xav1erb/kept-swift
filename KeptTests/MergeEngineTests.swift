import Foundation
import Testing
@testable import Kept

/// The M1 done-bar (extraction.md §5): the transcript-fixture corpus produces the exact expected
/// object graphs through the REAL merge into a real store — before any UI polish exists.
struct MergeEngineTests {

    // fx-001 — Onboarding, focus fork, the Daniel disclosure.
    @Test func fx001_focusForkDanielDisclosure() throws {
        let harness = try FixtureHarness()
        let summaries = try harness.run("fx-001")

        let profile = try harness.store.userProfile()
        #expect(profile.name == "Ana")
        #expect(profile.onboardingMode == .focus)
        #expect(profile.age == 24)
        #expect(profile.city == "Amsterdam")

        let chapters = try harness.store.chapterSummaries()
        #expect(chapters.count == 1)
        let chapter = try #require(chapters.first)
        #expect(chapter.title == "Daniel · the Instagram thing")   // AI title, user's words
        #expect(chapter.type == .relationship)
        #expect(chapter.state == .tense)
        #expect(chapter.awarenessPct == 57)   // 4 of 7 relationship slots — slot table, not model

        let people = try harness.store.people()
        let daniel = try #require(people.first)
        #expect(people.count == 1)
        #expect(daniel.name == "Daniel")
        #expect(daniel.relation == "partner")
        #expect(daniel.chapterIds == [chapter.id])

        let events = try harness.store.events(inChapter: chapter.id)
        #expect(events.count == 3)
        let evidence = try #require(events.first { $0.title == "Followed two new girls" })
        #expect(evidence.valence == .storm)
        #expect(evidence.isOpen)
        #expect(evidence.date == WireDate(year: 2026, month: 7, day: 18).date)
        #expect(evidence.source == .onboarding)
        let talk = try #require(events.first { $0.title == "The talk" })
        #expect(talk.isUpcoming)   // pinned; prep offered at the reveal (M2)
        let anchor = try #require(events.first { $0.title == "Flowers after every fight" })
        #expect(anchor.valence == .bright)
        // No stated date → merge falls back to the utterance date at day precision.
        #expect(anchor.date == WireDate(year: 2026, month: 7, day: 19).date)

        let promise = try #require(try harness.store.commitments(inChapter: chapter.id).first)
        #expect(promise.text == "no following girls")
        #expect(promise.dateMade == WireDate(year: 2026, month: 7, day: 6).date)  // receipts matter
        #expect(promise.status == .broken)
        #expect(promise.evidenceEventIds == [evidence.id])
        #expect(promise.personId == daniel.id)

        #expect(summaries.count == 2)
        #expect(summaries[0].touchedChapterIds == [chapter.id])
        #expect(summaries.allSatisfy { $0.pendingQuestions.isEmpty && !$0.wasAlreadyApplied })
    }

    // fx-002 — Full fork: census blocks → expected graph; followupQueue empty.
    @Test func fx002_fullForkCensus() throws {
        let harness = try FixtureHarness()
        try harness.run("fx-002")

        let profile = try harness.store.userProfile()
        #expect(profile.onboardingMode == .full)
        #expect(profile.followupQueue.isEmpty)

        let chapters = try harness.store.chapterSummaries()
        #expect(chapters.count == 3)
        #expect(try #require(chapters.first { $0.type == .family }).awarenessPct == 67)  // 4/6
        #expect(try #require(chapters.first { $0.type == .work }).awarenessPct == 50)    // 3/6
        #expect(try #require(chapters.first { $0.type == .money }).awarenessPct == 50)   // 2/4

        let mara = try #require(try harness.store.people().first)
        #expect(mara.name == "Mara")
        #expect(mara.chapterIds == [try #require(chapters.first { $0.type == .family }).id])

        let goal = try #require(try harness.store.goals().first)
        #expect(goal.text == "€6,000 saved")
        #expect(goal.progressNote == "at €4,200")
        #expect(goal.chapterId == chapters.first { $0.type == .money }?.id)
    }

    // fx-003 — Three-topic vent: exactly 3 chapters touched, no 4th write.
    @Test func fx003_threeTopicVentFilesToThreeChapters() throws {
        let harness = try FixtureHarness()
        let summaries = try harness.run("fx-003")

        #expect(summaries[1].touchedChapterIds.count == 3)
        let chapters = try harness.store.chapterSummaries()
        #expect(chapters.count == 3)   // the vent created nothing new
        #expect(Set(summaries[1].touchedChapterIds) == Set(chapters.map(\.id)))

        let ventEvents = try harness.allEvents().filter { $0.source == .vent }
        #expect(ventEvents.count == 3)   // source stamped from the surface, never model-set
        #expect(try #require(try harness.store.people().first { $0.name == "Mara" }).mood == .tense)
        #expect(try #require(chapters.first { $0.type == .family }).state == .tense)
    }

    // fx-004 — Two Saras: disambiguation raised; ALL Sara-deltas held; nothing auto-merged.
    @Test func fx004_twoSarasDisambiguationGate() throws {
        let harness = try FixtureHarness()
        let steps = try harness.steps(named: "fx-004")
        try harness.apply(steps[0])
        try harness.apply(steps[1])   // second Sara enters through the gate, confirmed-new
        #expect(try harness.store.people().count == 2)

        let summary = try harness.apply(steps[2])
        #expect(summary.pendingQuestions.count == 1)
        let pending = try #require(try harness.store.pendingDisambiguations().first)
        #expect(pending.mention == "Sara")
        #expect(pending.question == "work-Sara, not friend-Sara, right?")
        #expect(pending.candidateIds.count == 2)

        // Everything else in the envelope applied; the Sara-deltas wait.
        let workId = try harness.resolveToken("$chapter:Work")
        #expect(try harness.store.events(inChapter: workId).count == 1)
        #expect(try harness.store.people().allSatisfy { $0.mood == .fine })

        let colleagueId = try harness.resolveToken("$person:Sara/colleague")
        try harness.store.resolveDisambiguation(batchId: pending.id, resolution: .existing(colleagueId))

        let people = try harness.store.people()
        #expect(people.count == 2)   // resolution never merged or duplicated anyone
        #expect(try #require(people.first { $0.id == colleagueId }).mood == .warm)
        #expect(try #require(people.first { $0.relation == "friend" }).mood == .fine)
        #expect(try harness.store.pendingDisambiguations().isEmpty)
    }

    // fx-005 — Name collision the model missed: the deterministic backstop converts the create.
    @Test func fx005_backstopConvertsSilentDuplicateIntoDisambiguation() throws {
        let harness = try FixtureHarness()
        let steps = try harness.steps(named: "fx-005")
        try harness.apply(steps[0])

        let summary = try harness.apply(steps[1])
        let pending = try #require(summary.pendingQuestions.first)
        #expect(pending.mention == "Sara")
        #expect(pending.question == "Is this the Sara you've told me about, or someone new?")
        #expect(try harness.store.people().count == 1)   // nothing silently created
        #expect(try harness.store.chapterSummaries().count == 2)   // the chapter itself applied

        try harness.store.resolveDisambiguation(batchId: pending.id, resolution: .newPerson)
        let people = try harness.store.people()
        #expect(people.count == 2)   // two Saras, distinct forever
        let yogaSara = try #require(people.first { $0.relation == "friend from yoga" })
        #expect(yogaSara.mood == .warm)
        #expect(yogaSara.chapterIds == [try harness.resolveToken("$chapter:Friends")])
    }

    // fx-006 — Commitment lifecycle: made (dated) → later utterance breaks it with evidence.
    @Test func fx006_commitmentLifecycle() throws {
        let harness = try FixtureHarness()
        let steps = try harness.steps(named: "fx-006")

        try harness.apply(steps[0])
        var promise = try #require(try harness.allCommitments().first)
        #expect(promise.status == .held)
        #expect(promise.dateMade == WireDate(year: 2026, month: 6, day: 1).date)
        #expect(promise.evidenceEventIds.isEmpty)

        try harness.apply(steps[1])
        promise = try #require(try harness.allCommitments().first)
        #expect(promise.status == .broken)
        let evidence = try #require(try harness.allEvents().first { $0.title == "Missed the Sunday call" })
        #expect(promise.evidenceEventIds == [evidence.id])
    }

    // fx-007 — Positive anchor: bright events, keep-card material, valence correct.
    @Test func fx007_positiveAnchor() throws {
        let harness = try FixtureHarness()
        try harness.run("fx-007")

        let events = try harness.allEvents()
        #expect(events.count == 2)
        #expect(try #require(events.first { $0.title == "Sunday cooking" }).valence == .bright)
        #expect(try #require(events.first { $0.title == "Sunset at the pier" }).valence == .gold)
        #expect(events.allSatisfy { !$0.isOpen })   // anchors are kept moments, not wounds
        #expect(try #require(try harness.store.chapterSummaries().first).awarenessPct == 14)  // 1/7
    }

    // fx-008 — Folding: user's own words fold; refolding never overwrites; no unfold exists.
    @Test func fx008_foldingIsOneWayAndConservative() throws {
        let harness = try FixtureHarness()
        let steps = try harness.steps(named: "fx-008")
        try harness.apply(steps[0])
        try harness.apply(steps[1])

        var fight = try #require(try harness.allEvents().first { $0.title == "The birthday fight" })
        #expect(fight.isHealed)
        #expect(fight.healedReason == "We talked properly and I forgave her")   // her words
        #expect(try #require(try harness.store.chapterSummaries().first).state == .warm)

        try harness.apply(steps[2])   // a second fold attempt
        fight = try #require(try harness.allEvents().first { $0.title == "The birthday fight" })
        #expect(fight.isHealed)
        #expect(fight.healedReason == "We talked properly and I forgave her")   // NOT overwritten
    }

    // fx-009 — Idempotent replay: the same envelope twice → byte-identical graph.
    @Test func fx009_idempotentReplay() throws {
        let harness = try FixtureHarness()
        let step = try #require(try harness.steps(named: "fx-009").first)

        let first = try harness.apply(step)
        #expect(!first.wasAlreadyApplied)
        let world = try harness.worldSnapshot()

        let replay = try harness.apply(step)
        #expect(replay.wasAlreadyApplied)
        #expect(replay.touchedChapterIds.isEmpty)
        #expect(try harness.worldSnapshot() == world)
    }

    // fx-010 — Poisoned envelopes: loud rejection at the right boundary, store untouched.
    @Test func fx010_poisonedEnvelopesRejectLoudly() throws {
        let harness = try FixtureHarness()
        let poisoned = try FixtureHarness.poisonedEnvelopes(named: "fx-010")

        for name in ["unknownKind", "unknownEnum", "bothIdAndRef", "malformedDate"] {
            #expect(throws: DecodingError.self, "\(name) must fail at decode") {
                _ = try JSONDecoder().decode(ExtractionEnvelope.self, from: try #require(poisoned[name]))
            }
        }

        let before = try harness.worldSnapshot()
        for name in ["forwardRef", "fabricatedId", "badSlot", "wrongSchemaVersion"] {
            let envelope = try JSONDecoder().decode(
                ExtractionEnvelope.self, from: try #require(poisoned[name])
            )
            let context = try harness.store.extractionContext()
            #expect(throws: MergeError.self, "\(name) must fail validation") {
                try harness.store.applyExtraction(
                    envelope, sentContext: context, surface: .vent, clientTime: .now
                )
            }
        }
        // Envelope-atomic: nothing partial ever landed (badSlot's chapter included).
        #expect(try harness.worldSnapshot() == before)
        #expect(try harness.store.chapterSummaries().isEmpty)
    }

    // fx-011 — Sensitive type: internal slots fill, no count exposed anywhere (§19 never-test).
    @Test func fx011_griefSlotsAreInternalOnly() throws {
        let harness = try FixtureHarness()
        try harness.run("fx-011")

        let chapter = try #require(try harness.store.chapterSummaries().first)
        #expect(chapter.type == .grief)
        #expect(chapter.type.isSensitive)
        #expect(chapter.awarenessPct == 75)   // 3/4 internal slots — % exists for the pin

        // The UI-facing read model carries NO slot list, slot count, or question count —
        // asserted structurally, not by copy discipline (C3).
        let labels = Mirror(reflecting: chapter).children.compactMap(\.label)
        #expect(!labels.contains { label in
            label.localizedCaseInsensitiveContains("slot")
                || label.localizedCaseInsensitiveContains("question")
        })
    }

    // The slot tables themselves are contract surface (extraction.md §4) — pin the totals.
    @Test func slotTableTotalsMatchTheSpec() {
        let expected: [ChapterType: Int] = [
            .relationship: 7, .family: 6, .friendship: 5, .work: 6, .health: 5,
            .money: 4, .passion: 4, .growth: 5, .privateCorner: 3, .grief: 4,
        ]
        for (type, count) in expected {
            #expect(AwarenessSchema.slots(for: type).count == count, "\(type)")
        }
        #expect(AwarenessSchema.awarenessPct(filledSlots: ["partnerName"], type: .relationship) == 14)
        #expect(AwarenessSchema.awarenessPct(filledSlots: [], type: .money) == 0)
        #expect(
            AwarenessSchema.awarenessPct(
                filledSlots: AwarenessSchema.slots(for: .grief), type: .grief
            ) == 100
        )
    }
}
