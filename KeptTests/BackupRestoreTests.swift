import CryptoKit
import Foundation
import Testing
@testable import Kept

// M2-CONTRACTS §9.6: envelope round-trip, tamper detection (a flipped byte fails loudly), and
// restore rebuilding an equivalent store — plus the BackupService orchestration over FakeBackend.

@MainActor
struct BackupRestoreTests {

    private let key = InMemoryMasterKey()

    @Test func envelopeRoundTrips() throws {
        let symmetricKey = try key.loadOrCreateKey()
        let payload = PersonBlob(
            id: UUID(), name: "Daniel", relation: "partner", age: nil, mood: .fine,
            roleFlags: [], rituals: ["Sunday pancakes"], priority: 0, notes: "brings flowers"
        )
        let sealed = try BlobEnvelope.seal(payload, type: .person, blobId: payload.id, key: symmetricKey)
        #expect(sealed.envelopeVersion == 1)

        let (type, interior) = try BlobEnvelope.open(sealed, key: symmetricKey)
        #expect(type == .person)
        let decoded = try BlobEnvelope.decoder().decode(BlobInterior<PersonBlob>.self, from: interior)
        #expect(decoded.data.name == "Daniel")
        #expect(decoded.data.rituals == ["Sunday pancakes"])
    }

    @Test func tamperedByteFailsLoudly() throws {
        let symmetricKey = try key.loadOrCreateKey()
        let payload = GoalBlob(id: UUID(), chapterId: nil, text: "€6,000 saved", targetDate: nil, progressNote: "")
        let sealed = try BlobEnvelope.seal(payload, type: .goal, blobId: payload.id, key: symmetricKey)

        var tampered = sealed.payload
        tampered[tampered.count / 2] ^= 0xFF
        let corrupted = EncryptedBlob(blobId: sealed.blobId, envelopeVersion: 1, payload: tampered)
        #expect(throws: BlobEnvelopeError.self) {
            _ = try BlobEnvelope.open(corrupted, key: symmetricKey)
        }
    }

    @Test func wrongKeyFailsLoudly() throws {
        let sealed = try BlobEnvelope.seal(
            GoalBlob(id: UUID(), chapterId: nil, text: "x", targetDate: nil, progressNote: ""),
            type: .goal, blobId: UUID(), key: key.loadOrCreateKey()
        )
        let otherKey = InMemoryMasterKey(keyData: Data(repeating: 0x07, count: 32))
        #expect(throws: BlobEnvelopeError.self) {
            _ = try BlobEnvelope.open(sealed, key: otherKey.loadOrCreateKey())
        }
    }

    @Test func unknownEnvelopeVersionRejects() throws {
        let sealed = try BlobEnvelope.seal(
            GoalBlob(id: UUID(), chapterId: nil, text: "x", targetDate: nil, progressNote: ""),
            type: .goal, blobId: UUID(), key: key.loadOrCreateKey()
        )
        let future = EncryptedBlob(blobId: sealed.blobId, envelopeVersion: 2, payload: sealed.payload)
        #expect(throws: BlobEnvelopeError.self) {
            _ = try BlobEnvelope.open(future, key: key.loadOrCreateKey())
        }
    }

    @Test func hexCodecRoundTrips() {
        let data = Data([0x00, 0x0A, 0xFF, 0x42])
        let hex = SupabaseBackend.hexEncode(data)
        #expect(hex == "\\x000aff42")
        #expect(SupabaseBackend.hexDecode(hex) == data)
        #expect(SupabaseBackend.hexDecode("000aff42") == data)  // prefixless tolerated
        #expect(SupabaseBackend.hexDecode("\\x0") == nil)       // odd length rejected
    }

    /// Seal the fx-001 world, restore into a fresh store, and compare every read model — the
    /// "new phone, story follows you" mechanism proven on real pipeline data (NN#4).
    @Test func sealAllThenRestoreRebuildsTheWorld() async throws {
        let harness = try FixtureHarness()
        try harness.run("fx-001")
        let source = harness.store
        let symmetricKey = try key.loadOrCreateKey()

        let blobs = try source.sealAllRecords(key: symmetricKey)
        #expect(!blobs.isEmpty)

        let target = try KeptStore(configuration: .inMemory)
        try target.restore(interiors: blobs.map { try BlobEnvelope.open($0, key: symmetricKey) })

        #expect(try target.userProfile() == (try source.userProfile()))
        #expect(try target.chapterSummaries() == (try source.chapterSummaries()))
        #expect(try target.people() == (try source.people()))
        #expect(try target.goals() == (try source.goals()))
        #expect(try target.crossLinks() == (try source.crossLinks()))
        for chapter in try source.chapterSummaries() {
            #expect(try target.events(inChapter: chapter.id) == (try source.events(inChapter: chapter.id)))
            #expect(try target.commitments(inChapter: chapter.id) == (try source.commitments(inChapter: chapter.id)))
        }
    }

    @Test func backupServiceUploadsAndRestores() async throws {
        let store = try KeptStore(configuration: .inMemory)
        try store.setUserName("Maya")
        let chapterId = try store.createChapter(
            type: .relationship, chapterKind: .dimension, title: "Us", iconRef: "heart"
        )
        try store.fillCensusSlots(chapterId: chapterId, slots: ["currentState"])

        let backend = FakeBackend()
        backend.seed(blobs: [], signedIn: true)
        let service = BackupService(store: store, backend: backend, masterKey: key)

        try await service.initialBackup()
        #expect(!backend.blobs.isEmpty)
        #expect(try store.pendingBlobUploads().isEmpty)  // full backup supersedes the queue

        // Write-behind: a later command enqueues; drain uploads and clears.
        try store.setChapterState(chapterId, state: .warm)
        #expect(try store.pendingBlobUploads().count == 1)
        try await service.drainQueue()
        #expect(try store.pendingBlobUploads().isEmpty)

        // New device, same account, same (synced) master key: restore rebuilds the world.
        let fresh = try KeptStore(configuration: .inMemory)
        let freshService = BackupService(store: fresh, backend: backend, masterKey: key)
        #expect(try await freshService.serverWorldExists())
        try await freshService.restoreServerWorld()
        #expect(try fresh.userProfile().name == "Maya")
        let restored = try #require(try fresh.chapterSummaries().first)
        #expect(restored.title == "Us")
        #expect(restored.state == .warm)
    }

    @Test func restoreWithoutMasterKeyFailsLoudly() async throws {
        let store = try KeptStore(configuration: .inMemory)
        let backend = FakeBackend()
        let sealed = try BlobEnvelope.seal(
            GoalBlob(id: UUID(), chapterId: nil, text: "x", targetDate: nil, progressNote: ""),
            type: .goal, blobId: UUID(), key: key.loadOrCreateKey()
        )
        backend.seed(blobs: [sealed], signedIn: true)

        /// A keychain with no key: blobs exist but cannot be opened — never a silent empty world.
        struct EmptyKeychain: MasterKeyProviding {
            func loadOrCreateKey() throws -> SymmetricKey { SymmetricKey(size: .bits256) }
            func existingKey() throws -> SymmetricKey? { nil }
        }
        let service = BackupService(store: store, backend: backend, masterKey: EmptyKeychain())
        await #expect(throws: MasterKeyError.self) {
            try await service.restoreServerWorld()
        }
    }
}
