import Dependencies
import Foundation

// The backend seam (M2-CONTRACTS §7.1, APPROACH seam #6): Supabase auth + the ciphertext blob
// transport, protocol-fronted so tests fake it (C9 posture). The client only ever sends
// ciphertext to `encrypted_blobs` (C2) — sealing happens in Services/Store before data reaches
// this boundary.

nonisolated enum BackendError: Error {
    /// AppSecrets missing/empty — the app runs fully local until Xavier supplies the anon key
    /// (docs/PROVISIONING.md item 1). Never a silent no-op: sign-in surfaces the state.
    case unconfigured
    case notSignedIn
    case transport(underlying: Error)
}

/// nonisolated + Sendable: the extraction endpoint's token closure calls this off the main
/// actor; the live impl wraps a Sendable Supabase client.
nonisolated protocol BackendServicing: AnyObject, Sendable {
    var isConfigured: Bool { get }
    func isSignedIn() async -> Bool
    /// The Supabase user JWT — feeds `ExtractionEndpoint.accessToken` (M1 client).
    func accessToken() async throws -> String
    func signInWithApple(idToken: String, nonce: String?) async throws
    func sendMagicLink(email: String) async throws
    /// Handles `kept://auth-callback` (magic link). Returns true when a session was established.
    func handleAuthCallback(url: URL) async throws -> Bool
    func signOut() async throws

    // Blob transport (ciphertext only, RLS owner-scoped)
    func upsertBlobs(_ blobs: [EncryptedBlob]) async throws
    func tombstoneBlob(_ blobId: UUID) async throws
    /// Live (non-tombstoned) blobs for this user — the restore read.
    func listBlobs() async throws -> [EncryptedBlob]
}

/// Fails loudly on every network operation instead of pretending a backend exists.
nonisolated final class UnconfiguredBackend: BackendServicing {
    var isConfigured: Bool { false }
    func isSignedIn() async -> Bool { false }
    func accessToken() async throws -> String { throw BackendError.unconfigured }
    func signInWithApple(idToken: String, nonce: String?) async throws { throw BackendError.unconfigured }
    func sendMagicLink(email: String) async throws { throw BackendError.unconfigured }
    func handleAuthCallback(url: URL) async throws -> Bool { throw BackendError.unconfigured }
    func signOut() async throws {}
    func upsertBlobs(_ blobs: [EncryptedBlob]) async throws { throw BackendError.unconfigured }
    func tombstoneBlob(_ blobId: UUID) async throws { throw BackendError.unconfigured }
    func listBlobs() async throws -> [EncryptedBlob] { throw BackendError.unconfigured }
}

/// In-memory fake for tests and previews: instant sign-in, blob dictionary. @unchecked: state
/// is only ever touched from the main actor (tests + previews).
nonisolated final class FakeBackend: BackendServicing, @unchecked Sendable {
    var isConfigured: Bool { true }
    private(set) var signedIn = false
    private(set) var blobs: [UUID: EncryptedBlob] = [:]
    private(set) var tombstoned: Set<UUID> = []

    func seed(blobs: [EncryptedBlob], signedIn: Bool = false) {
        for blob in blobs { self.blobs[blob.blobId] = blob }
        self.signedIn = signedIn
    }

    func isSignedIn() async -> Bool { signedIn }
    func accessToken() async throws -> String {
        guard signedIn else { throw BackendError.notSignedIn }
        return "fake-token"
    }
    func signInWithApple(idToken: String, nonce: String?) async throws { signedIn = true }
    func sendMagicLink(email: String) async throws {}
    func handleAuthCallback(url: URL) async throws -> Bool { signedIn = true; return true }
    func signOut() async throws { signedIn = false }
    func upsertBlobs(_ blobs: [EncryptedBlob]) async throws {
        guard signedIn else { throw BackendError.notSignedIn }
        for blob in blobs { self.blobs[blob.blobId] = blob }
    }
    func tombstoneBlob(_ blobId: UUID) async throws {
        guard signedIn else { throw BackendError.notSignedIn }
        tombstoned.insert(blobId)
        blobs[blobId] = nil
    }
    func listBlobs() async throws -> [EncryptedBlob] {
        guard signedIn else { throw BackendError.notSignedIn }
        return blobs.values.sorted { $0.blobId.uuidString < $1.blobId.uuidString }
    }
}

nonisolated enum BackendClientKey: DependencyKey {
    static var liveValue: any BackendServicing {
        if let config = BackendConfig.load() { SupabaseBackend(config: config) } else { UnconfiguredBackend() }
    }
    static var testValue: any BackendServicing { UnconfiguredBackend() }
}

nonisolated extension DependencyValues {
    var backendClient: any BackendServicing {
        get { self[BackendClientKey.self] }
        set { self[BackendClientKey.self] = newValue }
    }
}
