import Foundation

// The controlled vocabulary (whitepaper §3, LEXICON-aligned). String raw values are the
// storage + wire representation — renaming a case is a migration, not an edit.

nonisolated enum ChapterType: String, Codable, CaseIterable, Sendable {
    case relationship, family, friendship, work, health, money, passion
    case privateCorner, growth, grief

    /// §19: sensitive types never show question counts or slot lists anywhere. Type-level
    /// fact so never-tests can assert against it (C3).
    var isSensitive: Bool { self == .privateCorner || self == .grief }
}

nonisolated enum ChapterKind: String, Codable, Sendable {
    case situational, dimension
}

nonisolated enum ChapterState: String, Codable, CaseIterable, Sendable {
    case warm, fine, quiet, tense, complicated
}

nonisolated enum PersonMood: String, Codable, CaseIterable, Sendable {
    case warm, fine, quiet, tense, complicated, drifting
}

nonisolated enum RoleFlag: String, Codable, Sendable {
    case confidant, ally, witness, trigger
}

nonisolated enum Valence: String, Codable, Sendable {
    case bright, gold, neutral, storm, soft
}

nonisolated enum EventSource: String, Codable, Sendable {
    case chat, vent, onboarding
}

nonisolated enum CommitmentStatus: String, Codable, Sendable {
    case held, broken, resolved
}

nonisolated enum AchievementCategory: String, Codable, Sendable {
    case courage, consistency, closure, selfcare, milestone
}

nonisolated enum OnboardingMode: String, Codable, Sendable {
    case focus, full
}

nonisolated enum VoiceProfile: String, Codable, CaseIterable, Sendable {
    case soft, realWithMe, sunshine, calm
}

nonisolated enum CheckInFrequency: String, Codable, CaseIterable, Sendable {
    case daily, moderate, importantOnly
}

/// Typed reminder schedule — deliberately NOT a cron string (M0-CONTRACTS §2).
nonisolated struct ReminderSchedule: Codable, Equatable, Sendable {
    nonisolated enum Repeat: String, Codable, Sendable {
        case daily, weekdays, weekly
    }

    var hour: Int
    var minute: Int
    var repeats: Repeat
}
