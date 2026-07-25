import Foundation
import Testing
@testable import Kept

// M5-CONTRACTS §6: the vent turn (capture-first, typed confirmation), the disambiguation
// surface, the typed smart prompt, structural freshness, F9 mic gating, and the VoiceCapture
// never-network scan. Scripted proxies, real decode, real merge.

@MainActor
struct TellPomTests {

    // MARK: - Fakes

    final class ScriptedVentExtraction: ExtractionServicing, @unchecked Sendable {
        var respond: (ExtractionRequest) throws -> String

        init(respond: @escaping (ExtractionRequest) throws -> String = { _ in
            throw ExtractionError.upstreamUnavailable
        }) {
            self.respond = respond
        }

        func extract(_ request: ExtractionRequest) async throws -> ExtractionEnvelope {
            let json = try respond(request)
                .replacingOccurrences(of: "$UTTERANCE_ID", with: request.utteranceId.uuidString)
            return try JSONDecoder().decode(ExtractionEnvelope.self, from: Data(json.utf8))
        }
    }

    final class FakeSpeechCapture: SpeechCapturing, @unchecked Sendable {
        var scriptedAvailability: SpeechAvailability
        var partials: [String]
        var finalTranscript: String
        var permissionsGranted = true

        init(
            availability: SpeechAvailability = SpeechAvailability(onDeviceSupported: true, permissionDenied: false),
            partials: [String] = [],
            finalTranscript: String = ""
        ) {
            self.scriptedAvailability = availability
            self.partials = partials
            self.finalTranscript = finalTranscript
        }

        func availability(locale: Locale) async -> SpeechAvailability { scriptedAvailability }
        func requestPermissions() async -> Bool { permissionsGranted }
        func startCapture(partial: @escaping @Sendable (String) -> Void) async throws {
            for text in partials { partial(text) }
        }
        func stopCapture() async -> String { finalTranscript }
        func cancelCapture() async {}
    }

    // MARK: - Seeding

    struct Seed {
        let store: KeptStore
        let momId: UUID
        let workId: UUID
        let moneyId: UUID
    }

    private func makeSeed() throws -> Seed {
        let store = try KeptStore(configuration: .inMemory)
        try store.setUserName("Maya")
        try store.grantAIConsent()
        try store.completeOnboarding()
        let momId = try store.createChapter(type: .family, chapterKind: .dimension, title: "Mom", iconRef: "house.fill")
        let workId = try store.createChapter(type: .work, chapterKind: .dimension, title: "Work", iconRef: "briefcase.fill")
        let moneyId = try store.createChapter(type: .money, chapterKind: .dimension, title: "Money", iconRef: "banknote")
        return Seed(store: store, momId: momId, workId: workId, moneyId: moneyId)
    }

    private func threeTopicEnvelope(for request: ExtractionRequest) -> String {
        let ids = request.context.chapters.map(\.id.uuidString)
        let events = ids.enumerated().map { index, id in
            """
            {"kind": "addEvent", "ref": "e\(index)", "chapterRef": {"id": "\(id)"},
             "datePrecision": "unknown", "title": "Topic \(index)", "body": "kept",
             "valence": "soft", "isOpen": false, "isUpcoming": false}
            """
        }.joined(separator: ",")
        return """
        {"schemaVersion": 1, "utteranceId": "$UTTERANCE_ID", "disambiguations": [], "deltas": [\(events)]}
        """
    }

    // MARK: - §6.1 the done-bar vent: three topics file to three chapters, and Pom says so

    @Test func threeTopicVentFilesAndConfirms() async throws {
        let seed = try makeSeed()
        let extraction = ScriptedVentExtraction { [self] in threeTopicEnvelope(for: $0) }
        let model = VentModel(store: seed.store, extraction: extraction, speech: FakeSpeechCapture())
        await model.start()

        await model.send("mom called, work was a mess, and I moved money into savings")

        #expect(try seed.store.pendingUtterances().isEmpty)
        let confirmations = model.items.compactMap { item -> (String, [VentModel.FilingChip])? in
            if case .confirmation(_, let line, let chips) = item { return (line, chips) }
            return nil
        }
        #expect(confirmations.count == 1)
        let (line, chips) = try #require(confirmations.first)
        // Exactly the three touched chapters — no 4th write, no invented room (fx-003 law).
        #expect(Set(chips.map(\.title)) == ["Mom", "Work", "Money"])
        #expect(chips.count == 3)
        #expect(line.hasPrefix(VentCopy.filedPrefix))
        #expect(line.hasSuffix(VentCopy.filedSuffix))
        // Every chip is a real deep-link target.
        for chip in chips {
            let router = Router()
            #expect(router.open(deepLink: URL(string: "kept://chapter/\(chip.chapterId.uuidString)")!))
            #expect(router.path == [.chapter(chip.chapterId)])
        }
    }

    // MARK: - §6.2 two Saras through the surface (the C4 gate's UI)

    @Test func twoSarasRaiseAQuestionCardAndResolutionApplies() async throws {
        let seed = try makeSeed()
        let sara1 = try seed.store.addPerson(name: "Sara", relation: "colleague")
        let sara2 = try seed.store.addPerson(name: "Sara", relation: "friend")
        let extraction = ScriptedVentExtraction { _ in
            """
            {"schemaVersion": 1, "utteranceId": "$UTTERANCE_ID",
             "disambiguations": [{"ref": "p1", "mention": "Sara",
               "candidateIds": ["\(sara1.uuidString)", "\(sara2.uuidString)"],
               "question": "work-Sara, not Instagram-Sara, right?"}],
             "deltas": [{"kind": "upsertPerson", "ref": "p1", "name": "Sara", "notesAppend": "saved me today"}]}
            """
        }
        let model = VentModel(store: seed.store, extraction: extraction, speech: FakeSpeechCapture())
        await model.start()

        await model.send("Sara totally saved me today")

        let question = try #require(model.items.compactMap { item -> (UUID, String, [VentModel.QuestionOption])? in
            if case .question(let id, let prompt, let options) = item { return (id, prompt, options) }
            return nil
        }.first)
        #expect(question.1 == "work-Sara, not Instagram-Sara, right?")
        #expect(question.2.map(\.label) == ["Sara · colleague", "Sara · friend", VentCopy.someoneNew])

        await model.resolveQuestion(batchId: question.0, resolution: .existing(sara1))

        // The card is gone, the batch is drained, and the held delta landed on the RIGHT Sara.
        #expect(!model.items.contains { $0.id == question.0 })
        #expect(try seed.store.pendingDisambiguations().isEmpty)
        let people = try seed.store.people()
        #expect(people.first { $0.id == sara1 }?.notes.contains("saved me today") == true)
        #expect(people.first { $0.id == sara2 }?.notes.isEmpty == true)
        #expect(people.count == 2) // nothing auto-created, nothing merged
    }

    // MARK: - §6.3 nothing lost

    @Test func failedFlushKeepsWordsHonestly() async throws {
        let seed = try makeSeed()
        let model = VentModel(
            store: seed.store, extraction: ScriptedVentExtraction(), speech: FakeSpeechCapture()
        )
        await model.start()

        await model.send("this one matters, don't lose it")

        // The words were captured BEFORE the network was tried — the row survives for retry.
        #expect(try seed.store.pendingUtterances().count == 1)
        #expect(model.items.contains { if case .keptLagged = $0 { true } else { false } })
        #expect(!model.items.contains { if case .confirmation = $0 { true } else { false } })
    }

    // MARK: - §6.4 the smart prompt is a pure typed selection

    @Test func smartPromptGoldens() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        let now = Date(timeIntervalSince1970: 1_784_973_600) // 2026-07-25 10:00 UTC
        let chapterId = UUID()
        let chapter = ChapterSummary(
            id: chapterId, type: .relationship, chapterKind: .dimension, title: "Daniel",
            iconRef: "heart.fill", state: .tense, awarenessPct: 70, isResting: false,
            personIds: [], priority: 5, createdAt: now, lastTouchedAt: now
        )
        func event(_ title: String, hoursFromNow: Double, armed: Bool = false) -> EventSnapshot {
            EventSnapshot(
                id: UUID(), chapterId: chapterId, date: now.addingTimeInterval(hoursFromNow * 3600),
                title: title, body: "", valence: .neutral, isOpen: true, isHealed: false,
                healedReason: nil, isUpcoming: true, source: .chat,
                preparedAt: nil, checkInArmed: armed
            )
        }

        // 1. A just-passed pinned moment wins — and an ARMED one beats a nearer unarmed one.
        let armed = event("The talk", hoursFromNow: -6, armed: true)
        let nearer = event("Lunch", hoursFromNow: -2)
        let postEvent = VentModel.selectPrompt(
            events: [nearer, armed], chapters: [chapter], now: now, calendar: calendar
        )
        #expect(postEvent.kind == .postEvent)
        #expect(postEvent.text == "💗 The talk \(VentCopy.postEventSuffix)")

        // 2. Nothing just passed → the Next-up pick, template phrasing exact.
        let tonight = event("The talk", hoursFromNow: 10) // 20:00 → "tonight"
        let upcoming = VentModel.selectPrompt(
            events: [tonight], chapters: [chapter], now: now, calendar: calendar
        )
        #expect(upcoming.kind == .upcoming)
        #expect(upcoming.text == "The talk · tonight \(VentCopy.upcomingSuffix)")

        // 3. A quiet world → the quiet prompt. Beyond the 48h window counts as quiet-past.
        let longPassed = event("Old thing", hoursFromNow: -80)
        let quiet = VentModel.selectPrompt(
            events: [longPassed], chapters: [chapter], now: now, calendar: calendar
        )
        #expect(quiet.kind == .quiet)
        #expect(quiet.text == VentCopy.quietPrompt)
    }

    // MARK: - §6.5 freshness is structural

    @Test func aNewSessionStartsEmpty() async throws {
        let seed = try makeSeed()
        let extraction = ScriptedVentExtraction { [self] in threeTopicEnvelope(for: $0) }
        let first = VentModel(store: seed.store, extraction: extraction, speech: FakeSpeechCapture())
        await first.start()
        await first.send("a full session with confirmations")
        #expect(!first.items.isEmpty)

        // The next presentation constructs a fresh model — nothing carries over, because
        // nothing CAN: no store model holds a vent transcript.
        let second = VentModel(store: seed.store, extraction: extraction, speech: FakeSpeechCapture())
        await second.start()
        #expect(second.items.isEmpty)
    }

    // MARK: - §6.6 voice: F9 gating + hold-to-talk through the fake

    @Test func micGatesOnStrictOnDeviceAvailability() async throws {
        let seed = try makeSeed()
        let unsupported = FakeSpeechCapture(availability: .unavailable)
        let model = VentModel(store: seed.store, extraction: ScriptedVentExtraction(), speech: unsupported)
        await model.start()
        #expect(model.micAvailable == false) // F9: the mic simply isn't there

        let denied = FakeSpeechCapture(
            availability: SpeechAvailability(onDeviceSupported: true, permissionDenied: true)
        )
        let deniedModel = VentModel(store: seed.store, extraction: ScriptedVentExtraction(), speech: denied)
        await deniedModel.start()
        #expect(deniedModel.micAvailable == false)
    }

    @Test func holdToTalkStreamsPartialsAndReleaseKeepsTextEditable() async throws {
        let seed = try makeSeed()
        let speech = FakeSpeechCapture(
            partials: ["he", "he did", "he did it again"],
            finalTranscript: "he did it again last night"
        )
        let model = VentModel(store: seed.store, extraction: ScriptedVentExtraction(), speech: speech)
        await model.start()
        #expect(model.micAvailable)

        await model.beginHold()
        #expect(model.isCapturing)
        for _ in 0..<20 where model.captureText != "he did it again" {
            await Task.yield()
        }
        #expect(model.captureText == "he did it again")

        await model.endHold()
        #expect(!model.isCapturing)
        // The final transcript lands in the composer, editable — never auto-sent (§4).
        #expect(model.captureText == "he did it again last night")
        #expect(model.items.isEmpty)
    }

    // MARK: - §6.9 never-tests: the copy bank + the walled module scan

    @Test func ventCopyBankHasNoGuiltStrings() {
        let forbidden = [
            "we miss you", "miss you", "come back", "don't forget", "you haven't",
            "overdue", "at risk", "last chance", "streak is about to",
        ]
        for line in VentCopy.all {
            for phrase in forbidden {
                #expect(!line.lowercased().contains(phrase), "guilt copy in vent bank: \(phrase)")
            }
        }
    }

    /// C9/F9 mechanically: VoiceCapture is on-device-only and store-blind — the sources must
    /// pin `requiresOnDeviceRecognition = true` and must never reference a network or store symbol.
    @Test func voiceCaptureIsOnDeviceOnlyAndWalled() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let moduleDir = testFile.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Kept/VoiceCapture")
        let files = try FileManager.default.contentsOfDirectory(at: moduleDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        let forbidden = ["URLSession", "import Network", "CFNetwork", "KeptStore", "SwiftData", "Services/Store"]
        var sawOnDevicePin = false
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            if content.contains("requiresOnDeviceRecognition = true") { sawOnDevicePin = true }
            for token in forbidden {
                #expect(!content.contains(token), "\(file.lastPathComponent) references \(token)")
            }
        }
        #expect(sawOnDevicePin, "the on-device pin is the F9 architecture — it must exist")
    }
}
