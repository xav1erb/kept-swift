import CryptoKit
import Dependencies
import Foundation
import Security

// The master key (C2/F3, M2-CONTRACTS §7.2): 32 random bytes in the iCloud Keychain
// (`kSecAttrSynchronizable` — Apple-E2E synced, "new phone, story follows you"). The key never
// leaves the Keychain except in memory for seal/open. No passphrase derivation in v1: the
// Keychain IS the recovery story; export (M7) is the user-readable escape hatch.

nonisolated protocol MasterKeyProviding: Sendable {
    /// Returns the existing key, creating and persisting one if none exists.
    func loadOrCreateKey() throws -> SymmetricKey
    /// Returns the existing key or nil — restore uses this (a fresh device with iCloud Keychain
    /// synced HAS the key; absence means there is nothing to restore with).
    func existingKey() throws -> SymmetricKey?
}

nonisolated enum MasterKeyError: Error {
    case keychain(OSStatus)
    case randomBytesFailed(OSStatus)
}

/// Live Keychain implementation. Device-verified behaviors (sync across devices) are on the M2
/// device checklist; simulator tests prove the code path.
nonisolated struct KeychainMasterKey: MasterKeyProviding {
    private static let service = "app.kept.masterkey"
    private static let account = "master"

    func loadOrCreateKey() throws -> SymmetricKey {
        if let key = try existingKey() { return key }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw MasterKeyError.randomBytesFailed(status) }
        let data = Data(bytes)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw MasterKeyError.keychain(addStatus) }
        return SymmetricKey(data: data)
    }

    func existingKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw MasterKeyError.keychain(status) }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw MasterKeyError.keychain(status)
        }
    }
}

/// Test/preview fake: a fixed in-memory key (never persisted).
nonisolated final class InMemoryMasterKey: MasterKeyProviding, @unchecked Sendable {
    private let key: SymmetricKey
    init(keyData: Data = Data(repeating: 0x2A, count: 32)) {
        self.key = SymmetricKey(data: keyData)
    }
    func loadOrCreateKey() throws -> SymmetricKey { key }
    func existingKey() throws -> SymmetricKey? { key }
}

nonisolated enum MasterKeyProviderKey: DependencyKey {
    static let liveValue: any MasterKeyProviding = KeychainMasterKey()
    static let testValue: any MasterKeyProviding = InMemoryMasterKey()
    static let previewValue: any MasterKeyProviding = InMemoryMasterKey()
}

extension DependencyValues {
    nonisolated var masterKeyProvider: any MasterKeyProviding {
        get { self[MasterKeyProviderKey.self] }
        set { self[MasterKeyProviderKey.self] = newValue }
    }
}
