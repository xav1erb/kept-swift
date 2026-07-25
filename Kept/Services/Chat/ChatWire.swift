import Foundation

// The /chat wire contract (M4-CONTRACTS §3). Explicit Codable, strict decode, loud failure —
// NN#7 applies to Pom's replies exactly as it does to deltas. The card grammar is enforced
// server-side by structured outputs AND re-validated here (defense in depth, both boundaries).

nonisolated enum ChatSchema {
    static let version = 1
}

nonisolated enum ChatAuthor: String, Codable, Sendable {
    case pom
    case user
}

/// The prep flow's typed stages (M4-CONTRACTS §5). The CLIENT advances these (C4 — the stage
/// machine computes, the model narrates); `perspective` is entered only on user request and
/// returns to the interrupted stage.
nonisolated enum PrepStage: String, Codable, CaseIterable, Sendable {
    case reframe
    case likelyAnswers
    case perspective
    case keepCard
    case openingClose
}

nonisolated enum ChatMode: Equatable, Sendable {
    case chat
    case prep(stage: PrepStage)
}

nonisolated struct ChatTurn: Codable, Equatable, Sendable {
    let author: ChatAuthor
    let text: String
}

/// Chapter-scoped context — fuller than ExtractionContext (chat needs the whole room) but still
/// one chapter only (minimum-necessary, C2). Folded events travel flagged; the server assembler
/// quarantines them into the sealed-memories block (M4-CONTRACTS §4) — a code path, not a hope.
nonisolated struct ChatContext: Codable, Equatable, Sendable {
    struct ChapterContext: Codable, Equatable, Sendable {
        let id: UUID
        let type: ChapterType
        let title: String
        let state: ChapterState
        let awarenessPct: Int
        let filledSlots: [String]
    }

    struct PersonContext: Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let relation: String
        let mood: PersonMood
        let roleFlags: [RoleFlag]
        let rituals: [String]
        let notes: String
        let priority: Int
    }

    struct EventContext: Codable, Equatable, Sendable {
        let id: UUID
        let title: String
        let body: String
        let date: WireDate
        let valence: Valence
        let isOpen: Bool
        let isHealed: Bool
        let healedReason: String?
        let isUpcoming: Bool
    }

    struct CommitmentContext: Codable, Equatable, Sendable {
        let id: UUID
        let personId: UUID?
        let text: String
        let dateMade: WireDate
        let status: CommitmentStatus
    }

    struct GoalContext: Codable, Equatable, Sendable {
        let id: UUID
        let text: String
        let targetDate: WireDate?
        let progressNote: String
    }

    struct CrossLinkContext: Codable, Equatable, Sendable {
        let otherChapterTitle: String
        let note: String
    }

    let userName: String
    let chapter: ChapterContext
    let people: [PersonContext]
    let events: [EventContext]
    let commitments: [CommitmentContext]
    let goals: [GoalContext]
    let crossLinks: [CrossLinkContext]
}

nonisolated struct ChatRequest: Encodable, Sendable {
    let schemaVersion: Int
    let turnId: UUID
    let chapterId: UUID
    let mode: ChatMode
    let clientTime: Date
    let locale: String
    /// nil only for client-initiated stage advances (the continue affordance sends no user text).
    let userText: String?
    /// Last ≤30 turns, oldest first; card messages travel flattened to their text.
    let history: [ChatTurn]
    let context: ChatContext

    init(
        schemaVersion: Int = ChatSchema.version,
        turnId: UUID,
        chapterId: UUID,
        mode: ChatMode,
        clientTime: Date,
        locale: String,
        userText: String?,
        history: [ChatTurn],
        context: ChatContext
    ) {
        self.schemaVersion = schemaVersion
        self.turnId = turnId
        self.chapterId = chapterId
        self.mode = mode
        self.clientTime = clientTime
        self.locale = locale
        self.userText = userText
        self.history = history
        self.context = context
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, turnId, chapterId, mode, prepStage, clientTime, locale
        case userText, history, context
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(turnId, forKey: .turnId)
        try container.encode(chapterId, forKey: .chapterId)
        switch mode {
        case .chat:
            try container.encode("chat", forKey: .mode)
        case .prep(let stage):
            try container.encode("prep", forKey: .mode)
            try container.encode(stage, forKey: .prepStage)
        }
        try container.encode(clientTime, forKey: .clientTime)
        try container.encode(locale, forKey: .locale)
        try container.encodeIfPresent(userText, forKey: .userText)
        try container.encode(history, forKey: .history)
        try container.encode(context, forKey: .context)
    }
}

// MARK: - Prep cards (M4-CONTRACTS §5)

/// A receipt citation: the id MUST resolve to a context commitment/event — the UI renders
/// title/date from the STORE; the model only annotates. An invented receipt is structurally
/// unrenderable (the model layer rejects the envelope on an unresolvable id).
nonisolated struct ReceiptRef: Codable, Equatable, Sendable {
    let id: UUID
    let note: String
}

nonisolated struct LikelyAnswer: Codable, Equatable, Sendable {
    let theirLine: String
    let read: String
    let counter: String
}

nonisolated struct PerspectiveSignal: Codable, Equatable, Sendable {
    let text: String
    let present: Bool
}

/// The typed prep components. Tagged by `kind`. C3 lives in this type: `perspective` has no
/// verdict field ("never a verdict on the relationship" is unexpressible); nothing here carries
/// a timer, countdown, or reconciliation percentage.
nonisolated enum PrepCard: Codable, Equatable, Sendable {
    case reframe(goal: String, receipts: [ReceiptRef])
    case likelyAnswers([LikelyAnswer])
    case perspective(incidentRead: String, patternRead: String, signals: [PerspectiveSignal], grounding: String)
    case keepCard(items: [ReceiptRef], closingLine: String)
    case openingClose(opening: String, close: String)

    var stage: PrepStage {
        switch self {
        case .reframe: .reframe
        case .likelyAnswers: .likelyAnswers
        case .perspective: .perspective
        case .keepCard: .keepCard
        case .openingClose: .openingClose
        }
    }

    /// Every receipt citation on this card (empty for cards that carry none).
    var receiptRefs: [ReceiptRef] {
        switch self {
        case .reframe(_, let receipts): receipts
        case .keepCard(let items, _): items
        case .likelyAnswers, .perspective, .openingClose: []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, goal, receipts, answers, incidentRead, patternRead, signals, grounding
        case items, closingLine, opening, close
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "reframe":
            self = .reframe(
                goal: try container.decode(String.self, forKey: .goal),
                receipts: try container.decode([ReceiptRef].self, forKey: .receipts)
            )
        case "likelyAnswers":
            let answers = try container.decode([LikelyAnswer].self, forKey: .answers)
            guard (2...4).contains(answers.count) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .answers, in: container,
                    debugDescription: "likelyAnswers requires 2–4 entries, got \(answers.count)"
                )
            }
            self = .likelyAnswers(answers)
        case "perspective":
            self = .perspective(
                incidentRead: try container.decode(String.self, forKey: .incidentRead),
                patternRead: try container.decode(String.self, forKey: .patternRead),
                signals: try container.decode([PerspectiveSignal].self, forKey: .signals),
                grounding: try container.decode(String.self, forKey: .grounding)
            )
        case "keepCard":
            self = .keepCard(
                items: try container.decode([ReceiptRef].self, forKey: .items),
                closingLine: try container.decode(String.self, forKey: .closingLine)
            )
        case "openingClose":
            self = .openingClose(
                opening: try container.decode(String.self, forKey: .opening),
                close: try container.decode(String.self, forKey: .close)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "Unknown prep card kind '\(kind)'"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .reframe(let goal, let receipts):
            try container.encode("reframe", forKey: .kind)
            try container.encode(goal, forKey: .goal)
            try container.encode(receipts, forKey: .receipts)
        case .likelyAnswers(let answers):
            try container.encode("likelyAnswers", forKey: .kind)
            try container.encode(answers, forKey: .answers)
        case .perspective(let incidentRead, let patternRead, let signals, let grounding):
            try container.encode("perspective", forKey: .kind)
            try container.encode(incidentRead, forKey: .incidentRead)
            try container.encode(patternRead, forKey: .patternRead)
            try container.encode(signals, forKey: .signals)
            try container.encode(grounding, forKey: .grounding)
        case .keepCard(let items, let closingLine):
            try container.encode("keepCard", forKey: .kind)
            try container.encode(items, forKey: .items)
            try container.encode(closingLine, forKey: .closingLine)
        case .openingClose(let opening, let close):
            try container.encode("openingClose", forKey: .kind)
            try container.encode(opening, forKey: .opening)
            try container.encode(close, forKey: .close)
        }
    }
}

// MARK: - Envelope

nonisolated struct ChatEnvelope: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let turnId: UUID
    /// Pom's words — ALWAYS present. Every stage schema keeps text required and card nullable,
    /// so a crisis response is never blocked by a card grammar (M4-CONTRACTS §4).
    let text: String
    let card: PrepCard?
    let chips: [String]

    init(schemaVersion: Int, turnId: UUID, text: String, card: PrepCard?, chips: [String]) {
        self.schemaVersion = schemaVersion
        self.turnId = turnId
        self.text = text
        self.card = card
        self.chips = chips
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, turnId, text, card, chips
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        turnId = try container.decode(UUID.self, forKey: .turnId)
        text = try container.decode(String.self, forKey: .text)
        card = try container.decodeIfPresent(PrepCard.self, forKey: .card)
        let chips = try container.decodeIfPresent([String].self, forKey: .chips) ?? []
        guard chips.count <= 3 else {
            throw DecodingError.dataCorruptedError(
                forKey: .chips, in: container,
                debugDescription: "At most 3 quick-reply chips, got \(chips.count)"
            )
        }
        self.chips = chips
    }

    /// Post-decode validation against the request (runs on live AND scripted paths): identity
    /// echo, version match, and stage-lock — any mismatch rejects the envelope loudly.
    func validated(for request: ChatRequest) throws -> ChatEnvelope {
        guard schemaVersion == request.schemaVersion else {
            throw ChatError.schemaMismatch(serverVersion: schemaVersion)
        }
        guard turnId == request.turnId else {
            throw ChatError.envelopeRejected(reason: "turnId echo mismatch")
        }
        if let card {
            guard case .prep(let stage) = request.mode else {
                throw ChatError.envelopeRejected(reason: "card outside prep mode")
            }
            guard card.stage == stage else {
                throw ChatError.envelopeRejected(
                    reason: "card stage \(card.stage.rawValue) ≠ requested \(stage.rawValue)"
                )
            }
        }
        return self
    }
}

nonisolated enum ChatError: Error {
    case rateLimited(retryAfter: TimeInterval?)
    case upstreamUnavailable
    case schemaMismatch(serverVersion: Int)
    case unauthorized
    case envelopeRejected(reason: String)
    case transport(underlying: Error)
}
