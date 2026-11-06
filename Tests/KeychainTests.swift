import Foundation
import Testing
@testable import Shellhand

/// Passwords in the system's keychain — under a service of this run's own,
/// never the user's.
///
/// `Keychain.service` is "Shellhand" unless `SHELLHAND_KEYCHAIN_SERVICE` says
/// otherwise, and every call here passes a service of its own instead: a
/// fresh name per run, so nothing an earlier build wrote is ever read back.
/// That is more than tidiness. **A keychain item is guarded by the signature
/// that made it**, the test host is rebuilt on every run, and reading one
/// across builds is how a run stops on a question put to whoever is at the
/// Mac — the same shape as the privacy prompt that hung every file-pane test
/// until they were pointed at a scratch home.
///
/// Each test takes its items away on the way out, whether or not it passed.
@Suite("Passwords in the keychain")
nonisolated struct KeychainTests {
    private func ownService() -> String { "Shellhand test \(UUID().uuidString)" }
    private func ownID() -> String { "identity-\(UUID().uuidString)" }

    @Test("a password written is read back, replaced in place, and forgotten")
    func roundTrip() throws {
        let service = ownService()
        let id = ownID()
        defer { try? Keychain.remove(id, service: service) }

        #expect(try Keychain.password(for: id, service: service) == nil)
        #expect(!Keychain.has(id, service: service))

        try Keychain.save("one", for: id, service: service)
        #expect(try Keychain.password(for: id, service: service) == "one")
        #expect(Keychain.has(id, service: service))

        // Replaced, not added beside: a second item under one id would be a
        // password nobody could predict the reading of.
        try Keychain.save("two", for: id, service: service)
        #expect(try Keychain.password(for: id, service: service) == "two")

        try Keychain.remove(id, service: service)
        #expect(try Keychain.password(for: id, service: service) == nil)
        #expect(!Keychain.has(id, service: service))
    }

    @Test("an empty password is not a password — it forgets instead")
    func emptyForgets() throws {
        let service = ownService()
        let id = ownID()
        defer { try? Keychain.remove(id, service: service) }

        try Keychain.save("something", for: id, service: service)
        try Keychain.save("", for: id, service: service)
        #expect(try Keychain.password(for: id, service: service) == nil)
    }

    @Test("forgetting one that was never there is not a failure")
    func forgettingNothing() throws {
        // It is already forgotten, which is what was asked for.
        try Keychain.remove(ownID(), service: ownService())
    }

    @Test("two identities keep their own passwords")
    func twoApart() throws {
        let service = ownService()
        let one = ownID()
        let two = ownID()
        defer {
            try? Keychain.remove(one, service: service)
            try? Keychain.remove(two, service: service)
        }
        try Keychain.save("first", for: one, service: service)
        try Keychain.save("second", for: two, service: service)
        #expect(try Keychain.password(for: one, service: service) == "first")
        #expect(try Keychain.password(for: two, service: service) == "second")
        try Keychain.remove(one, service: service)
        // Taking one away leaves the other where it was.
        #expect(try Keychain.password(for: two, service: service) == "second")
    }

    @Test("the service a run files under is the variable's, so nothing lands in the user's")
    func serviceComesFromTheEnvironment() {
        // The variable is what `TestRun` and anything automated set to keep
        // their passwords out of the user's keychain, and what the askpass
        // helper is handed so both halves look in the same place.
        #expect(Keychain.serviceVariable == "SHELLHAND_KEYCHAIN_SERVICE")
        let named = ProcessInfo.processInfo.environment[Keychain.serviceVariable] ?? ""
        #expect(Keychain.service == (named.isEmpty ? "Shellhand" : named))
    }
}
