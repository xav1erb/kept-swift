import Foundation

// The wire contract with the proxy — mirrors docs/extraction.md §1 and M1-CONTRACTS §2 exactly.
// Every decode is strict and fails loudly (NN#7): unknown kind, unknown enum value, malformed
// date, or an id/ref violation throws. A swallowed delta is a lost piece of someone's life.

nonisolated enum ExtractionSchema {
    static let version = 1
}

/// The surface an utterance came from. The client stamps `EventSource` from this — the model
/// never sets `source` (extraction.md §1).
nonisolated enum Surface: String, Codable, Sendable {
    case onboarding, chapterChat, vent

    var eventSource: EventSource {
        switch self {
        case .onboarding: .onboarding
        case .chapterChat: .chat
        case .vent: .vent
        }
    }
}

/// A calendar date on the wire: strict `"yyyy-MM-dd"`, resolved deterministically in UTC.
nonisolated struct WireDate: Equatable, Sendable, Codable {
    let year: Int
    let month: Int
    let day: Int

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// UTC midnight of the given instant — the merge's fallback "utterance date at day precision".
    init(date: Date) {
        let components = Self.utc.dateComponents([.year, .month, .day], from: date)
        self.year = components.year!
        self.month = components.month!
        self.day = components.day!
    }

    var date: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              Self.utc.date(from: DateComponents(year: year, month: month, day: day)) != nil,
              (1...12).contains(month),
              (1...31).contains(day)
        else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected strict yyyy-MM-dd date, got '\(raw)'"
            ))
        }
        // Reject normalized-away impossibilities like 2026-02-31 (Calendar rolls them forward).
        let roundTrip = Self.utc.dateComponents([.year, .month, .day], from: WireDate(year: year, month: month, day: day).date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Impossible calendar date '\(raw)'"
            ))
        }
        self.init(year: year, month: month, day: day)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }
}

nonisolated enum DatePrecision: String, Codable, Equatable, Sendable {
    case day, month, year, unknown
}

/// Entity reference (extraction.md §1): `id` = UUID the model saw in the request context;
/// `ref` = local handle for an entity created earlier in this envelope. Exactly one, always.
nonisolated enum EntityHandle: Equatable, Sendable, Codable, Hashable {
    case id(UUID)
    case ref(String)

    private enum CodingKeys: String, CodingKey { case id, ref }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id)
        let ref = try container.decodeIfPresent(String.self, forKey: .ref)
        switch (id, ref) {
        case (let id?, nil): self = .id(id)
        case (nil, let ref?): self = .ref(ref)
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Entity reference must carry exactly one of 'id' / 'ref'"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .id(let id): try container.encode(id, forKey: .id)
        case .ref(let ref): try container.encode(ref, forKey: .ref)
        }
    }

    /// Upsert deltas carry their identity as flat top-level `id`/`ref` fields (extraction.md §1).
    fileprivate init(targetFrom decoder: Decoder) throws {
        self = try EntityHandle(from: decoder)
    }

    fileprivate func encodeTarget(to encoder: Encoder) throws {
        try encode(to: encoder)
    }
}

// MARK: - Request (client → proxy)

nonisolated struct ExtractionRequest: Encodable, Sendable {
    let schemaVersion: Int
    let utteranceId: UUID
    let surface: Surface
    let clientTime: Date
    let locale: String
    let utterance: String
    let context: ExtractionContext

    init(
        utteranceId: UUID = UUID(),
        surface: Surface,
        clientTime: Date,
        locale: String,
        utterance: String,
        context: ExtractionContext
    ) {
        self.schemaVersion = ExtractionSchema.version
        self.utteranceId = utteranceId
        self.surface = surface
        self.clientTime = clientTime
        self.locale = locale
        self.utterance = utterance
        self.context = context
    }
}

/// Minimum-necessary context (M1-CONTRACTS §4). Folded events travel WITH `isHealed: true`
/// (§8.3 ruling) so folded memories id-match instead of duplicating — the delta vocabulary has
/// no unfold and no destructive op, so the worst a model can do with one is reference its id.
nonisolated struct ExtractionContext: Codable, Equatable, Sendable {
    struct PersonContext: Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let relation: String
    }

    struct ChapterContext: Codable, Equatable, Sendable {
        let id: UUID
        let type: ChapterType
        let title: String
        let state: ChapterState
        let filledSlots: [String]
    }

    struct CommitmentContext: Codable, Equatable, Sendable {
        let id: UUID
        let personId: UUID?
        let text: String
        let dateMade: WireDate
    }

    struct EventContext: Codable, Equatable, Sendable {
        let id: UUID
        let chapterId: UUID?
        let title: String
        let date: WireDate
        let isOpen: Bool
        let isHealed: Bool
    }

    let people: [PersonContext]
    let chapters: [ChapterContext]
    let openCommitments: [CommitmentContext]
    let recentEvents: [EventContext]
}

// MARK: - Envelope (proxy → client)

nonisolated struct ExtractionEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let utteranceId: UUID
    let deltas: [Delta]
    let disambiguations: [Disambiguation]
}

/// The C4 gate. The ambiguous person's local `ref` is the binding handle: deltas referencing it
/// are held until the user answers; resolution binds the ref to an existing id or a confirmed-new
/// person (extraction.md §1, ratification amendment).
nonisolated struct Disambiguation: Codable, Equatable, Sendable {
    let ref: String
    let mention: String
    let candidateIds: [UUID]
    let question: String
}

// MARK: - Deltas

nonisolated enum Delta: Codable, Equatable, Sendable {
    case upsertPerson(UpsertPersonDelta)
    case upsertChapter(UpsertChapterDelta)
    case addEvent(AddEventDelta)
    case foldEvent(FoldEventDelta)
    case addCommitment(AddCommitmentDelta)
    case updateCommitmentStatus(UpdateCommitmentStatusDelta)
    case upsertGoal(UpsertGoalDelta)
    case setChapterState(SetChapterStateDelta)
    case setPersonMood(SetPersonMoodDelta)
    case addCrossLink(AddCrossLinkDelta)
    case fillSlots(FillSlotsDelta)

    private enum KindKey: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: KindKey.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "upsertPerson": self = .upsertPerson(try UpsertPersonDelta(from: decoder))
        case "upsertChapter": self = .upsertChapter(try UpsertChapterDelta(from: decoder))
        case "addEvent": self = .addEvent(try AddEventDelta(from: decoder))
        case "foldEvent": self = .foldEvent(try FoldEventDelta(from: decoder))
        case "addCommitment": self = .addCommitment(try AddCommitmentDelta(from: decoder))
        case "updateCommitmentStatus": self = .updateCommitmentStatus(try UpdateCommitmentStatusDelta(from: decoder))
        case "upsertGoal": self = .upsertGoal(try UpsertGoalDelta(from: decoder))
        case "setChapterState": self = .setChapterState(try SetChapterStateDelta(from: decoder))
        case "setPersonMood": self = .setPersonMood(try SetPersonMoodDelta(from: decoder))
        case "addCrossLink": self = .addCrossLink(try AddCrossLinkDelta(from: decoder))
        case "fillSlots": self = .fillSlots(try FillSlotsDelta(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container,
                debugDescription: "Unknown delta kind '\(kind)' — envelope rejected (extraction.md §2)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: KindKey.self)
        switch self {
        case .upsertPerson(let delta):
            try container.encode("upsertPerson", forKey: .kind); try delta.encode(to: encoder)
        case .upsertChapter(let delta):
            try container.encode("upsertChapter", forKey: .kind); try delta.encode(to: encoder)
        case .addEvent(let delta):
            try container.encode("addEvent", forKey: .kind); try delta.encode(to: encoder)
        case .foldEvent(let delta):
            try container.encode("foldEvent", forKey: .kind); try delta.encode(to: encoder)
        case .addCommitment(let delta):
            try container.encode("addCommitment", forKey: .kind); try delta.encode(to: encoder)
        case .updateCommitmentStatus(let delta):
            try container.encode("updateCommitmentStatus", forKey: .kind); try delta.encode(to: encoder)
        case .upsertGoal(let delta):
            try container.encode("upsertGoal", forKey: .kind); try delta.encode(to: encoder)
        case .setChapterState(let delta):
            try container.encode("setChapterState", forKey: .kind); try delta.encode(to: encoder)
        case .setPersonMood(let delta):
            try container.encode("setPersonMood", forKey: .kind); try delta.encode(to: encoder)
        case .addCrossLink(let delta):
            try container.encode("addCrossLink", forKey: .kind); try delta.encode(to: encoder)
        case .fillSlots(let delta):
            try container.encode("fillSlots", forKey: .kind); try delta.encode(to: encoder)
        }
    }
}

/// `chapterRefs` is attach-only (ratification amendment): the chapters this person belongs in.
/// Detachment is a user action, never a delta — the vocabulary stays non-destructive.
nonisolated struct UpsertPersonDelta: Codable, Equatable, Sendable {
    let target: EntityHandle
    let name: String
    let relation: String?
    let mood: PersonMood?
    let roleFlags: [RoleFlag]?
    let rituals: [String]?
    let notesAppend: String?
    let chapterRefs: [EntityHandle]?

    private enum CodingKeys: String, CodingKey {
        case name, relation, mood, roleFlags, rituals, notesAppend, chapterRefs
    }

    init(
        target: EntityHandle, name: String, relation: String? = nil, mood: PersonMood? = nil,
        roleFlags: [RoleFlag]? = nil, rituals: [String]? = nil, notesAppend: String? = nil,
        chapterRefs: [EntityHandle]? = nil
    ) {
        self.target = target
        self.name = name
        self.relation = relation
        self.mood = mood
        self.roleFlags = roleFlags
        self.rituals = rituals
        self.notesAppend = notesAppend
        self.chapterRefs = chapterRefs
    }

    init(from decoder: Decoder) throws {
        self.target = try EntityHandle(targetFrom: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.relation = try container.decodeIfPresent(String.self, forKey: .relation)
        self.mood = try container.decodeIfPresent(PersonMood.self, forKey: .mood)
        self.roleFlags = try container.decodeIfPresent([RoleFlag].self, forKey: .roleFlags)
        self.rituals = try container.decodeIfPresent([String].self, forKey: .rituals)
        self.notesAppend = try container.decodeIfPresent(String.self, forKey: .notesAppend)
        self.chapterRefs = try container.decodeIfPresent([EntityHandle].self, forKey: .chapterRefs)
    }

    func encode(to encoder: Encoder) throws {
        try target.encodeTarget(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(relation, forKey: .relation)
        try container.encodeIfPresent(mood, forKey: .mood)
        try container.encodeIfPresent(roleFlags, forKey: .roleFlags)
        try container.encodeIfPresent(rituals, forKey: .rituals)
        try container.encodeIfPresent(notesAppend, forKey: .notesAppend)
        try container.encodeIfPresent(chapterRefs, forKey: .chapterRefs)
    }
}

nonisolated struct UpsertChapterDelta: Codable, Equatable, Sendable {
    let target: EntityHandle
    let type: ChapterType
    let chapterKind: ChapterKind
    let title: String?
    let iconRef: String?
    let state: ChapterState?

    private enum CodingKeys: String, CodingKey { case type, chapterKind, title, iconRef, state }

    init(
        target: EntityHandle, type: ChapterType, chapterKind: ChapterKind,
        title: String? = nil, iconRef: String? = nil, state: ChapterState? = nil
    ) {
        self.target = target
        self.type = type
        self.chapterKind = chapterKind
        self.title = title
        self.iconRef = iconRef
        self.state = state
    }

    init(from decoder: Decoder) throws {
        self.target = try EntityHandle(targetFrom: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(ChapterType.self, forKey: .type)
        self.chapterKind = try container.decode(ChapterKind.self, forKey: .chapterKind)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.iconRef = try container.decodeIfPresent(String.self, forKey: .iconRef)
        self.state = try container.decodeIfPresent(ChapterState.self, forKey: .state)
    }

    func encode(to encoder: Encoder) throws {
        try target.encodeTarget(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(chapterKind, forKey: .chapterKind)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(iconRef, forKey: .iconRef)
        try container.encodeIfPresent(state, forKey: .state)
    }
}

nonisolated struct AddEventDelta: Codable, Equatable, Sendable {
    let ref: String
    let chapterRef: EntityHandle
    let date: WireDate?
    let datePrecision: DatePrecision
    let title: String
    let body: String
    let valence: Valence
    let isOpen: Bool
    let isUpcoming: Bool
}

nonisolated struct FoldEventDelta: Codable, Equatable, Sendable {
    let eventId: UUID
    let reason: String
}

nonisolated struct AddCommitmentDelta: Codable, Equatable, Sendable {
    let ref: String
    let chapterRef: EntityHandle
    let personRef: EntityHandle?
    let text: String
    let dateMade: WireDate?
    let datePrecision: DatePrecision
}

/// `commitmentRef` accepts id or ref (ratification amendment — a commitment disclosed and broken
/// in the same utterance must be status-updatable within its own envelope, fx-001).
nonisolated struct UpdateCommitmentStatusDelta: Codable, Equatable, Sendable {
    let commitmentRef: EntityHandle
    let status: CommitmentStatus
    let evidenceEventRef: EntityHandle?
}

nonisolated struct UpsertGoalDelta: Codable, Equatable, Sendable {
    let target: EntityHandle
    let chapterRef: EntityHandle?
    let text: String
    let targetDate: WireDate?
    let progressNote: String?

    private enum CodingKeys: String, CodingKey { case chapterRef, text, targetDate, progressNote }

    init(
        target: EntityHandle, chapterRef: EntityHandle? = nil, text: String,
        targetDate: WireDate? = nil, progressNote: String? = nil
    ) {
        self.target = target
        self.chapterRef = chapterRef
        self.text = text
        self.targetDate = targetDate
        self.progressNote = progressNote
    }

    init(from decoder: Decoder) throws {
        self.target = try EntityHandle(targetFrom: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chapterRef = try container.decodeIfPresent(EntityHandle.self, forKey: .chapterRef)
        self.text = try container.decode(String.self, forKey: .text)
        self.targetDate = try container.decodeIfPresent(WireDate.self, forKey: .targetDate)
        self.progressNote = try container.decodeIfPresent(String.self, forKey: .progressNote)
    }

    func encode(to encoder: Encoder) throws {
        try target.encodeTarget(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(chapterRef, forKey: .chapterRef)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(targetDate, forKey: .targetDate)
        try container.encodeIfPresent(progressNote, forKey: .progressNote)
    }
}

nonisolated struct SetChapterStateDelta: Codable, Equatable, Sendable {
    let chapterRef: EntityHandle
    let state: ChapterState
}

nonisolated struct SetPersonMoodDelta: Codable, Equatable, Sendable {
    let personRef: EntityHandle
    let mood: PersonMood
}

nonisolated struct AddCrossLinkDelta: Codable, Equatable, Sendable {
    let fromChapterRef: EntityHandle
    let toChapterRef: EntityHandle
    let note: String
}

nonisolated struct FillSlotsDelta: Codable, Equatable, Sendable {
    let chapterRef: EntityHandle
    let slots: [String]
}

// MARK: - Typed proxy errors (M1-CONTRACTS §2)

nonisolated enum ExtractionError: Error {
    case rateLimited(retryAfter: TimeInterval?)
    case upstreamUnavailable
    case schemaMismatch(serverVersion: Int)
    case unauthorized
    case transport(underlying: any Error)
}
