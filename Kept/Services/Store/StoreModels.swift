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
