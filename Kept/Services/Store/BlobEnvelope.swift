import CryptoKit
import Foundation

// The E2E envelope (M2-CONTRACTS §7.3, C2/F3). One blob per record; the TYPE TAG LIVES INSIDE
// THE CIPHERTEXT — the server stores opaque `(blob_id, payload, envelope_version)` rows and stays
// type-blind (minimum-leak posture, closes the M1 §5 question).
//
// envelope_version 1 = AES.GCM under the iCloud-Keychain master key, 12-byte random nonce,
// `combined` (nonce ‖ ciphertext ‖ tag). Framing changes bump the version — contract review.

nonisolated enum BlobRecordType: String, Codable, CaseIterable, Sendable {
    case userProfile, notificationPrefs, chapter, person, event, commitment
    case goal, reminder, achievement, crossLink, appliedUtterance, heldDeltaBatch

    /// `NotificationPrefs` has no id of its own — the singleton rides a fixed blob id.
    static let notificationPrefsSingletonId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
}

nonisolated enum BlobEnvelopeError: Error {
    case sealFailed
    case openFailed
    case unknownEnvelopeVersion(Int)
    case unknownRecordType(String)
}

/// What the server stores (mirrors `public.encrypted_blobs` minus tenancy columns).
nonisolated struct EncryptedBlob: Equatable, Sendable {
    let blobId: UUID
    let envelopeVersion: Int
    let payload: Data          // AES.GCM combined: nonce ‖ ciphertext ‖ tag
}

/// The plaintext interior: `{ "t": ..., "v": 1, "data": ... }` (M2-CONTRACTS §7.3).
nonisolated struct BlobInterior<P: Codable>: Codable {
    let t: BlobRecordType
    let v: Int
    let data: P
}

/// Decode step 1: read the tag without knowing the payload type.
nonisolated private struct BlobTypeProbe: Codable {
    let t: String
    let v: Int
}

nonisolated enum BlobEnvelope {
    static let currentVersion = 1

    static func seal<P: Codable>(
        _ payload: P, type: BlobRecordType, blobId: UUID, key: SymmetricKey
    ) throws -> EncryptedBlob {
        let encoder = JSONEncoder()
        // .deferredToDate (raw timeIntervalSinceReferenceDate Double) — the only strategy that
        // round-trips Date EXACTLY. .iso8601 truncates sub-second precision, which broke
        // restore-equality and destabilized createdAt sort order (M3 amendment to §7.3; interiors
        // are ciphertext anyway — fidelity beats readability). Amended 2026-07-23, pre-first-blob.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        let interior = try encoder.encode(BlobInterior(t: type, v: 1, data: payload))
        guard let combined = try AES.GCM.seal(interior, using: key).combined else {
            throw BlobEnvelopeError.sealFailed
        }
        return EncryptedBlob(blobId: blobId, envelopeVersion: currentVersion, payload: combined)
    }

    /// Opens the envelope and returns the interior JSON + its type tag. Tampering (a flipped
    /// byte, a wrong key) fails loudly — never a silent skip (NN#7 posture applies to our own
    /// boundary too).
    static func open(_ blob: EncryptedBlob, key: SymmetricKey) throws -> (type: BlobRecordType, interior: Data) {
        guard blob.envelopeVersion == currentVersion else {
            throw BlobEnvelopeError.unknownEnvelopeVersion(blob.envelopeVersion)
        }
        let interior: Data
        do {
            let box = try AES.GCM.SealedBox(combined: blob.payload)
            interior = try AES.GCM.open(box, using: key)
        } catch {
            throw BlobEnvelopeError.openFailed
        }
        let probe = try Self.decoder().decode(BlobTypeProbe.self, from: interior)
        guard let type = BlobRecordType(rawValue: probe.t) else {
            throw BlobEnvelopeError.unknownRecordType(probe.t)
        }
        return (type, interior)
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }
}

// MARK: - Payload structs (mirror the @Model fields 1:1; relationship links travel as ids and
// are re-linked in restore's second pass)

nonisolated struct UserProfileBlob: Codable {
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
    let aiConsentGrantedAt: Date?
    let createdAt: Date
}

nonisolated struct NotificationPrefsBlob: Codable {
    let frequency: CheckInFrequency
    let quietStart: Int?
    let quietEnd: Int?
    let exemptReminderIDs: [UUID]
    let genericLockScreenCopy: Bool
    let monthlyRecapEnabled: Bool
}

nonisolated struct ChapterBlob: Codable {
    let id: UUID
    let type: ChapterType
    let chapterKind: ChapterKind
    let title: String
    let iconRef: String
    let state: ChapterState
    let awarenessPct: Int
    let filledSlots: [String]
    let priority: Int
    let isResting: Bool
    let closingLetter: String?
    let createdAt: Date
    let lastTouchedAt: Date
    let personIds: [UUID]
}

nonisolated struct PersonBlob: Codable {
    let id: UUID
    let name: String
    let relation: String
    let age: Int?
    let mood: PersonMood
    let roleFlags: [RoleFlag]
    let rituals: [String]
    let priority: Int
    let notes: String
}

nonisolated struct EventBlob: Codable {
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

nonisolated struct CommitmentBlob: Codable {
    let id: UUID
    let chapterId: UUID?
    let personId: UUID?
    let text: String
    let dateMade: Date
    let status: CommitmentStatus
    let evidenceEventIds: [UUID]
}

nonisolated struct GoalBlob: Codable {
    let id: UUID
    let chapterId: UUID?
    let text: String
    let targetDate: Date?
    let progressNote: String
}

nonisolated struct ReminderBlob: Codable {
    let id: UUID
    let chapterId: UUID?
    let title: String
    let schedule: ReminderSchedule
    let enabled: Bool
}

nonisolated struct AchievementBlob: Codable {
    let id: UUID
    let key: String
    let category: AchievementCategory
    let chapterId: UUID?
    let earnedAt: Date?
    let progress: Double?
    let isSecret: Bool
}

nonisolated struct CrossLinkBlob: Codable {
    let id: UUID
    let fromChapterId: UUID?
    let toChapterId: UUID?
    let note: String
}

nonisolated struct AppliedUtteranceBlob: Codable {
    let utteranceId: UUID
    let appliedAt: Date
}

nonisolated struct HeldDeltaBatchBlob: Codable {
    let id: UUID
    let utteranceId: UUID
    let ref: String
    let mention: String
    let candidateIds: [UUID]
    let question: String
    let deltasJSON: Data
    let bindingsJSON: Data
    let surfaceRaw: String
    let clientTime: Date
    let createdAt: Date
}
