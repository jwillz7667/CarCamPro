import Foundation
import Security

/// Keychain-backed storage for session tokens.
///
/// Threading: the class is `final` + `Sendable` but every method acquires an
/// internal `NSLock` because the Keychain APIs are reentrancy-safe but not
/// free of races when two callers try to rotate the same item concurrently
/// (e.g. two requests hitting a 401 in parallel and both calling `/refresh`).
///
/// Access control: items are stored with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so tokens survive
/// backgrounding but don't sync to iCloud Keychain and don't migrate to a
/// new device via backup. That's what we want for bearer auth.
public final class AuthTokenStore: @unchecked Sendable {
    // Every member is explicitly `nonisolated` — the class does its own
    // locking via an `NSLock`, so Swift 6's default main-actor inference
    // for global `static let` is incorrect here.
    /// Snapshot of stored credentials. Value type — cheap to copy.
    /// `Codable` so the whole bundle serializes cleanly into a single
    /// Keychain blob; `Equatable` for test assertions.
    public struct Snapshot: Codable, Sendable, Equatable {
        public let tokens: APISessionTokens
        public let user: APIAuthUser

        public init(tokens: APISessionTokens, user: APIAuthUser) {
            self.tokens = tokens
            self.user = user
        }
    }

    nonisolated public static let shared = AuthTokenStore(service: "pro.carcam.auth")

    private let service: String
    private let account = "primary"
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    nonisolated public init(service: String) {
        self.service = service
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Public API

    nonisolated public func load() -> Snapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let data = readKeychain() else { return nil }
        return try? decoder.decode(Snapshot.self, from: data)
    }

    nonisolated public func save(_ snapshot: Snapshot) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? encoder.encode(snapshot) else { return }
        writeKeychain(data)
    }

    nonisolated public func clear() {
        lock.lock(); defer { lock.unlock() }
        deleteKeychain()
    }

    // MARK: - Keychain wrappers

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readKeychain() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func writeKeychain(_ data: Data) {
        var attrs = baseQuery()
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            SecItemAdd(attrs as CFDictionary, nil)
        }
    }

    private func deleteKeychain() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
