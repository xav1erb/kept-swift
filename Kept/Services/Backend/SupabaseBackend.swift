import Foundation
import Supabase

// Live Supabase backend (supabase-swift v2). Auth: Sign in with Apple (id-token exchange) +
// email magic link over the `kept://auth-callback` scheme. Blobs: PostgREST upserts against
// `encrypted_blobs` (bytea payload travels as \x-hex). RLS scopes every row to auth.uid().

nonisolated struct BackendConfig: Sendable {
    let url: URL
    let anonKey: String

    /// nil until AppSecrets carries a key — the app then runs fully local (BackendError.unconfigured).
    static func load() -> BackendConfig? {
        guard !AppSecrets.supabaseAnonKey.isEmpty else { return nil }
        return BackendConfig(url: AppSecrets.supabaseURL, anonKey: AppSecrets.supabaseAnonKey)
    }
}

nonisolated final class SupabaseBackend: BackendServicing {
    private let client: SupabaseClient
    private let config: BackendConfig

    init(config: BackendConfig) {
        self.config = config
        self.client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
    }

    var isConfigured: Bool { true }

    func isSignedIn() async -> Bool {
        (try? await client.auth.session) != nil
    }

    func accessToken() async throws -> String {
        do {
            return try await client.auth.session.accessToken
        } catch {
            throw BackendError.notSignedIn
        }
    }

    func signInWithApple(idToken: String, nonce: String?) async throws {
        do {
            try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
        } catch {
            throw BackendError.transport(underlying: error)
        }
    }

    func sendMagicLink(email: String) async throws {
        do {
            try await client.auth.signInWithOTP(
                email: email,
                redirectTo: URL(string: "kept://auth-callback")
            )
        } catch {
            throw BackendError.transport(underlying: error)
        }
    }

    func handleAuthCallback(url: URL) async throws -> Bool {
        guard url.scheme == "kept" else { return false }
        do {
            try await client.auth.session(from: url)
            return true
        } catch {
            throw BackendError.transport(underlying: error)
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: - Blob transport

    private struct BlobRow: Codable {
        let user_id: UUID
        let blob_id: UUID
        let payload: String
        let envelope_version: Int
    }

    private struct BlobReadRow: Decodable {
        let blob_id: UUID
        let payload: String
        let envelope_version: Int
        let deleted_at: String?
    }

    private struct Tombstone: Encodable {
        let deleted_at: String
    }

    private func userId() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch {
            throw BackendError.notSignedIn
        }
    }

    func upsertBlobs(_ blobs: [EncryptedBlob]) async throws {
        guard !blobs.isEmpty else { return }
        let uid = try await userId()
        let rows = blobs.map {
            BlobRow(
                user_id: uid, blob_id: $0.blobId,
                payload: Self.hexEncode($0.payload), envelope_version: $0.envelopeVersion
            )
        }
        do {
            try await client.from("encrypted_blobs")
                .upsert(rows, onConflict: "user_id,blob_id")
                .execute()
        } catch {
            throw BackendError.transport(underlying: error)
        }
    }

    func tombstoneBlob(_ blobId: UUID) async throws {
        _ = try await userId()
        do {
            try await client.from("encrypted_blobs")
                .update(Tombstone(deleted_at: ISO8601DateFormatter().string(from: .now)))
                .eq("blob_id", value: blobId)
                .execute()
        } catch {
            throw BackendError.transport(underlying: error)
        }
    }

    func listBlobs() async throws -> [EncryptedBlob] {
        _ = try await userId()
        let rows: [BlobReadRow]
        do {
            rows = try await client.from("encrypted_blobs")
                .select("blob_id,payload,envelope_version,deleted_at")
                .execute()
                .value
        } catch {
            throw BackendError.transport(underlying: error)
        }
        return try rows
            .filter { $0.deleted_at == nil }
            .map { row in
                guard let payload = Self.hexDecode(row.payload) else {
                    throw BackendError.transport(underlying: URLError(.cannotDecodeContentData))
                }
                return EncryptedBlob(blobId: row.blob_id, envelopeVersion: row.envelope_version, payload: payload)
            }
    }

    // MARK: - bytea ↔ \x-hex

    static func hexEncode(_ data: Data) -> String {
        "\\x" + data.map { String(format: "%02x", $0) }.joined()
    }

    static func hexDecode(_ string: String) -> Data? {
        var hex = Substring(string)
        if hex.hasPrefix("\\x") { hex = hex.dropFirst(2) }
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
