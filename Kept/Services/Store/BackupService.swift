import CryptoKit
import Dependencies
import Foundation

// Backup + restore orchestration (M2-CONTRACTS §7.2/§7.3). Runs after sign-in only — before
// that, nothing leaves the device (§8.1 posture). Conflict strategy v1: last-write-wins per blob
// on the server's updated_at (single-active-device assumption, documented in the contract).

@Observable
final class BackupService {
    enum Phase: Equatable {
        case idle
        case backingUp
        case restoring
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let store: KeptStore
    private let backend: any BackendServicing
    private let masterKey: any MasterKeyProviding

    init(store: KeptStore, backend: any BackendServicing, masterKey: any MasterKeyProviding) {
        self.store = store
        self.backend = backend
        self.masterKey = masterKey
    }

    /// The initial full backup after first sign-in: create-or-load the master key, seal every
    /// record, upsert. Clears the write-behind queue (a full backup supersedes it).
    func initialBackup() async throws {
        phase = .backingUp
        do {
            let key = try masterKey.loadOrCreateKey()
            let blobs = try store.sealAllRecords(key: key)
            try await backend.upsertBlobs(blobs)
            for row in try store.pendingBlobUploads() {
                try store.clearBlobUpload(row.blobId)
            }
            phase = .idle
        } catch {
            phase = .failed(String(describing: error))
            throw error
        }
    }

    /// Drains the write-behind queue (M2 §7.3): seal each dirty record, upsert, clear the row.
    /// A record deleted since enqueue becomes a tombstone.
    func drainQueue() async throws {
        let pending = try store.pendingBlobUploads()
        guard !pending.isEmpty, await backend.isSignedIn() else { return }
        phase = .backingUp
        do {
            let key = try masterKey.loadOrCreateKey()
            for row in pending {
                if row.deleted {
                    try await backend.tombstoneBlob(row.blobId)
                } else if let blob = try store.sealRecord(type: row.type, id: row.blobId, key: key) {
                    try await backend.upsertBlobs([blob])
                }
                try store.clearBlobUpload(row.blobId)
            }
            phase = .idle
        } catch {
            phase = .failed(String(describing: error))
            throw error
        }
    }

    /// The sign-in moment's first question (M2 §7.3): does this account already own a world?
    func serverWorldExists() async throws -> Bool {
        try await !backend.listBlobs().isEmpty
    }

    /// "New phone, story follows you": wipe the minutes-old local onboarding scratch (the
    /// utterance queue survives — the new answers file INTO the restored world) and rebuild from
    /// the server blobs. The master key must already be in the synced iCloud Keychain — its
    /// absence with blobs present is surfaced as an error, never a silent empty world.
    func restoreServerWorld() async throws {
        let blobs = try await backend.listBlobs()
        guard !blobs.isEmpty else { return }
        guard let key = try masterKey.existingKey() else {
            phase = .failed("master key not present in iCloud Keychain")
            throw MasterKeyError.keychain(errSecItemNotFound)
        }
        phase = .restoring
        do {
            let interiors = try blobs.map { try BlobEnvelope.open($0, key: key) }
            try store.wipeWorldForRestore()
            try store.restore(interiors: interiors)
            phase = .idle
        } catch {
            phase = .failed(String(describing: error))
            throw error
        }
    }
}
