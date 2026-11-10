import Foundation
import Security

/// Passwords, in the system's own keychain.
///
/// **The store never holds one.** It is an ordinary SQLite file, and the YAML
/// export is meant for a dotfiles repository: an identity there says only
/// that the machine takes a password and who to log in as. The password
/// itself is filed here, under the identity's id — or, for a host's or a
/// group's own, under `account(host:)` or `account(group:)`.
///
/// The file-based keychain rather than the data-protection one, which on
/// macOS wants an entitlement a Developer ID app does not carry. What guards
/// an item is the signature: the askpass helper ssh runs is this same bundle,
/// so it reads what the window wrote without anyone being asked again.
///
/// Recovered close to verbatim from the pre-reset bundle, where it shipped
/// before the MVP cut took it out. The one rename is `credentialID` to
/// `identityID`: the record it files under is an identity now.
nonisolated enum Keychain {
    /// What these items are filed under — Shellhand's own.
    ///
    /// `SHELLHAND_KEYCHAIN_SERVICE` moves them somewhere else, which is how
    /// anything automated keeps its passwords out of the user's. It is
    /// carried to the askpass helper with the rest of the environment, so
    /// both halves agree about where to look. **This is the same trap
    /// `@AppStorage` sets**: the keychain is keyed by the signature and the
    /// service, not by `--db`, so a scratch copy and a test host reach the
    /// real items unless they are sent elsewhere.
    static var service: String {
        let named = ProcessInfo.processInfo.environment[serviceVariable] ?? ""
        return named.isEmpty ? "Shellhand" : named
    }

    static let serviceVariable = "SHELLHAND_KEYCHAIN_SERVICE"

    /// What a host's own password is filed under, and a group's. An
    /// identity's is its bare id, as it always was; these say what they
    /// belong to, so a host's id can never be read as an identity's.
    static func account(host id: String) -> String { "host:" + id }
    static func account(group id: String) -> String { "group:" + id }

    /// The password filed under `account` — an identity's id, or
    /// `account(host:)` or `(group:)` — or nil where none has been typed yet,
    /// which is a thing to ask about rather than a failure.
    static func password(for account: String, service: String = Keychain.service) throws
        -> String?
    {
        var query = base(account, service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError(status)
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Writes a password, replacing whatever was there. An empty one removes
    /// the item instead: a password of nothing is not a password.
    static func save(
        _ password: String, for account: String, service: String = Keychain.service
    ) throws {
        guard !password.isEmpty else { return try remove(account, service: service) }
        let data = Data(password.utf8)
        let update = SecItemUpdate(
            base(account, service) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(update) }

        var add = base(account, service)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Shellhand"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    /// Forgets a password. One that was not there is already forgotten.
    static func remove(_ account: String, service: String = Keychain.service) throws {
        let status = SecItemDelete(base(account, service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status)
        }
    }

    /// Whether one is stored. A failure reads as "no", because every caller
    /// is drawing a row and none of them has anywhere to put an error.
    static func has(_ account: String, service: String = Keychain.service) -> Bool {
        ((try? password(for: account, service: service)) ?? nil) != nil
    }

    /// The service is a parameter only so a test can file its own items
    /// somewhere unmistakable and take them away again.
    private static func base(_ account: String, _ service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

nonisolated struct KeychainError: LocalizedError, Sendable {
    let status: OSStatus

    init(_ status: OSStatus) { self.status = status }

    var errorDescription: String? {
        let said = SecCopyErrorMessageString(status, nil) as String?
        return said ?? "the keychain refused that (\(status))"
    }
}
