import Foundation
import Observation

// Tell Pom — the vent (M5-CONTRACTS §3). Fresh each session BY CONSTRUCTION: the session
// transcript lives only in this model, built at sheet presentation; the store has nothing to
// hold it. The only write is the ONE pipeline (enqueue .vent + flush); Pom's response is the
// typed filing confirmation (§8.1 ruling — no model call renders this sheet).

/// The vent copy bank (C3: guilt-scanned; ⚠ agent-drafted, flagged for Xavier's review).
nonisolated enum VentCopy {
    static let hero = "I'm listening."
    static let heroSub = "Say anything — a mess, a win, three topics at once. Sorting it is my job, not yours."
    static let filingNote = "Whatever you tell me gets filed into the right chapters, quietly. You talk. I keep."
    static let sealedBadge = "🔒 SEALED"
    static let composerPlaceholder = "anything at all…"
    static let filing = "filing…"
    static let filedPrefix = "filed to"
    static let filedSuffix = "— want to open any?"
    static let keptQuiet = "Kept. All of it."
    static let keptLagged = "Kept. I'll file it the moment I can — nothing gets lost."
    static let someoneNew = "someone new"
    static let quietPrompt = "what's alive today? even the small stuff counts."
    static let typeOnlyLine = "typing is just as kept."
    static let postEventSuffix = "happened — how did it go? · I've been thinking about you."
    static let upcomingSuffix = "— want to talk it through?"

    /// The 6 template chips, verbatim (whitepaper §10). Tapping pre-fills the composer.
    static let templateChips = [
        "🌧 just need to vent",
        "✨ something good happened",
        "📖 quick chapter update",
        "🤔 help me decide something",
        "🌿 log something small",
        "💬 ask me about my day",
    ]

    static var all: [String] {
        [hero, heroSub, filingNote, sealedBadge, composerPlaceholder, filing, filedPrefix,
         filedSuffix, keptQuiet, keptLagged, someoneNew, quietPrompt, typeOnlyLine,
         postEventSuffix, upcomingSuffix] + templateChips
    }

    static func filedLine(chapterTitles: [String]) -> String {
        let list: String = switch chapterTitles.count {
        case 0: ""
        case 1: chapterTitles[0]
        case 2: "\(chapterTitles[0]) and \(chapterTitles[1])"
        default: chapterTitles.dropLast().joined(separator: ", ") + " and \(chapterTitles.last!)"
        }
        return list.isEmpty ? keptQuiet : "\(filedPrefix) \(list) \(filedSuffix)"
    }
}

/// The contextual smart prompt — a typed selection over store state (§8.4 ruling, C4).
nonisolated struct VentPrompt: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case postEvent, upcoming, quiet }
    let kind: Kind
    let text: String
    let chapterId: UUID?
}

@Observable
@MainActor
final class VentModel {

    enum SessionItem: Equatable, Identifiable {
        case userText(id: UUID, text: String)
        case filing(id: UUID)
        case confirmation(id: UUID, line: String, chips: [FilingChip])
        case question(id: UUID, prompt: String, options: [QuestionOption])
        case keptLagged(id: UUID)

        var id: UUID {
            switch self {
            case .userText(let id, _), .filing(let id), .confirmation(let id, _, _),
                 .question(let id, _, _), .keptLagged(let id):
                id
            }
        }
    }

    nonisolated struct FilingChip: Equatable, Sendable {
        let chapterId: UUID
        let title: String
        let iconRef: String
    }

    nonisolated struct QuestionOption: Equatable, Sendable {
        let label: String
        let resolution: PersonResolution
    }

    private let store: KeptStore
    private let extraction: any ExtractionServicing
    private let speech: any SpeechCapturing

    private(set) var items: [SessionItem] = []
    private(set) var smartPrompt: VentPrompt = VentPrompt(kind: .quiet, text: VentCopy.quietPrompt, chapterId: nil)
    private(set) var isFiling = false
    /// F9: the mic exists only when strictly-on-device STT does.
    private(set) var micAvailable = false
    private(set) var isCapturing = false
    /// Live partial transcript while holding; lands in the composer, stays editable.
    var captureText = ""

    init(
        store: KeptStore,
        extraction: any ExtractionServicing,
        speech: any SpeechCapturing = OnDeviceSpeechCapture()
    ) {
        self.store = store
        self.extraction = extraction
        self.speech = speech
    }

    /// Session start: the smart prompt, any questions Pom is still holding (persisted batches
    /// from ANY surface — §8.2 ruling), and the mic availability check.
    func start(now: Date = .now, calendar: Calendar = .current) async {
        smartPrompt = Self.selectPrompt(
            events: (try? store.riverEvents()) ?? [],
            chapters: (try? store.chapterSummaries()) ?? [],
            now: now, calendar: calendar
        )
        appendPendingQuestions()
        let availability = await speech.availability(locale: .current)
        micAvailable = availability.onDeviceSupported && !availability.permissionDenied
    }

    // MARK: - The turn (C1 — capture first, network second; words cannot be lost)

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isFiling else { return }
        do {
            try store.enqueueUtterance(surface: .vent, nodeId: "vent", text: trimmed)
        } catch {
            return // pre-consent is unreachable post-onboarding; a store failure keeps the sheet inert
        }
        items.append(.userText(id: UUID(), text: trimmed))
        let filingId = UUID()
        items.append(.filing(id: filingId))
        isFiling = true
        defer { isFiling = false }

        let result = await UtteranceFlusher(store: store, extraction: extraction).flush()
        items.removeAll { $0.id == filingId }

        for summary in result.summaries {
            appendConfirmation(for: summary)
        }
        if !result.failedUtteranceIds.isEmpty {
            items.append(.keptLagged(id: UUID()))
        }
        appendPendingQuestions()
    }

    /// The C4 gate's surface: answering applies the held deltas and files them.
    func resolveQuestion(batchId: UUID, resolution: PersonResolution) async {
        guard let summary = try? store.resolveDisambiguation(batchId: batchId, resolution: resolution) else { return }
        items.removeAll { $0.id == batchId }
        appendConfirmation(for: summary)
    }

    // MARK: - Voice (hold-to-talk; the module is walled — this model only sees text)

    func beginHold() async {
        guard micAvailable, !isCapturing else { return }
        guard await speech.requestPermissions() else {
            micAvailable = false
            return
        }
        captureText = ""
        do {
            try await speech.startCapture { [weak self] partial in
                Task { @MainActor in self?.captureText = partial }
            }
            isCapturing = true
        } catch {
            micAvailable = false
        }
    }

    func endHold() async {
        guard isCapturing else { return }
        captureText = await speech.stopCapture()
        isCapturing = false
        // The transcript stays in the composer, editable — her words, her send (§4).
    }

    // MARK: - Typed selection (pure, golden-tested)

    static func selectPrompt(
        events: [EventSnapshot],
        chapters: [ChapterSummary],
        now: Date,
        calendar: Calendar
    ) -> VentPrompt {
        // 1. A pinned moment that just passed (≤48h): armed check-ins first, then nearest past.
        let justPassed = events
            .filter { $0.isUpcoming && $0.date < now && $0.date >= now.addingTimeInterval(-48 * 3600) }
            .min {
                ($0.checkInArmed ? 0 : 1, now.timeIntervalSince($0.date), $0.id.uuidString)
                    < ($1.checkInArmed ? 0 : 1, now.timeIntervalSince($1.date), $1.id.uuidString)
            }
        if let event = justPassed {
            return VentPrompt(
                kind: .postEvent,
                text: "💗 \(event.title) \(VentCopy.postEventSuffix)",
                chapterId: event.chapterId
            )
        }
        // 2. Else the Next-up pick (the M3 engine, reused).
        if let nextUp = WorldModel.selectNextUp(
            events: events.filter { $0.isUpcoming }, chapters: chapters, now: now, calendar: calendar
        ) {
            return VentPrompt(
                kind: .upcoming,
                text: "\(nextUp.eventTitle) · \(nextUp.relativeDay) \(VentCopy.upcomingSuffix)",
                chapterId: nextUp.chapterId
            )
        }
        // 3. Else quiet.
        return VentPrompt(kind: .quiet, text: VentCopy.quietPrompt, chapterId: nil)
    }

    // MARK: - Private

    private func appendConfirmation(for summary: FilingSummary) {
        guard !summary.touchedChapterIds.isEmpty else {
            items.append(.confirmation(id: UUID(), line: VentCopy.keptQuiet, chips: []))
            return
        }
        let summaries = (try? store.chapterSummaries()) ?? []
        let byId = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
        let chips = summary.touchedChapterIds
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { byId[$0] }
            .map { FilingChip(chapterId: $0.id, title: $0.title, iconRef: $0.iconRef) }
        items.append(.confirmation(
            id: UUID(),
            line: VentCopy.filedLine(chapterTitles: chips.map(\.title)),
            chips: chips
        ))
    }

    private func appendPendingQuestions() {
        let people = (try? store.people()) ?? []
        let byId = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        for batch in (try? store.pendingDisambiguations()) ?? [] {
            guard !items.contains(where: { $0.id == batch.id }) else { continue }
            var options = batch.candidateIds.compactMap { candidateId -> QuestionOption? in
                guard let person = byId[candidateId] else { return nil }
                return QuestionOption(
                    label: "\(person.name) · \(person.relation)",
                    resolution: .existing(person.id)
                )
            }
            options.append(QuestionOption(label: VentCopy.someoneNew, resolution: .newPerson))
            items.append(.question(id: batch.id, prompt: batch.question, options: options))
        }
    }
}
