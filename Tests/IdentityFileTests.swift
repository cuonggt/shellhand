import Testing
@testable import Shellhand

// No `import Foundation`: it makes `Host` ambiguous.

/// Identities in the file and in the store.
///
/// The file is where the one subtlety lives: **`identity` means a key path in
/// a document at version 4 or below and an identity's name at 5 or above**,
/// because that is what every list anyone exported before this means. Both
/// readings are pinned here, with a fixture each.
@Suite("Identities in the file")
nonisolated struct IdentityFileTests {
    // MARK: reading

    @Test("at version 1, identity is a key path, as it always was")
    func oldSpelling() throws {
        let document = try Portable.parse("""
            version: 1
            hosts:
              - name: db-01
                addr: 10.0.0.1
                identity: /keys/deploy
            """)
        let host = try #require(document.hosts.first)
        #expect(host.keyPath == "/keys/deploy")
        #expect(host.identity == "")
        #expect(document.identities.isEmpty)
    }

    @Test("at version 5, identity is a name and key is the path")
    func newSpelling() throws {
        let document = try Portable.parse("""
            version: 5
            identities:
              - name: deploy
                user: deploy
                key: ~/.ssh/id_ed25519
            groups:
              - name: Production
                identity: deploy
            hosts:
              - name: db-01
                addr: 10.0.0.1
                identity: deploy
                key: /keys/host-only
            """)
        #expect(document.identities == [Portable.Identity(
            name: "deploy", user: "deploy", keyPath: "~/.ssh/id_ed25519")])
        let host = try #require(document.hosts.first)
        #expect(host.identity == "deploy")
        #expect(host.keyPath == "/keys/host-only")
        #expect(document.groups.first?.identity == "deploy")
    }

    @Test("a file below version 5 may not carry a key, so neither word is read two ways")
    func keyNeedsVersionFive() {
        #expect(throws: PortableError.self) {
            try Portable.parse("""
                version: 1
                hosts:
                  - name: db-01
                    addr: 10.0.0.1
                    key: /keys/deploy
                """)
        }
    }

    @Test("a file below version 5 may not carry identities either")
    func identitiesNeedVersionFive() {
        #expect(throws: PortableError.self) {
            try Portable.parse("""
                version: 4
                identities:
                  - name: deploy
                """)
        }
    }

    @Test("an identity nothing declares is refused rather than invented")
    func unknownIdentity() throws {
        let document = try Portable.parse("""
            version: 5
            hosts:
              - name: db-01
                addr: 10.0.0.1
                identity: nobody
            """)
        // The document parses — the name is text — and the merge is where it
        // has to resolve. Inventing an empty identity would take the host's
        // login away and report success.
        #expect(throws: PortableError.self) {
            try Portable.merge(document, into: Snapshot())
        }
    }

    @Test("two identities of one name are refused, as two hosts of one name are")
    func duplicateNames() {
        #expect(throws: PortableError.self) {
            try Portable.parse("""
                version: 5
                identities:
                  - name: deploy
                  - name: DEPLOY
                """)
        }
    }

    @Test("a version past what this reads is refused")
    func tooNew() {
        #expect(throws: PortableError.self) {
            try Portable.parse("version: 6")
        }
    }

    // MARK: writing

    @Test("a list with no identities is still written as it was, so older copies read it")
    func noIdentities() throws {
        let text = try Portable.export(
            groups: [], hosts: [Shellhand.Host(
                id: "h", name: "db-01", addr: "10.0.0.1", keyPath: "/keys/deploy")])
        #expect(text.contains("version: 1"))
        // The old spelling, because the file says 1.
        #expect(text.contains("identity: /keys/deploy"))
        #expect(!text.contains("key: /keys/deploy"))
    }

    @Test("a list with identities says version 5 and writes key for a path")
    func withIdentities() throws {
        let identity = Shellhand.Identity(
            id: "i1", name: "deploy", user: "deploy", keyPath: "~/.ssh/id_ed25519")
        let host = Shellhand.Host(
            id: "h", name: "db-01", addr: "10.0.0.1", keyPath: "/keys/host-only",
            identityId: "i1")
        let text = try Portable.export(groups: [], hosts: [host], identities: [identity])
        #expect(text.contains("version: 5"))
        #expect(text.contains("identity: deploy"))
        #expect(text.contains("key: /keys/host-only"))
        #expect(text.contains("key: ~/.ssh/id_ed25519"))
    }

    @Test("an export with identities reads back as what it was")
    func roundTrip() throws {
        let identity = Shellhand.Identity(
            id: "i1", name: "deploy", user: "deploy", keyPath: "~/.ssh/id_ed25519")
        let group = Shellhand.Group(id: "g", name: "Production", identityId: "i1")
        let host = Shellhand.Host(
            id: "h", name: "db-01", addr: "10.0.0.1", identityId: "i1", groupId: "g")
        let text = try Portable.export(
            groups: [group], hosts: [host], identities: [identity])

        let read = try Portable.parse(text)
        #expect(read.version == 5)
        #expect(read.identities == [Portable.Identity(
            name: "deploy", user: "deploy", keyPath: "~/.ssh/id_ed25519")])
        #expect(read.hosts.first?.identity == "deploy")
        #expect(read.groups.first?.identity == "deploy")

        // And folding it into an empty store gives the pointers back.
        let plan = try Portable.merge(read, into: Snapshot())
        let made = try #require(plan.identities.first)
        #expect(made.name == "deploy")
        #expect(plan.hosts.first?.identityId == made.id)
        #expect(plan.groups.first?.identityId == made.id)
    }

    // MARK: folding one in

    @Test("importing the same file twice points at the one record")
    func twice() throws {
        let text = """
            version: 5
            identities:
              - name: deploy
                user: deploy
            hosts:
              - name: db-01
                addr: 10.0.0.1
                identity: deploy
            """
        let first = try Portable.merge(try Portable.parse(text), into: Snapshot())
        let identity = try #require(first.identities.first)
        let snapshot = Snapshot(
            groups: [], hosts: first.hosts, identities: first.identities)

        let again = try Portable.merge(try Portable.parse(text), into: snapshot)
        // Nothing to add or change the second time round.
        #expect(again.identities.isEmpty)
        #expect(again.hosts.isEmpty)
        #expect(again.unchanged == 2)
        // And the host still points at the record that was already here.
        #expect(snapshot.hosts.first?.identityId == identity.id)
    }

    @Test("a host may point at an identity already in the store without declaring it")
    func pointsAtOneAlreadyHere() throws {
        let here = Shellhand.Identity(id: "i1", name: "deploy", user: "deploy")
        let plan = try Portable.merge(
            try Portable.parse("""
                version: 5
                hosts:
                  - name: db-01
                    addr: 10.0.0.1
                    identity: deploy
                """),
            into: Snapshot(identities: [here]))
        #expect(plan.identities.isEmpty)
        #expect(plan.hosts.first?.identityId == "i1")
    }

    @Test("an import that says nothing about the identity keeps the one already set")
    func keepsWhatIsSet() throws {
        let here = Shellhand.Identity(id: "i1", name: "deploy")
        let host = Shellhand.Host(
            id: "h", name: "db-01", addr: "10.0.0.1", identityId: "i1")
        let plan = try Portable.merge(
            try Portable.parse("""
                version: 1
                hosts:
                  - name: db-01
                    addr: 10.0.0.2
                """),
            into: Snapshot(hosts: [host], identities: [here]))
        // The address changed and the pointer survived: an import fills in
        // and corrects, and never blanks.
        #expect(plan.hosts.first?.addr == "10.0.0.2")
        #expect(plan.hosts.first?.identityId == "i1")
    }
}

/// The store's side: the record, the two pointer columns, and what deleting
/// one does to them. Against a scratch database, never the real list.
@Suite("Identities in the store")
nonisolated struct IdentityStoreTests {
    private func scratch() throws -> Store {
        try Store(path: TestScratch.database())
    }

    @Test("an identity saved without an id is given one, and reads back whole")
    func roundTrip() throws {
        let store = try scratch()
        let saved = try store.save(Identity(
            name: "  deploy  ", user: "deploy", keyPath: "~/.ssh/id_ed25519"))
        #expect(!saved.id.isEmpty)
        #expect(saved.name == "deploy")

        let read = try #require(try store.snapshot().identities.first)
        #expect(read.id == saved.id)
        #expect(read.name == "deploy")
        #expect(read.user == "deploy")
        #expect(read.keyPath == "~/.ssh/id_ed25519")
    }

    /// The third edit a new field needs, after the model and the migration:
    /// the hand-written row mapping. Missing it, the field reads and writes
    /// as its default for ever with no error anywhere — which is exactly how
    /// this trap was found the first time.
    @Test("a host's and a group's pointer survive a write and a read")
    func pointersPersist() throws {
        let store = try scratch()
        let identity = try store.save(Identity(name: "deploy", user: "deploy"))
        _ = try store.save(Group(name: "Production", identityId: identity.id))
        _ = try store.save(Shellhand.Host(
            name: "db-01", addr: "10.0.0.1", identityId: identity.id))

        let snapshot = try store.snapshot()
        #expect(snapshot.hosts.first?.identityId == identity.id)
        #expect(snapshot.groups.first?.identityId == identity.id)
    }

    @Test("deleting an identity leaves nothing pointing at a record that is gone")
    func deleteClearsPointers() throws {
        let store = try scratch()
        let identity = try store.save(Identity(name: "deploy", user: "deploy"))
        _ = try store.save(Group(name: "Production", identityId: identity.id))
        _ = try store.save(Shellhand.Host(
            name: "db-01", addr: "10.0.0.1", identityId: identity.id))

        try store.deleteIdentity(id: identity.id)

        let snapshot = try store.snapshot()
        #expect(snapshot.identities.isEmpty)
        // Cleared, not dangling: a host left naming a deleted identity
        // resolves to nothing in silence, which looks exactly like a host
        // that simply inherits less.
        #expect(snapshot.hosts.first?.identityId == "")
        #expect(snapshot.groups.first?.identityId == "")
        // And nothing else went with it.
        #expect(snapshot.hosts.count == 1)
        #expect(snapshot.groups.count == 1)
    }

    @Test("renaming an identity takes nothing with it, because the pointer is an id")
    func renameIsFree() throws {
        let store = try scratch()
        var identity = try store.save(Identity(name: "deploy", user: "deploy"))
        _ = try store.save(Shellhand.Host(
            name: "db-01", addr: "10.0.0.1", identityId: identity.id))

        identity.name = "deploy key"
        _ = try store.save(identity)

        let snapshot = try store.snapshot()
        #expect(snapshot.identities.first?.name == "deploy key")
        #expect(snapshot.hosts.first?.identityId == identity.id)
    }

    @Test("a plan writes identities before the records that point at them")
    func applyOrder() throws {
        let store = try scratch()
        let plan = try Portable.merge(
            try Portable.parse("""
                version: 5
                identities:
                  - name: deploy
                    user: deploy
                    key: ~/.ssh/id_ed25519
                hosts:
                  - name: db-01
                    addr: 10.0.0.1
                    identity: deploy
                """),
            into: Snapshot())
        try store.apply(plan)

        let snapshot = try store.snapshot()
        let identity = try #require(snapshot.identities.first)
        #expect(identity.name == "deploy")
        #expect(snapshot.hosts.first?.identityId == identity.id)
    }

    @Test("an old store gains the identities table and the two columns")
    func migrates() throws {
        // A store made by this build has already run every migration; what
        // matters is that the new ones are additive and that a list written
        // before them still reads. Opening the same file twice runs the
        // migrator twice, which is the cheapest check that it is idempotent.
        let path = TestScratch.database()
        let first = try Store(path: path)
        _ = try first.save(Shellhand.Host(name: "db-01", addr: "10.0.0.1"))
        let again = try Store(path: path)
        let snapshot = try again.snapshot()
        #expect(snapshot.hosts.count == 1)
        #expect(snapshot.identities.isEmpty)
    }
}
