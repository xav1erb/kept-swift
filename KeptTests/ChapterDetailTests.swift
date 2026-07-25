import CryptoKit
import Foundation
import Testing
@testable import Kept

// M4-CONTRACTS §8: the chat turn (two independent paths, §10.1), the prep stage machine (§5),
// receipt grounding, the timeline node grammar (§7), the never-tests, and chat history through
// the E2E backup (§10.3). Scripted proxies, real decode, real merge — fake the source, never
// the shape.

@MainActor
struct ChapterDetailTests {

    // MARK: - Fakes (source only — the real decoders and validators always run)

    /// Chat proxy fake with switchable behavior (the FakeBackend pattern): tests swap `respond`
    /// mid-scenario to script failure-then-recovery. $TURN_ID substituted from the request.
    final class SwitchableChat: ChatServicing, @unchecked Sendable {
        var respond: (ChatRequest) throws -> String

        init(respond: @escaping (ChatRequest) throws -> String = { _ in
            throw ChatError.upstreamUnavailable
        }) {
            self.respond = respond
        }

        func send(_ request: ChatRequest) async throws -> ChatEnvelope {
            let json = try respond(request)
                .replacingOccurrences(of: "$TURN_ID", with: request.turnId.uuidString)
            return try JSONDecoder().decode(ChatEnvelope.self, from: Data(json.utf8))
        }
    }

    /// Extraction fake: a valid empty envelope for ANY utterance — filing succeeds, nothing
    /// merges. Used where the chat reply is the thing under test.
    nonisolated struct EmptyExtraction: ExtractionServicing {
        func extract(_ request: ExtractionRequest) async throws -> ExtractionEnvelope {
            let json = """
            {"schemaVersion": 1, "utteranceId": "\(request.utteranceId.uuidString)", "deltas": [], "disambiguations": []}
            """
            return try JSONDecoder().decode(ExtractionEnvelope.self, from: Data(json.utf8))
        }
    }

    nonisolated struct FailingExtraction: ExtractionServicing {
        func extract(_ request: ExtractionRequest) async throws -> ExtractionEnvelope {
            throw ExtractionError.upstreamUnavailable
        }
    }

    /// Extraction fake that records the context it was sent (for the open-chapter-first test).
    final class RecordingExtraction: ExtractionServicing, @unchecked Sendable {
        var sentContexts: [ExtractionContext] = []

        func extract(_ request: ExtractionRequest) async throws -> ExtractionEnvelope {
            sentContexts.append(request.context)
            let json = """
            {"schemaVersion": 1, "utteranceId": "\(request.utteranceId.uuidString)", "deltas": [], "disambiguations": []}
            """
            return try JSONDecoder().decode(ExtractionEnvelope.self, from: Data(json.utf8))
        }
    }

    // MARK: - Seeding (fx-001-shaped: Daniel, the Jul 6 promise, positives, the pinned talk)

    struct Seed {
        let store: KeptStore
        let chapterId: UUID
        let commitmentId: UUID
        let lisbonId: UUID
        let talkId: UUID
        let stormId: UUID
    }

    private func makeSeed() throws -> Seed {
        let store = try KeptStore(configuration: .inMemory)
        try store.setUserName("Maya")
        try store.grantAIConsent()
        try store.completeOnboarding()
        // An older sibling chapter so "listed first" is a real reordering, not a coincidence.
        try store.createChapter(type: .health, chapterKind: .dimension, title: "Health", iconRef: "leaf.fill")
        let chapterId = try store.createChapter(
            type: .relationship, chapterKind: .dimension, title: "Daniel", iconRef: "heart.fill"
        )
        let personId = try store.addPerson(name: "Daniel", relation: "boyfriend")
        try store.attach(personId: personId, toChapter: chapterId)
        let commitmentId = try store.addCommitment(
            chapterId: chapterId, personId: personId, text: "no following girls",
            dateMade: Date(timeIntervalSince1970: 1_783_728_000) // 2026-07-06 UTC
        )
        let lisbonId = try store.addEvent(
            chapterId: chapterId, date: Date(timeIntervalSince1970: 1_778_800_000),
            title: "Lisbon", body: "The best weekend.", valence: .gold,
            isOpen: false, isUpcoming: false, source: .onboarding
        )
        let stormId = try store.addEvent(
            chapterId: chapterId, date: Date(timeIntervalSince1970: 1_784_600_000),
            title: "The credit thing", body: "Second time.", valence: .storm,
            isOpen: true, isUpcoming: false, source: .chat
        )
        let talkId = try store.addEvent(
            chapterId: chapterId, date: Date.now.addingTimeInterval(6 * 3600),
            title: "The talk", body: "", valence: .neutral,
            isOpen: true, isUpcoming: true, source: .chat
        )
        return Seed(
            store: store, chapterId: chapterId, commitmentId: commitmentId,
            lisbonId: lisbonId, talkId: talkId, stormId: stormId
        )
    }

    private func makeModel(_ seed: Seed, chat: any ChatServicing, extraction: any ExtractionServicing) -> ChapterDetailModel {
        let model = ChapterDetailModel(
            chapterId: seed.chapterId, store: seed.store, chat: chat, extraction: extraction
        )
        model.refresh()
        return model
    }

    // MARK: - §8.1 the chat turn: durable filing + ephemeral reply, independent

    @Test func chatTurnFilesAndReplies() async throws {
        let seed = try makeSeed()
        let chat = SwitchableChat { _ in
            """
            {"schemaVersion": 1, "turnId": "$TURN_ID", "text": "I hear you. That promise is on record — July 6.",
             "chips": ["practice it with me", "what if he gets defensive?"]}
            """
        }
        let extraction = RecordingExtraction()
        let model = makeModel(seed, chat: chat, extraction: extraction)

        await model.send("he did it again last night")

        #expect(model.messages.count == 2)
        #expect(model.messages.first?.author == .user)
        #expect(model.messages.last?.author == .pom)
        #expect(model.messages.last?.text.contains("July 6") == true)
        #expect(model.chips == ["practice it with me", "what if he gets defensive?"])
        #expect(model.replyFailed == false)
        #expect(model.filingLagged == false)
        // The queue drained through the real pipeline...
        #expect(try seed.store.pendingUtterances().isEmpty)
        // ...and the open chapter was listed FIRST in extraction context (M4 §2 amendment),
        // even though an older chapter exists.
        let sent = try #require(extraction.sentContexts.first)
        #expect(sent.chapters.first?.id == seed.chapterId)
        #expect(sent.chapters.count == 2)
    }

    @Test func replyFailureKeepsWordsAndQueueThenRetryRecovers() async throws {
        let seed = try makeSeed()
        let chat = SwitchableChat() // throws by default
        let model = makeModel(seed, chat: chat, extraction: FailingExtraction())

        await model.send("I'm scared about tonight")

        // Both paths failed — nothing lost: the bubble is kept AND the utterance row survives.
        #expect(model.replyFailed)
        #expect(model.filingLagged)
        #expect(model.messages.count == 1)
        #expect(try seed.store.pendingUtterances().count == 1)

        // Retry re-sends ONLY the reply call; the transcript gains just Pom's answer.
        chat.respond = { _ in
            """
            {"schemaVersion": 1, "turnId": "$TURN_ID", "text": "I'm right here.", "chips": []}
            """
        }
        await model.retryReply()
        #expect(model.replyFailed == false)
        #expect(model.messages.count == 2)
        #expect(model.messages.last?.text == "I'm right here.")
        // Filing still lags (extraction is still down) — honest, kept, retryable.
        #expect(try seed.store.pendingUtterances().count == 1)
    }

    // MARK: - §8.2/§8.3 the prep walk (all five cards, receipts grounded, arming)

    @Test func prepWalkRendersAllComponentsAndArms() async throws {
        let seed = try makeSeed()
        let chat = SwitchableChat { request in
            guard case .prep(let stage) = request.mode else {
                throw ChatError.envelopeRejected(reason: "expected prep mode")
            }
            let commitmentId = request.context.commitments.first { $0.text == "no following girls" }!.id
            let lisbonId = request.context.events.first { $0.title == "Lisbon" }!.id
            let card: String
            switch stage {
            case .reframe:
                card = """
                {"kind": "reframe", "goal": "You're not going in to win — you're going in to be clear.",
                 "receipts": [{"id": "\(commitmentId.uuidString)", "note": "made on July 6 — it's on record"}]}
                """
            case .likelyAnswers:
                card = """
                {"kind": "likelyAnswers", "answers": [
                  {"theirLine": "I was just looking.", "read": "minimizing", "counter": "It's the promise that matters."},
                  {"theirLine": "You're overreacting.", "read": "turning it around", "counter": "I'm asking calmly."}
                ]}
                """
            case .perspective:
                card = """
                {"kind": "perspective", "incidentRead": "One incident, small on its own.",
                 "patternRead": "Second time since the promise.",
                 "signals": [{"text": "a promise made and repeated", "present": true},
                             {"text": "hiding it when asked", "present": false}],
                 "grounding": "Tonight is about the pattern, not the person."}
                """
            case .keepCard:
                card = """
                {"kind": "keepCard", "items": [{"id": "\(lisbonId.uuidString)", "note": "the best weekend"}],
                 "closingLine": "This talk is about protecting that, not putting it on trial."}
                """
            case .openingClose:
                card = """
                {"kind": "openingClose", "opening": "I want to talk about the promise, because it matters to me.",
                 "close": "Then let him talk. I'll check on you after. 🤍"}
                """
            }
            return """
            {"schemaVersion": 1, "turnId": "$TURN_ID", "text": "lead-in", "card": \(card), "chips": []}
            """
        }
        let model = makeModel(seed, chat: chat, extraction: EmptyExtraction())

        #expect(model.canOfferPrep)
        await model.startPrep()                       // → reframe
        #expect(model.prepStage == .likelyAnswers)
        await model.advancePrep()                     // → likelyAnswers
        #expect(model.prepStage == .keepCard)
        await model.askPerspective()                  // detour, files the question too
        #expect(model.prepStage == .keepCard)         // returned where it left off
        await model.advancePrep()                     // → keepCard
        #expect(model.prepStage == .openingClose)
        await model.advancePrep()                     // → openingClose, completes + arms
        #expect(model.prepStage == nil)

        // All five designed components arrived, typed, in order (the ROADMAP done-bar).
        let stages = model.messages.compactMap { $0.card?.stage }
        #expect(stages == [.reframe, .likelyAnswers, .perspective, .keepCard, .openingClose])

        // Receipts resolve against the STORE — title/date come from the record.
        let reframe = try #require(model.messages.compactMap(\.card).first)
        let receipt = try #require(reframe.receiptRefs.first)
        let display = try #require(model.receiptDisplay(receipt.id))
        #expect(display.title == "\u{201C}no following girls\u{201D}")

        // The openingClose card armed the linked upcoming event (§5).
        let talk = try #require(model.events.first { $0.id == seed.talkId })
        #expect(talk.preparedAt != nil)
        #expect(talk.checkInArmed)
        #expect(TimelineNode.node(for: talk, now: .now, calendar: .current)
            == .upcoming(talk, prepped: true))

        // ...and the World's Next-up card sees it (M3 §4 fields go live).
        let nextUp = WorldModel.selectNextUp(
            events: try seed.store.upcomingEvents(),
            chapters: try seed.store.chapterSummaries(),
            now: .now, calendar: .current
        )
        #expect(nextUp?.prepArmed == true)
        #expect(nextUp?.checkInArmed == true)
    }

    @Test func inventedReceiptRejectsTheEnvelope() async throws {
        let seed = try makeSeed()
        let chat = SwitchableChat { _ in
            """
            {"schemaVersion": 1, "turnId": "$TURN_ID", "text": "lead-in",
             "card": {"kind": "reframe", "goal": "g", "receipts": [{"id": "\(UUID().uuidString)", "note": "invented"}]},
             "chips": []}
            """
        }
        let model = makeModel(seed, chat: chat, extraction: EmptyExtraction())
        await model.startPrep()
        // The invented receipt is structurally unrenderable — the whole envelope is rejected.
        #expect(model.replyFailed)
        #expect(model.messages.compactMap(\.card).isEmpty)
        #expect(model.prepStage == .reframe) // the stage machine did not advance
    }

    // MARK: - §8.2 wire validation (strict decode, loud rejection)

    @Test func hostileEnvelopesAreRejected() throws {
        func decode(_ json: String) throws -> ChatEnvelope {
            try JSONDecoder().decode(ChatEnvelope.self, from: Data(json.utf8))
        }
        let turnId = UUID()
        let head = #""schemaVersion": 1, "turnId": "\#(turnId.uuidString)", "text": "t""#

        // >3 chips — the softness cap holds at the decode boundary.
        #expect(throws: (any Error).self) {
            _ = try decode(#"{\#(head), "chips": ["a", "b", "c", "d"]}"#)
        }
        // likelyAnswers outside 2–4.
        #expect(throws: (any Error).self) {
            _ = try decode(#"{\#(head), "card": {"kind": "likelyAnswers", "answers": [{"theirLine": "x", "read": "y", "counter": "z"}]}}"#)
        }
        // Unknown card kind.
        #expect(throws: (any Error).self) {
            _ = try decode(#"{\#(head), "card": {"kind": "verdict", "value": "leave him"}}"#)
        }

        // Stage-lock: a reframe card against a keepCard request is rejected...
        let context = ChatContext(
            userName: "Maya",
            chapter: .init(id: UUID(), type: .relationship, title: "Daniel", state: .tense, awarenessPct: 50, filledSlots: []),
            people: [], events: [], commitments: [], goals: [], crossLinks: []
        )
        let valid = try decode(
            #"{\#(head), "card": {"kind": "reframe", "goal": "g", "receipts": []}, "chips": []}"#
        )
        func request(mode: ChatMode, turnId: UUID) -> ChatRequest {
            ChatRequest(
                turnId: turnId, chapterId: UUID(), mode: mode, clientTime: .now,
                locale: "en", userText: nil, history: [], context: context
            )
        }
        #expect(throws: (any Error).self) {
            _ = try valid.validated(for: request(mode: .prep(stage: .keepCard), turnId: turnId))
        }
        // ...a card outside prep mode is rejected...
        #expect(throws: (any Error).self) {
            _ = try valid.validated(for: request(mode: .chat, turnId: turnId))
        }
        // ...a mis-echoed turnId is rejected...
        #expect(throws: (any Error).self) {
            _ = try valid.validated(for: request(mode: .prep(stage: .reframe), turnId: UUID()))
        }
        // ...and the honest case passes.
        let accepted = try valid.validated(for: request(mode: .prep(stage: .reframe), turnId: turnId))
        #expect(accepted.card?.stage == .reframe)
    }

    // MARK: - §8.4/§8.5 timeline grammar (typed, only the open storm pulses, fold overrides all)

    private func snapshot(
        valence: Valence, isOpen: Bool = false, isHealed: Bool = false,
        isUpcoming: Bool = false, date: Date = .init(timeIntervalSince1970: 1_752_000_000),
        preparedAt: Date? = nil
    ) -> EventSnapshot {
        EventSnapshot(
            id: UUID(), chapterId: UUID(), date: date, title: "t", body: "b",
            valence: valence, isOpen: isOpen, isHealed: isHealed,
            healedReason: isHealed ? "forgiven" : nil, isUpcoming: isUpcoming,
            source: .chat, preparedAt: preparedAt, checkInArmed: false
        )
    }

    @Test func timelineGrammarGoldens() {
        let now = Date(timeIntervalSince1970: 1_784_800_000)
        let calendar = Calendar.current
        func node(_ event: EventSnapshot) -> TimelineNode {
            TimelineNode.node(for: event, now: now, calendar: calendar)
        }

        let folded = snapshot(valence: .storm, isHealed: true)
        let openStorm = snapshot(valence: .storm, isOpen: true)
        let calmStorm = snapshot(valence: .storm, isOpen: false)
        let upcoming = snapshot(valence: .neutral, isUpcoming: true, date: now.addingTimeInterval(3600))
        let bright = snapshot(valence: .bright)
        let gold = snapshot(valence: .gold)
        let neutral = snapshot(valence: .neutral)
        let soft = snapshot(valence: .soft)

        #expect(node(folded) == .folded(folded))
        #expect(node(openStorm) == .openStorm(openStorm))
        #expect(node(calmStorm) == .calmReceipt(calmStorm))
        #expect(node(upcoming) == .upcoming(upcoming, prepped: false))
        #expect(node(bright) == .bright(bright))
        #expect(node(gold) == .bright(gold))
        #expect(node(neutral) == .receipt(neutral))
        #expect(node(soft) == .gentle(soft))

        // The §19 never-rule: the open storm is the ONLY pulsing node.
        let all = [folded, openStorm, calmStorm, upcoming, bright, gold, neutral, soft]
        let pulsing = all.map(node).filter(\.pulses)
        #expect(pulsing == [.openStorm(openStorm)])
    }

    @Test func foldOverridesEverythingAndNeverPulses() {
        let now = Date(timeIntervalSince1970: 1_784_800_000)
        // A healed event ALWAYS renders folded — even an open, upcoming storm. Expansion has no
        // store field and no node case: every fresh construction leads folded (structural refold).
        for valence in [Valence.bright, .gold, .neutral, .storm, .soft] {
            for isOpen in [true, false] {
                for isUpcoming in [true, false] {
                    let event = snapshot(
                        valence: valence, isOpen: isOpen, isHealed: true,
                        isUpcoming: isUpcoming, date: now.addingTimeInterval(3600)
                    )
                    let node = TimelineNode.node(for: event, now: now, calendar: .current)
                    #expect(node == .folded(event))
                    #expect(!node.pulses)
                }
            }
        }
    }

    // MARK: - §8.6 context: folded travels flagged; the record reaches /chat whole

    @Test func chatContextCarriesTheWholeRoomWithFoldedFlagged() async throws {
        let seed = try makeSeed()
        // Fold the storm through the REAL pipeline (foldEvent is merge-only — no store command).
        let sent = try seed.store.extractionContext()
        let foldJSON = """
        {"schemaVersion": 1, "utteranceId": "\(UUID().uuidString)", "disambiguations": [], "deltas": [
          {"kind": "foldEvent", "eventId": "\(seed.stormId.uuidString)", "reason": "we talked it through, I forgave it"}
        ]}
        """
        let envelope = try JSONDecoder().decode(ExtractionEnvelope.self, from: Data(foldJSON.utf8))
        _ = try seed.store.applyExtraction(
            envelope, sentContext: sent, surface: .chapterChat, clientTime: .now
        )

        let context = try seed.store.chatContext(chapterId: seed.chapterId)
        #expect(context.userName == "Maya")
        #expect(context.chapter.id == seed.chapterId)
        #expect(context.people.map(\.name) == ["Daniel"])
        #expect(context.commitments.map(\.text) == ["no following girls"])
        let foldedEvent = try #require(context.events.first { $0.id == seed.stormId })
        #expect(foldedEvent.isHealed)
        #expect(foldedEvent.healedReason == "we talked it through, I forgave it")
        // One chapter only — minimum-necessary (the Health chapter's record never travels).
        #expect(context.events.count == 3)
        #expect(context.crossLinks.isEmpty)
    }

    // MARK: - §8.7 the copy bank holds no guilt (C3)

    @Test func detailCopyBankHasNoGuiltStrings() {
        let forbidden = [
            "we miss you", "miss you", "come back", "don't forget", "you haven't",
            "overdue", "at risk", "last chance", "streak is about to",
        ]
        for line in ChapterDetailCopy.all {
            for phrase in forbidden {
                #expect(!line.lowercased().contains(phrase), "guilt copy in detail bank: \(phrase)")
            }
        }
    }

    // MARK: - §8 header: a typed template over store fields, no model text

    @Test func headerStatusIsATypedTemplate() throws {
        let seed = try makeSeed()
        let chat = SwitchableChat()
        let model = makeModel(seed, chat: chat, extraction: EmptyExtraction())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")

        let now = Date.now
        let status = model.headerStatus(now: now, calendar: calendar)
        let summary = try #require(model.summary)
        let since = summary.createdAt.formatted(.dateTime.month(.abbreviated).year())
        #expect(status.hasPrefix("relationship · since \(since)"))
        #expect(status.hasSuffix("The talk · \(WorldModel.relativeDay(from: now, to: model.events.first { $0.id == seed.talkId }!.date, calendar: calendar))"))
    }

    // MARK: - §10.3 chat history joins the E2E backup (additive tag, restore rebuilds)

    @Test func chatHistorySurvivesSealAndRestore() async throws {
        let seed = try makeSeed()
        try seed.store.markPrepared(eventId: seed.talkId)
        try seed.store.armPostEventCheckIn(eventId: seed.talkId)
        try seed.store.appendChatMessage(
            chapterId: seed.chapterId, author: .user, text: "he did it again"
        )
        try seed.store.appendChatMessage(
            chapterId: seed.chapterId, author: .pom, text: "kept. and the promise is on record.",
            card: .reframe(goal: "be clear", receipts: [
                ReceiptRef(id: seed.commitmentId, note: "July 6"),
            ])
        )

        let key = SymmetricKey(size: .bits256)
        let blobs = try seed.store.sealAllRecords(key: key)
        let restored = try KeptStore(configuration: .inMemory)
        try restored.restore(interiors: blobs.map { blob in
            let opened = try BlobEnvelope.open(blob, key: key)
            return (type: opened.type, interior: opened.interior)
        })

        let original = try seed.store.chatMessages(inChapter: seed.chapterId)
        let rebuilt = try restored.chatMessages(inChapter: seed.chapterId)
        #expect(original.count == 2)
        #expect(rebuilt == original)
        #expect(rebuilt.last?.card?.receiptRefs.first?.id == seed.commitmentId)

        // The arming fields ride the event blob (M6's contract surface survives a new phone).
        let talk = try #require(try restored.events(inChapter: seed.chapterId).first { $0.id == seed.talkId })
        #expect(talk.preparedAt != nil)
        #expect(talk.checkInArmed)
    }
}
