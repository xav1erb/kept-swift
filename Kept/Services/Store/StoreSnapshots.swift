import Foundation

// Typed read models (C7/F11): the ONLY shapes features and views ever see. Value types,
// Equatable so tests can assert whole-graph equality across store round-trips.

struct UserProfileSnapshot: Equatable, Sendable {
    let id: UUID
    let name: String
    let age: Int?
    let pronouns: String?
    let city: String?
    let occupation: String?
    let theme: Theme
    let voiceProfile: VoiceProfile
    let streakCount: Int
    let streakRestDayUsed: Bool
    let onboardingMode: OnboardingMode?
    let followupQueue: [ChapterType]
}

struct NotificationPrefsSnapshot: Equatable, Sendable {
    let frequency: CheckInFrequency
    let quietStart: Int?
    let quietEnd: Int?
    let exemptReminderIDs: [UUID]
    let genericLockScreenCopy: Bool
    let monthlyRecapEnabled: Bool
}

struct ChapterSummary: Equatable, Sendable, Identifiable {
    let id: UUID
    let type: ChapterType
    let chapterKind: ChapterKind
    let title: String
    let iconRef: String
    let state: ChapterState
    let awarenessPct: Int
    let isResting: Bool
    let personIds: [UUID]
}

struct PersonSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let relation: String
    let mood: PersonMood
    let roleFlags: [RoleFlag]
    let rituals: [String]
    let priority: Int
    let notes: String
    let chapterIds: [UUID]
}

struct EventSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let chapterId: UUID?
    let date: Date
    let title: String
    let body: String
    let valence: Valence
    let isOpen: Bool
    let isHealed: Bool
    let healedReason: String?
    let isUpcoming: Bool
    let source: EventSource
}

struct CommitmentSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let chapterId: UUID?
    let personId: UUID?
    let text: String
    let dateMade: Date
    let status: CommitmentStatus
    let evidenceEventIds: [UUID]
}

struct GoalSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let chapterId: UUID?
    let text: String
    let targetDate: Date?
    let progressNote: String
}

struct CrossLinkSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let fromChapterId: UUID?
    let toChapterId: UUID?
    let note: String
}
