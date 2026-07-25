import Foundation
import Observation

// Chapter detail (M4-CONTRACTS §5/§6). The chat turn is TWO independent paths (§10.1 ruling):
// the durable filing path (append + enqueue + flush through the M1 pipeline) and the ephemeral
// reply path (/chat). A failed reply never loses filed words; a lagging flush never blocks the
// conversation. The prep flow is a client-side typed stage machine (C4 — the machine computes,
// the model narrates); receipts must resolve against the store or the envelope is rejected.

/// The chapter-detail copy bank (C3: the guilt-scan never-test runs over `all` — detail copy is
/// never assembled anywhere else). ⚠ agent-drafted copy — flagged for Xavier's review.
nonisolated enum ChapterDetailCopy {
    static let composerPlaceholder = "tell me anything…"
    static let emptyChat = "This room is yours. Say anything — I keep all of it."
    static let typing = "Pom is thinking…"
    static let replyFailed = "I lost my thread — tap to try that again. Your words are already kept."
    static let offline = "I can't reach my voice right now — everything you say is still kept and files as soon as I'm back."
    static let filingLag = "Still filing that one — it's kept, just slow."
    static let prepEntryPrefix = "want to get ready for"
    static let prepEntryCTA = "Get ready with Pom"
    static let prepContinue = "okay — what's next?"
    static let prepPerspectiveChip = "am I overreacting?"
    static let timelineIntroPrefix = "Your story with"
    static let timelineIntroSuffix = "the way I keep it — the good stays bright, the healed rests quietly."
    static let timelineFooter = "Healed moments stay folded so your story leads with the good. They're yours to open — never mine to bring up."
    static let timelineEmpty = "Nothing kept here yet — it starts with whatever you tell me."
    static let foldedPill = "🌱 A bump — worked through & forgiven · tap only if you want to revisit"
    static let foldedFrame = "You chose to forgive this — kept as something you survived, not as ammunition."
    static let refold = "fold it back"
    static let onRecord = "On record."
    static let upcomingPrepped = "You're prepped. I'll check in after."
    static let loadError = "This chapter is safe — it just didn't load. Try again?"

    static var all: [String] {
        [composerPlaceholder, emptyChat, typing, replyFailed, offline, filingLag,
         prepEntryPrefix, prepEntryCTA, prepContinue, prepPerspectiveChip,
         timelineIntroPrefix, timelineIntroSuffix, timelineFooter, timelineEmpty,
         foldedPill, foldedFrame, refold, onRecord, upcomingPrepped, loadError]
    }

    /// The header's weather glyph — soft vocabulary only, never numbers (§2.2).
    static func weatherGlyph(for state: ChapterState) -> String {
        switch state {
        case .warm: "🌤"
        case .fine: "☁️"
        case .quiet: "🌙"
        case .tense: "🌧"
        case .complicated: "🌫"
        }
    }
}

@Observable
@MainActor
final class ChapterDetailModel {

    enum LoadState: Equatable { case loading, ready, failed }

    let chapterId: UUID
    private let store: KeptStore
    private let chat: any ChatServicing
    private let extraction: any ExtractionServicing

    private(set) var state: LoadState = .loading
    private(set) var summary: ChapterSummary?
    private(set) var messages: [ChatMessageSnapshot] = []
    private(set) var chips: [String] = []
    private(set) var isAwaitingReply = false
    private(set) var replyFailed = false
    private(set) var filingLagged = false

    /// The stage the NEXT prep request will ask for; nil = no active prep session.
    private(set) var prepStage: PrepStage?
    /// Where the flow returns after an on-request perspective detour.
    private var perspectiveReturnStage: PrepStage?
    /// The upcoming event this prep session is for (nil → prep completes, nothing arms).
    private(set) var prepEventId: UUID?

    /// The last reply attempt, kept for retry: history EXCLUDES the user turn it carries.
    private var lastAttempt: (userText: String?, history: [ChatTurn])?

    init(chapterId: UUID, store: KeptStore, chat: any ChatServicing, extraction: any ExtractionServicing) {
        self.chapterId = chapterId
        self.store = store
        self.chat = chat
        self.extraction = extraction
    }

    func refresh() {
        do {
            guard let summary = try store.chapterSummaries().first(where: { $0.id == chapterId }) else {
                state = .failed
                return
            }
            self.summary = summary
            messages = try store.chatMessages(inChapter: chapterId)
            state = .ready
        } catch {
            state = .failed
        }
    }

    // MARK: - Header (typed template — no model text, M4-CONTRACTS §6)

    var events: [EventSnapshot] { (try? store.events(inChapter: chapterId)) ?? [] }

    func headerStatus(now: Date = .now, calendar: Calendar = .current) -> String {
        guard let summary else { return "" }
        var parts = [summary.type.displayName.lowercased()]
        parts.append("since \(summary.createdAt.formatted(.dateTime.month(.abbreviated).year()))")
        let upcoming = events.filter(\.isUpcoming)
        if let status = WorldModel.statusLine(for: summary, upcoming: upcoming, now: now, calendar: calendar) {
            parts.append(status)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - The chat turn (§10.1: two independent calls)

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAwaitingReply else { return }
        let history = currentTurns()
        do {
            // The durable path first: the words are KEPT before any network is attempted.
            try store.appendChatMessage(chapterId: chapterId, author: .user, text: trimmed)
            try store.enqueueUtterance(surface: .chapterChat, nodeId: "chat", text: trimmed, chapterId: chapterId)
        } catch {
            state = .failed
            return
        }
        refresh()
        lastAttempt = (trimmed, history)
        async let filing: Void = flushFiling()
        await requestReply(userText: trimmed, history: history)
        await filing
    }

    /// The prep continue affordance — advances the stage machine without user text.
    func advancePrep() async {
        guard prepStage != nil, !isAwaitingReply else { return }
        let history = currentTurns()
        lastAttempt = (nil, history)
        await requestReply(userText: nil, history: history)
    }

    /// Retry re-sends ONLY the reply call — the user's words and the filing queue are untouched.
    func retryReply() async {
        guard let attempt = lastAttempt, !isAwaitingReply else { return }
        await requestReply(userText: attempt.userText, history: attempt.history)
    }

    // MARK: - Prep session (the §5 stage machine)

    /// The nearest upcoming open event, if any — what a new prep session gets ready for.
    func upcomingEvent(now: Date = .now, calendar: Calendar = .current) -> EventSnapshot? {
        events
            .filter { $0.isUpcoming && $0.date >= calendar.startOfDay(for: now) }
            .min { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    var canOfferPrep: Bool {
        guard prepStage == nil, state == .ready else { return false }
        guard let event = upcomingEvent() else { return false }
        return event.preparedAt == nil
    }

    var canAskPerspective: Bool {
        prepStage != nil && prepStage != .perspective && perspectiveReturnStage == nil
    }

    var showsContinue: Bool {
        guard prepStage != nil, !isAwaitingReply, !replyFailed else { return false }
        guard case .pom = messages.last?.author else { return false }
        return true
    }

    func startPrep(now: Date = .now, calendar: Calendar = .current) async {
        guard prepStage == nil else { return }
        prepEventId = upcomingEvent(now: now, calendar: calendar)?.id
        prepStage = .reframe
        await advancePrep()
    }

    func askPerspective() async {
        guard let current = prepStage, current != .perspective else { return }
        perspectiveReturnStage = current
        prepStage = .perspective
        await send(ChapterDetailCopy.prepPerspectiveChip)
    }

    func stopPrep() {
        prepStage = nil
        perspectiveReturnStage = nil
        prepEventId = nil
    }

    // MARK: - Private

    private func currentTurns() -> [ChatTurn] {
        messages.suffix(30).map { ChatTurn(author: $0.author, text: $0.text) }
    }

    private func flushFiling() async {
        let result = await UtteranceFlusher(store: store, extraction: extraction).flush()
        filingLagged = !result.failedUtteranceIds.isEmpty
        // Deltas may have re-graded the chapter (state, awareness) — re-read, keep the transcript.
        refresh()
    }

    private func requestReply(userText: String?, history: [ChatTurn]) async {
        isAwaitingReply = true
        replyFailed = false
        chips = []
        defer { isAwaitingReply = false }
        do {
            let context = try store.chatContext(chapterId: chapterId)
            let mode: ChatMode = prepStage.map { ChatMode.prep(stage: $0) } ?? .chat
            let request = ChatRequest(
                turnId: UUID(),
                chapterId: chapterId,
                mode: mode,
                clientTime: .now,
                locale: Locale.current.identifier,
                userText: userText,
                history: history,
                context: context
            )
            let envelope = try (try await chat.send(request)).validated(for: request)
            try validateReceipts(envelope.card)
            try store.appendChatMessage(
                chapterId: chapterId, author: .pom, text: envelope.text, card: envelope.card
            )
            chips = envelope.chips
            refresh()
            lastAttempt = nil
            if let card = envelope.card { advanceStage(after: card) }
        } catch {
            replyFailed = true
        }
    }

    /// Every receipt citation must resolve to a real record row — an invented receipt is
    /// structurally unrenderable, so the whole envelope is rejected loudly (NN#7, M4 §5).
    private func validateReceipts(_ card: PrepCard?) throws {
        guard let card else { return }
        let refs = card.receiptRefs
        guard !refs.isEmpty else { return }
        var valid = Set(try store.events(inChapter: chapterId).map(\.id))
        valid.formUnion(try store.commitments(inChapter: chapterId).map(\.id))
        for ref in refs where !valid.contains(ref.id) {
            throw ChatError.envelopeRejected(reason: "receipt id not in the record")
        }
    }

    /// Resolves a receipt citation for rendering: title + date come from the STORE, never the
    /// model — the model only annotates (M4-CONTRACTS §5).
    func receiptDisplay(_ id: UUID) -> (title: String, date: Date)? {
        if let event = events.first(where: { $0.id == id }) {
            return (event.title, event.date)
        }
        if let commitment = (try? store.commitments(inChapter: chapterId))?.first(where: { $0.id == id }) {
            return ("\u{201C}\(commitment.text)\u{201D}", commitment.dateMade)
        }
        return nil
    }

    private func advanceStage(after card: PrepCard) {
        switch card.stage {
        case .reframe:
            prepStage = .likelyAnswers
        case .likelyAnswers:
            prepStage = .keepCard
        case .perspective:
            prepStage = perspectiveReturnStage ?? .keepCard
            perspectiveReturnStage = nil
        case .keepCard:
            prepStage = .openingClose
        case .openingClose:
            completePrep()
        }
    }

    private func completePrep() {
        if let eventId = prepEventId {
            // The event may have left the store mid-session — prep still completes, nothing arms
            // (M4-CONTRACTS §5).
            try? store.markPrepared(eventId: eventId)
            try? store.armPostEventCheckIn(eventId: eventId)
        }
        stopPrep()
        refresh()
    }
}
