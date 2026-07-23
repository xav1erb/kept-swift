import Foundation
import Testing
@testable import Kept

// M3-CONTRACTS §5/§6: the new-chapter grid + the shared-engine sequence (§8 ruling 1). The
// milestone's "done" check lives here: a chapter created via its sequence appears on the globe
// with a correct awareness ring, fed by the REAL pipeline (scripted proxy, real decode, real
// merge — fake the source, never the shape).

@MainActor
struct NewChapterTests {

    /// Scripted proxy: canned envelope per utterance text, ids substituted from the request —
    /// decoded by the real strict decoder, merged by the real engine.
    nonisolated struct ScriptedSequenceExtraction: ExtractionServicing {
        let envelopeByUtterance: [String: String]

        func extract(_ request: ExtractionRequest) async throws -> ExtractionEnvelope {
            guard let template = envelopeByUtterance[request.utterance],
                  let chapterId = request.context.chapters.first?.id else {
                throw ExtractionError.upstreamUnavailable
            }
            let json = template
                .replacingOccurrences(of: "$UTTERANCE_ID", with: request.utteranceId.uuidString)
                .replacingOccurrences(of: "$CHAPTER_ID", with: chapterId.uuidString)
            return try JSONDecoder().decode(ExtractionEnvelope.self, from: Data(json.utf8))
        }
    }

    private static func slotEnvelope(_ slot: String) -> String {
        """
        {"schemaVersion": 1, "utteranceId": "$UTTERANCE_ID", "disambiguations": [], "deltas": [
          {"kind": "fillSlots", "chapterRef": {"id": "$CHAPTER_ID"}, "slots": ["\(slot)"]}
        ]}
        """
    }

    private func makeStore() throws -> KeptStore {
        let store = try KeptStore(configuration: .inMemory)
        try store.setUserName("Maya")
        try store.grantAIConsent()
        try store.completeOnboarding()
        return store
    }

    // §5 — grid cards: counts come from the slot tables; sensitive types have NO count string
    // by construction (C3 never-test) and render "goes gently" instead.
    @Test func gridCardsNeverCountSensitiveTypes() {
        let cards = NewChapterModel.cards()
        #expect(cards.count == ChapterType.allCases.count)
        for card in cards {
            if card.type.isSensitive {
                #expect(card.countText == nil)
                #expect(card.gentleText == "goes gently")
            } else {
                let expected = AwarenessSchema.slots(for: card.type).count
                #expect(card.countText == "\(expected) questions")
                #expect(card.gentleText == nil)
            }
        }
        // Whitepaper §6 counts are the slot counts — pin them so drift is loud.
        #expect(cards.first { $0.type == .relationship }?.countText == "7 questions")
        #expect(cards.first { $0.type == .family }?.countText == "6 questions")
        #expect(cards.first { $0.type == .money }?.countText == "4 questions")
    }

    /// Every non-sensitive type's question bank covers its full schema — a missing slot would
    /// silently shrink the sequence.
    @Test func sequenceCoversEverySlot() {
        for type in ChapterType.allCases {
            let nodes = ChapterSequenceScript.nodes(for: type)
            let slots = AwarenessSchema.slots(for: type)
            #expect(nodes.count == slots.count, "\(type) sequence missing questions")
            let coveredSlots = nodes.map { ChapterSequenceScript.slot(ofNodeId: $0.id) }
            #expect(coveredSlots == slots)
            // Every sequence question is skippable — "you can stop anytime" is structural.
            let allSkippable = nodes.allSatisfy(\.skippable)
            #expect(allSkippable, "\(type) has a non-skippable sequence question")
        }
    }

    /// Already-filled slots are never re-asked (the provider's filledSlots gate).
    @Test func filledSlotsAreNeverReAsked() {
        let script = ChapterSequenceScript(type: .health, chapterId: UUID())
        let first = script.nextNode(answers: [:], filledSlots: ["focusAreas"])
        #expect(ChapterSequenceScript.slot(ofNodeId: first!.id) == "routines")
    }

    // The M3 "done" check: begin → answer → flush through the real pipeline → the chapter is on
    // the world with a correct ring.
    @Test func sequenceBuildsARoomWithACorrectRing() async throws {
        let store = try makeStore()
        let extraction = ScriptedSequenceExtraction(envelopeByUtterance: [
            "Sleep, mostly. And stress.": Self.slotEnvelope("focusAreas"),
            "Trying to run three times a week.": Self.slotEnvelope("routines"),
            "Waking up rested, honestly.": Self.slotEnvelope("goals"),
        ])
        let model = NewChapterModel(store: store, extraction: extraction)

        model.selectedType = .health
        model.begin()
        #expect(model.phase == .sequence)
        let chapterId = try #require(model.chapterId)

        // The pin exists from Begin (typed command) — visible on the globe at 0%.
        let atBegin = try store.chapterSummaries()
        #expect(atBegin.contains { $0.id == chapterId && $0.awarenessPct == 0 })

        // Answer 3, skip 2 — answers queue (C1), nothing merges until the flush.
        await model.submitText("Sleep, mostly. And stress.")
        await model.submitText("Trying to run three times a week.")
        #expect(try store.pendingUtterances().count == 2)
        model.skip()  // currentState
        await model.submitText("Waking up rested, honestly.")
        model.skip()  // openIssues — last node: engine completes, the flush runs

        // Wait for the async finish kicked off by the final skip.
        for _ in 0..<100 where model.phase != .done {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.phase == .done)
        #expect(!model.flushLagged)
        #expect(try store.pendingUtterances().isEmpty)

        // 3 of 5 slots → 60%, computed at merge (C6) — the ring grades .gaining on the globe.
        let summaries = try store.chapterSummaries()
        let summary = try #require(summaries.first { $0.id == chapterId })
        #expect(summary.awarenessPct == 60)
        let tokens = ThemeModel(theme: .cloudCream).tokens
        let pins = WorldModel.buildPins(
            chapters: summaries, upcoming: [], tokens: tokens,
            now: .now, calendar: .current
        )
        let pin = try #require(pins.first { $0.id == chapterId })
        #expect(pin.grade == .gaining)
        #expect(pin.pin.sublineText == "needs a bit more · 60%")
    }

    /// "That's enough for now" ends early — whatever was answered is kept and flushed.
    @Test func stopEarlyKeepsWhatWasGiven() async throws {
        let store = try makeStore()
        let extraction = ScriptedSequenceExtraction(envelopeByUtterance: [
            "Just how it stands.": Self.slotEnvelope("situation"),
        ])
        let model = NewChapterModel(store: store, extraction: extraction)
        model.selectedType = .money
        model.begin()
        await model.submitText("Just how it stands.")
        await model.stopEarly()

        #expect(model.phase == .done)
        let summaries = try store.chapterSummaries()
        let summary = try #require(summaries.first { $0.id == model.chapterId })
        #expect(summary.awarenessPct == 25)  // 1 of 4, computed at merge
    }

    /// A failed extraction keeps rows queued and says so honestly — filing lags, never drops.
    @Test func failedFlushKeepsRowsAndFlagsLag() async throws {
        let store = try makeStore()
        let model = NewChapterModel(
            store: store,
            extraction: ScriptedSequenceExtraction(envelopeByUtterance: [:])  // everything fails
        )
        model.selectedType = .passion
        model.begin()
        await model.submitText("Painting, badly and happily.")
        await model.stopEarly()
        #expect(model.phase == .done)
        #expect(model.flushLagged)
        #expect(try store.pendingUtterances().count == 1)  // kept for retry, not dropped (NN#7)
    }
}
