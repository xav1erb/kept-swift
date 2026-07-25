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
    let hasCompletedOnboarding: Bool
    let isMinor: Bool
    let aiConsentGranted: Bool
}

nonisolated struct OnboardingDraftSnapshot: Equatable, Sendable {
    let stepRaw: Int
    let nodeId: String?
    let bubblesJSON: Data
    let answersJSON: Data
}

nonisolated struct PendingUtteranceSnapshot: Equatable, Sendable {
    let utteranceId: UUID
    let order: Int
    let surfaceRaw: String
    let nodeId: String
    let text: String
    let clientTime: Date
    let chapterId: UUID?
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
    /// M3-CONTRACTS §8 A1: the globe's deterministic longitude rule sorts on priority then
    /// createdAt; recent-chapter cards sort on lastTouchedAt. All stored, never recomputed (C6).
    let priority: Int
    let createdAt: Date
    let lastTouchedAt: Date
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

// nonisolated: consumed by the nonisolated TimelineNode grammar (M4) — the default-MainActor
// synthesized conformances would otherwise be unusable there (Store CLAUDE.md 2026-07-19 gotcha).
nonisolated struct EventSnapshot: Equatable, Sendable, Identifiable {
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
    /// M4: prep completion stamp + M6 check-in intent. A timestamp and a bool by construction —
    /// no timer, no countdown (C3/§19).
    let preparedAt: Date?
    let checkInArmed: Bool
}

/// One chapter-chat turn (M4). `card` is the typed prep component when this message carries one —
/// decoded from the stored payload with the REAL wire decoder (a corrupt card fails loudly, NN#7).
nonisolated struct ChatMessageSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let chapterId: UUID?
    let author: ChatAuthor
    let text: String
    let card: PrepCard?
    let date: Date
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
