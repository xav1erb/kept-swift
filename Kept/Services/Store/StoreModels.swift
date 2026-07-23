import Foundation
import SwiftData

// The §3 data model behind Services/Store/ (C7). Views never see these types — reads go
// through the snapshot read models, writes through KeptStore commands (F11: no @Query).
//
// Gotcha (logged in Services/Store/CLAUDE.md): to-one relationship fields are optional at the
// SwiftData layer; required-ness is enforced by the command surface, which always sets them.
//
// C6: awarenessPct / streakCount / states are stored values, written at merge/day-close only.

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var age: Int?
    var pronouns: String?
    var city: String?
    var occupation: String?
    var theme: Theme
    var voiceProfile: VoiceProfile
    var streakCount: Int
    var streakRestDayUsed: Bool
    var onboardingMode: OnboardingMode?
    var followupQueue: [ChapterType]
    /// Set exactly once at the reveal (M2). RootView gates on it.
    var hasCompletedOnboarding: Bool = false
    /// F6: derived at the age write (13...17 → true), never displayed. Under-13 never reaches
    /// a stored profile — the engine hard-stops and wipes (M2-CONTRACTS §6).
    var isMinor: Bool = false
    /// C2 legal gate (onboarding 4.5): nil = not granted. The utterance queue and every AI
    /// client refuse structurally while nil (M2-CONTRACTS §7.1).
    var aiConsentGrantedAt: Date? = nil
    var createdAt: Date

    init(id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.name = ""
        self.theme = .cloudCream
        self.voiceProfile = .soft
        self.streakCount = 0
        self.streakRestDayUsed = false
        self.followupQueue = []
        self.createdAt = createdAt
    }
}

@Model
final class Chapter {
    @Attribute(.unique) var id: UUID
    var type: ChapterType
    var chapterKind: ChapterKind
    var title: String
    var iconRef: String
    var state: ChapterState
    var awarenessPct: Int
    var filledSlots: [String] = []
    var priority: Int
    var isResting: Bool
    var closingLetter: String?
    var createdAt: Date
    var lastTouchedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Event.chapter)
    var events: [Event]
    @Relationship(deleteRule: .cascade, inverse: \Commitment.chapter)
    var commitments: [Commitment]
    @Relationship(inverse: \Person.chapters)
    var people: [Person]

    init(
        id: UUID = UUID(),
        type: ChapterType,
        chapterKind: ChapterKind,
        title: String,
        iconRef: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.chapterKind = chapterKind
        self.title = title
        self.iconRef = iconRef
        self.state = .fine
        self.awarenessPct = 0
        self.priority = 0
        self.isResting = false
        self.createdAt = createdAt
        self.lastTouchedAt = createdAt
        self.events = []
        self.commitments = []
        self.people = []
    }
}

@Model
final class Person {
    @Attribute(.unique) var id: UUID
    var name: String
    var relation: String
    var age: Int?
    var mood: PersonMood
    var roleFlags: [RoleFlag]
    var rituals: [String]
    var priority: Int
    var notes: String
    var chapters: [Chapter]

    init(id: UUID = UUID(), name: String, relation: String) {
        self.id = id
        self.name = name
        self.relation = relation
        self.mood = .fine
        self.roleFlags = []
        self.rituals = []
        self.priority = 0
        self.notes = ""
        self.chapters = []
    }
}

@Model
final class Event {
    @Attribute(.unique) var id: UUID
    var chapter: Chapter?
    var date: Date
    var title: String
    var body: String
    var valence: Valence
    var isOpen: Bool
    var isHealed: Bool
    /// Quotes/paraphrases the user's own words of resolution (extraction.md §3 rule 4).
    /// Set once when the fold applies; refolding an already-healed event never overwrites it.
    var healedReason: String? = nil
    var isUpcoming: Bool
    var source: EventSource

    init(
        id: UUID = UUID(),
        date: Date,
        title: String,
        body: String,
        valence: Valence,
        isOpen: Bool,
        isUpcoming: Bool,
        source: EventSource
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.body = body
        self.valence = valence
        self.isOpen = isOpen
        self.isHealed = false
        self.isUpcoming = isUpcoming
        self.source = source
    }
}

@Model
final class Commitment {
    // C3/§19 by construction: no timer, no countdown, no "days since" field exists here.
    @Attribute(.unique) var id: UUID
    var chapter: Chapter?
    var person: Person?
    var text: String
    var dateMade: Date
    var status: CommitmentStatus
    var evidenceEvents: [Event]

    init(id: UUID = UUID(), text: String, dateMade: Date) {
        self.id = id
        self.text = text
        self.dateMade = dateMade
        self.status = .held
        self.evidenceEvents = []
    }
}

@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    var chapter: Chapter?
    var text: String
    var targetDate: Date?
    var progressNote: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
        self.progressNote = ""
    }
}

@Model
final class Reminder {
    @Attribute(.unique) var id: UUID
    var chapter: Chapter?
    var title: String
    var schedule: ReminderSchedule
    var enabled: Bool

    init(id: UUID = UUID(), title: String, schedule: ReminderSchedule) {
        self.id = id
        self.title = title
        self.schedule = schedule
        self.enabled = true
    }
}

@Model
final class NotificationPrefs {
    var frequency: CheckInFrequency
    var quietStart: Int?
    var quietEnd: Int?
    var exemptReminderIDs: [UUID]
    var genericLockScreenCopy: Bool
    var monthlyRecapEnabled: Bool

    init() {
        self.frequency = .moderate
        self.exemptReminderIDs = []
        self.genericLockScreenCopy = true   // F12: generic phrasing default ON
        self.monthlyRecapEnabled = true
    }
}

@Model
final class Achievement {
    @Attribute(.unique) var id: UUID
    var key: String
    var category: AchievementCategory
    var chapter: Chapter?
    var earnedAt: Date?
    var progress: Double?
    var isSecret: Bool

    init(id: UUID = UUID(), key: String, category: AchievementCategory, isSecret: Bool = false) {
        self.id = id
        self.key = key
        self.category = category
        self.isSecret = isSecret
    }
}

@Model
final class CrossLink {
    @Attribute(.unique) var id: UUID
    var fromChapter: Chapter?
    var toChapter: Chapter?
    var note: String

    init(id: UUID = UUID(), note: String) {
        self.id = id
        self.note = note
    }
}

/// Idempotency record (extraction.md §3 rule 1): one row per applied envelope. A duplicate
/// envelope is a no-op; retries after a mid-merge crash are therefore safe. Internal to the
/// merge — never surfaces in a read model.
@Model
final class AppliedUtterance {
    @Attribute(.unique) var utteranceId: UUID
    var appliedAt: Date

    init(utteranceId: UUID, appliedAt: Date = .now) {
        self.utteranceId = utteranceId
        self.appliedAt = appliedAt
    }
}

/// Resumable onboarding draft (M2-CONTRACTS §2): current step + node + the rendered bubble log,
/// so a killed app re-opens mid-interview pixel-identical. Extracted/command-written data is NOT
/// duplicated here. Deleted at reveal. Internal — never surfaces in a read model beyond its own
/// snapshot.
@Model
final class OnboardingDraft {
    var stepRaw: Int
    var nodeId: String?
    var bubblesJSON: Data
    /// nodeId → raw answer; the engine rebuilds its branch/census state from this on resume.
    var answersJSON: Data
    var updatedAt: Date

    init(stepRaw: Int, nodeId: String? = nil, bubblesJSON: Data = Data(), answersJSON: Data = Data(), updatedAt: Date = .now) {
        self.stepRaw = stepRaw
        self.nodeId = nodeId
        self.bubblesJSON = bubblesJSON
        self.answersJSON = answersJSON
        self.updatedAt = updatedAt
    }
}

/// The pre-sign-in utterance queue (M2-CONTRACTS §7.1, §8.1 ruling): free-text answers park here —
/// encrypted at rest like everything in the store — and flush FIFO through the M1 pipeline at
/// first sign-in. `utteranceId` is minted at capture so a crash mid-flush replays safely through
/// the `AppliedUtterance` idempotency gate.
@Model
final class PendingUtterance {
    @Attribute(.unique) var utteranceId: UUID
    var order: Int
    var surfaceRaw: String
    var nodeId: String
    var text: String
    var clientTime: Date

    init(utteranceId: UUID = UUID(), order: Int, surfaceRaw: String, nodeId: String, text: String, clientTime: Date = .now) {
        self.utteranceId = utteranceId
        self.order = order
        self.surfaceRaw = surfaceRaw
        self.nodeId = nodeId
        self.text = text
        self.clientTime = clientTime
    }
}

/// Write-behind backup queue (M2-CONTRACTS §7.3): commands and the merge engine enqueue touched
/// record refs in the same save; the uploader drains when authed. `deleted` rows become server
/// tombstones. Internal plumbing — never in a read model.
@Model
final class PendingBlobUpload {
    @Attribute(.unique) var blobId: UUID
    var recordTypeRaw: String
    var deleted: Bool
    var enqueuedAt: Date

    init(blobId: UUID, recordTypeRaw: String, deleted: Bool = false, enqueuedAt: Date = .now) {
        self.blobId = blobId
        self.recordTypeRaw = recordTypeRaw
        self.deleted = deleted
        self.enqueuedAt = enqueuedAt
    }
}

/// The persisted disambiguation queue (extraction.md §2, atomicity exception): deltas referencing
/// an ambiguous person are parked here — surviving app restarts — until the user answers the
/// question (C4 gate). `deltasJSON` holds the held `[Delta]`; `bindingsJSON` holds the
/// ref → UUID map from the envelope's applied portion so held deltas re-resolve exactly.
@Model
final class HeldDeltaBatch {
    @Attribute(.unique) var id: UUID
    var utteranceId: UUID
    var ref: String
    var mention: String
    var candidateIds: [UUID]
    var question: String
    var deltasJSON: Data
    var bindingsJSON: Data
    var surfaceRaw: String
    var clientTime: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        utteranceId: UUID,
        ref: String,
        mention: String,
        candidateIds: [UUID],
        question: String,
        deltasJSON: Data,
        bindingsJSON: Data,
        surfaceRaw: String,
        clientTime: Date,
        createdAt: Date = .now
    ) {
        self.id = id
        self.utteranceId = utteranceId
        self.ref = ref
        self.mention = mention
        self.candidateIds = candidateIds
        self.question = question
        self.deltasJSON = deltasJSON
        self.bindingsJSON = bindingsJSON
        self.surfaceRaw = surfaceRaw
        self.clientTime = clientTime
        self.createdAt = createdAt
    }
}
