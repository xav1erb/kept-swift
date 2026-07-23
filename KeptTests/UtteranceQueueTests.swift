import Foundation
import Testing
@testable import Kept

// M2-CONTRACTS §9.3 + the §8.1 flush: the queue refuses pre-consent (the ONLY path content
// takes toward the network during onboarding — the structural §13.2 gate), flushes FIFO through
// the real M1 pipeline, replays idempotently after a crash mid-flush, and keeps failed rows.

/// Scripted fake proxy: envelope JSON per utterance text, `$UTTERANCE_ID` substituted from the
/// request — the same real decode + merge path as production (fake the source, never the shape).
nonisolated struct ScriptedExtraction: ExtractionServicing {
    let envelopeByUtterance: [String: String]

    func extract(_ request: ExtractionRequest) async throws -> ExtractionEnvelope {
        guard let template = envelopeByUtterance[request.utterance] else {
            throw ExtractionError.upstreamUnavailable
        }
        let json = template.replacingOccurrences(of: "$UTTERANCE_ID", with: request.utteranceId.uuidString)
        return try JSONDecoder().decode(ExtractionEnvelope.self, from: Data(json.utf8))
    }
}

@MainActor
struct UtteranceQueueTests {

    private static let familyEnvelope = """
    {"schemaVersion": 1, "utteranceId": "$UTTERANCE_ID", "disambiguations": [], "deltas": [
      {"kind": "upsertChapter", "ref": "c1", "type": "family", "chapterKind": "dimension", "title": "Mom & Lena"},
      {"kind": "upsertPerson", "ref": "p1", "name": "Lena", "relation": "sister", "chapterRefs": [{"ref": "c1"}]},
      {"kind": "fillSlots", "chapterRef": {"ref": "c1"}, "slots": ["keyPeople", "dynamics"]}
    ]}
    """

    private static let moneyEnvelope = """
    {"schemaVersion": 1, "utteranceId": "$UTTERANCE_ID", "disambiguations": [], "deltas": [
      {"kind": "upsertChapter", "ref": "c1", "type": "money", "chapterKind": "dimension", "title": "The move fund"},
      {"kind": "upsertGoal", "ref": "g1", "chapterRef": {"ref": "c1"}, "text": "€6,000 saved for the move"},
      {"kind": "fillSlots", "chapterRef": {"ref": "c1"}, "slots": ["situation", "goals"]}
    ]}
    """

    @Test func queueRefusesPreConsent() throws {
        let store = try KeptStore(configuration: .inMemory)
        #expect(throws: KeptStore.StoreError.self) {
            try store.enqueueUtterance(surface: .onboarding, nodeId: "q6-positive", text: "hello")
        }
        #expect(try store.pendingUtterances().isEmpty)
    }

    @Test func flushAppliesFIFOThroughTheRealPipeline() async throws {
        let store = try KeptStore(configuration: .inMemory)
        try store.grantAIConsent()
        try store.enqueueUtterance(surface: .onboarding, nodeId: "q7-family", text: "family stuff")
        try store.enqueueUtterance(surface: .onboarding, nodeId: "q7-money", text: "money stuff")

        let flusher = UtteranceFlusher(store: store, extraction: ScriptedExtraction(envelopeByUtterance: [
            "family stuff": Self.familyEnvelope,
            "money stuff": Self.moneyEnvelope,
        ]))
        let result = await flusher.flush()

        #expect(result.summaries.count == 2)
        #expect(result.failedUtteranceIds.isEmpty)
        #expect(result.pendingQuestions.isEmpty)
        #expect(try store.pendingUtterances().isEmpty)  // removed only after application

        let chapters = try store.chapterSummaries()
        #expect(chapters.map(\.type) == [.family, .money])  // FIFO: family filed first
        #expect(chapters.map(\.title) == ["Mom & Lena", "The move fund"])
        #expect(chapters[0].awarenessPct == 33)  // 2 of 6 family slots
        #expect(chapters[1].awarenessPct == 50)  // 2 of 4 money slots
        let goals = try store.goals()
        #expect(goals.map(\.text) == ["€6,000 saved for the move"])
    }

    @Test func crashMidFlushReplaysAsNoOp() async throws {
        let store = try KeptStore(configuration: .inMemory)
        try store.grantAIConsent()
        try store.enqueueUtterance(surface: .onboarding, nodeId: "q7-family", text: "family stuff")

        let extraction = ScriptedExtraction(envelopeByUtterance: ["family stuff": Self.familyEnvelope])
        let pending = try #require(try store.pendingUtterances().first)

        // Simulate the crash window: the envelope APPLIED but the queue row survived.
        let request = ExtractionRequest(
            utteranceId: pending.utteranceId, surface: .onboarding, clientTime: pending.clientTime,
            locale: "en", utterance: pending.text, context: try store.extractionContext()
        )
        let envelope = try await extraction.extract(request)
        _ = try store.applyExtraction(
            envelope, sentContext: try store.extractionContext(),
            surface: .onboarding, clientTime: pending.clientTime
        )
        #expect(try store.chapterSummaries().count == 1)

        // The retry flush replays through the AppliedUtterance gate: no duplicate world.
        let flusher = UtteranceFlusher(store: store, extraction: extraction)
        let result = await flusher.flush()
        #expect(result.summaries.first?.wasAlreadyApplied == true)
        #expect(try store.pendingUtterances().isEmpty)
        #expect(try store.chapterSummaries().count == 1)
        #expect(try store.people().count == 1)
    }

    @Test func failedExtractionKeepsTheRowQueued() async throws {
        let store = try KeptStore(configuration: .inMemory)
        try store.grantAIConsent()
        try store.enqueueUtterance(surface: .onboarding, nodeId: "q7-family", text: "family stuff")
        try store.enqueueUtterance(surface: .onboarding, nodeId: "q7-money", text: "money stuff")

        // Only the money envelope is scripted — the family call fails (proxy down).
        let flusher = UtteranceFlusher(store: store, extraction: ScriptedExtraction(envelopeByUtterance: [
            "money stuff": Self.moneyEnvelope
        ]))
        let result = await flusher.flush()

        #expect(result.summaries.count == 1)
        #expect(result.failedUtteranceIds.count == 1)
        let remaining = try store.pendingUtterances()
        #expect(remaining.map(\.text) == ["family stuff"])  // kept for retry — never dropped (NN#7)
        #expect(try store.chapterSummaries().map(\.type) == [.money])
    }

    @Test func queuePersistsInTheStore() throws {
        // Same-store persistence shape (true relaunch is the §9.7 device checklist).
        let store = try KeptStore(configuration: .inMemory)
        try store.grantAIConsent()
        let id = try store.enqueueUtterance(surface: .onboarding, nodeId: "q6-positive", text: "the good part")
        let rows = try store.pendingUtterances()
        #expect(rows.map(\.utteranceId) == [id])
        #expect(rows.first?.surfaceRaw == "onboarding")
    }
}
