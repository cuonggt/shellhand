import Foundation
import Testing
@testable import Shellhand

@Suite("Documents")
nonisolated struct PortableTests {
    @Test("a document reads into records")
    func parse() throws {
        let document = try Portable.parse("""
            version: 1
            groups:
              - name: Production
                user: ubuntu
              - name: EU
                parent: Production
            hosts:
              - name: web
                addr: 10.0.0.1
                port: 2222
                group: EU
                tags: [edge, eu]
            """)
        #expect(document.version == 1)
        #expect(document.hosts.first?.tags == ["edge", "eu"])
        #expect(document.groups.count == 2)
        #expect(document.passedOver.isEmpty)
    }

    /// The same rule `forwards` set, for the same reason: every export
    /// written before these were cut still carries them, and refusing a file
    /// whole over a feature that no longer exists would make somebody's own
    /// export unimportable.
    @Test("a file still carrying keys, credentials and snippets imports, without them")
    func recordsArePassedOver() throws {
        let document = try Portable.parse("""
            version: 3
            credentials:
              - name: Deploy
                kind: key
                user: deploy
                identity: /keys/deploy
            groups:
              - name: Production
                credential: Deploy
                startup: Warm up
            hosts:
              - name: web
                addr: 10.0.0.1
                credential: Deploy
                startup: Warm up
            snippets:
              - name: Warm up
                script: uptime
            """)
        #expect(document.hosts.count == 1)
        #expect(document.hosts.first?.addr == "10.0.0.1")
        #expect(document.groups.count == 1)
        #expect(document.passedOver == ["credentials", "snippets", "startup snippets"])

        let plan = try Portable.merge(document, into: Snapshot())
        #expect(plan.hosts.count == 1)
        #expect(plan.result.passedOver == ["credentials", "snippets", "startup snippets"])
        // Apart from the changes, because nothing is written for them: a row
        // in that list would leave Import enabled with nothing to do.
        #expect(!plan.result.changes.contains { $0.kind == "credential" })
    }

    @Test("a credential named by a record, with no section of its own, is still said")
    func namedCredentialIsSaid() throws {
        let document = try Portable.parse(
            "hosts:\n  - name: web\n    addr: 10.0.0.1\n    credential: Deploy\n")
        #expect(document.passedOver == ["credentials"])
    }

    @Test("a file naming none of them says nothing about them")
    func nothingPassedOver() throws {
        let document = try Portable.parse("hosts:\n  - name: web\n    addr: 10.0.0.1\n")
        #expect(document.passedOver.isEmpty)
        #expect(try Portable.merge(document, into: Snapshot()).result.passedOver.isEmpty)
    }

    /// Every export written before port forwarding was removed carries the
    /// key. A file is refused whole when it holds something unknown, so
    /// refusing this one would make those files unimportable over a feature
    /// that is gone.
    @Test("a file still carrying forwarding rules imports, without them")
    func forwardsArePassedOver() throws {
        let document = try Portable.parse("""
            version: 2
            hosts:
              - name: web
                addr: 10.0.0.1
                forwards:
                  - kind: local
                    listen: 8080
                    dest: 127.0.0.1:80
            """)
        #expect(document.hosts.count == 1)
        #expect(document.hosts.first?.addr == "10.0.0.1")
        #expect(document.hosts.first?.hadForwards == true)

        let plan = try Portable.merge(document, into: Snapshot())
        #expect(plan.hosts.count == 1)
        #expect(plan.result.changes.contains {
            $0.action == "forwarding rules passed over"
        })
    }

    @Test("a host with no forwarding key is not reported as having had one")
    func noForwardsNoNote() throws {
        let document = try Portable.parse("""
            version: 1
            hosts:
              - name: web
                addr: 10.0.0.1
            """)
        #expect(document.hosts.first?.hadForwards == false)
        let plan = try Portable.merge(document, into: Snapshot())
        #expect(!plan.result.changes.contains { $0.action.contains("forwarding") })
    }

    @Test("a key that is not a field is refused, because silence reads as success")
    func unknownKey() {
        #expect(throws: PortableError.self) {
            try Portable.parse("version: 1\nhost:\n  - name: web\n    addr: 10.0.0.1\n")
        }
        #expect(throws: PortableError.self) {
            try Portable.parse("version: 1\nhosts:\n  - name: web\n    address: 10.0.0.1\n")
        }
    }

    @Test("a host needs a name and an address")
    func hostNeeds() {
        #expect(throws: PortableError.self) { try Portable.parse("hosts:\n  - addr: 10.0.0.1\n") }
        #expect(throws: PortableError.self) { try Portable.parse("hosts:\n  - name: web\n") }
    }

    @Test("two records of a kind cannot share a name, however it is cased")
    func duplicates() {
        #expect(throws: PortableError.self) {
            try Portable.parse("""
                hosts:
                  - name: web
                    addr: 10.0.0.1
                  - name: WEB
                    addr: 10.0.0.2
                """)
        }
    }

    @Test("a version this cannot read is said so plainly")
    func futureVersion() {
        #expect(throws: PortableError.self) { try Portable.parse("version: 9\n") }
    }

    @Test("an empty file is a document with nothing in it")
    func emptyFile() throws {
        #expect(try Portable.parse("").isEmpty)
        #expect(try Portable.parse("# only a comment\n").isEmpty)
    }

    // MARK: writing

    @Test("an export reads back as the same list")
    func roundTrip() throws {
        let group = Group(id: "g", name: "Production", user: "ubuntu")
        let child = Group(id: "g2", name: "EU", parentId: "g")
        let host = Host(id: "h", name: "web", addr: "10.0.0.1", port: 2222,
                        identity: "~/.ssh/id_ed25519", groupId: "g2", tags: ["edge"])

        let yaml = try Portable.export(groups: [group, child], hosts: [host])
        let document = try Portable.parse(yaml)

        #expect(document.version == 1)
        #expect(document.hosts.first?.name == "web")
        #expect(document.hosts.first?.port == 2222)
        #expect(document.hosts.first?.group == "EU")
        #expect(document.hosts.first?.identity == "~/.ssh/id_ed25519")
        #expect(document.hosts.first?.tags == ["edge"])
        #expect(document.groups.first { $0.name == "EU" }?.parent == "Production")
        // Nothing of the three is written any more, so a round trip has
        // nothing to pass over the second time.
        #expect(document.passedOver.isEmpty)
    }

    @Test("a group's name stays its name, so a round trip does not grow it")
    func groupNameStable() throws {
        let group = Group(id: "g", name: "Production")
        let child = Group(id: "g2", name: "EU", parentId: "g")
        var yaml = try Portable.export(groups: [group, child], hosts: [])
        for _ in 0..<3 {
            let document = try Portable.parse(yaml)
            let plan = try Portable.merge(document, into: Snapshot())
            yaml = try Portable.export(groups: plan.groups, hosts: plan.hosts)
        }
        #expect(try Portable.parse(yaml).groups.map(\.name).sorted() == ["EU", "Production"])
    }

    @Test("exporting the same list twice gives the same file, so a diff means something")
    func stable() throws {
        let hosts = [
            Host(id: "b", name: "beta", addr: "10.0.0.2"),
            Host(id: "a", name: "Alpha", addr: "10.0.0.1"),
        ]
        let first = try Portable.export(groups: [], hosts: hosts)
        let second = try Portable.export(groups: [], hosts: hosts.reversed())
        #expect(first == second)
        #expect(first.contains("# Shellhand host list"))
    }

    @Test("a file with nothing new to say is version 1, and ssh settings make it 4")
    func versions() throws {
        let host = Host(id: "h", name: "web", addr: "10.0.0.1")
        #expect(try Portable.parse(try Portable.export(groups: [], hosts: [host])).version == 1)

        var withOptions = host
        withOptions.sshOptions = ["Compression=yes"]
        let four = try Portable.export(groups: [], hosts: [withOptions])
        #expect(try Portable.parse(four).version == 4)
    }

    // MARK: folding one into the other

    private func merge(_ yaml: String, into snapshot: Snapshot = Snapshot())
        throws -> Portable.Plan {
        try Portable.merge(try Portable.parse(yaml), into: snapshot)
    }

    @Test("a host nothing has heard of is added, with an id of its own")
    func addsHost() throws {
        let plan = try merge("hosts:\n  - name: web\n    addr: 10.0.0.1\n")
        #expect(plan.hosts.count == 1)
        #expect(!(plan.hosts.first?.id.isEmpty ?? true))
        #expect(plan.result.added == 1)
    }

    @Test("a host already here keeps its id, so what hangs off it is not orphaned")
    func keepsID() throws {
        let snapshot = Snapshot(hosts: [Host(id: "kept", name: "web", addr: "10.0.0.1")])
        let plan = try merge("hosts:\n  - name: WEB\n    addr: 10.0.0.2\n", into: snapshot)
        #expect(plan.hosts.first?.id == "kept")
        #expect(plan.hosts.first?.addr == "10.0.0.2")
        #expect(plan.result.updated == 1)
    }

    @Test("a field the document leaves out keeps what the store had")
    func fillsRatherThanBlanks() throws {
        let snapshot = Snapshot(hosts: [
            Host(id: "h", name: "web", addr: "10.0.0.1", port: 2222, user: "deploy",
                 tags: ["edge"]),
        ])
        let plan = try merge("hosts:\n  - name: web\n    addr: 10.0.0.1\n", into: snapshot)
        // Nothing changed, so nothing is written.
        #expect(plan.hosts.isEmpty)
        #expect(plan.unchanged == 1)
    }

    @Test("a host naming a group nothing has heard of creates it")
    func createsGroup() throws {
        let plan = try merge("hosts:\n  - name: web\n    addr: 10.0.0.1\n    group: Production\n")
        #expect(plan.groups.map(\.name) == ["Production"])
        #expect(plan.hosts.first?.groupId == plan.groups.first?.id)
    }

    @Test("a parent resolves even when the document lists the child first")
    func parentAfterChild() throws {
        let plan = try merge("""
            groups:
              - name: EU
                parent: Production
              - name: Production
            """)
        let production = plan.groups.first { $0.name == "Production" }
        #expect(plan.groups.first { $0.name == "EU" }?.parentId == production?.id)
    }

    @Test("a group that is its own ancestor is refused before anything is written")
    func cycle() {
        #expect(throws: PortableError.self) {
            try merge("""
                groups:
                  - name: A
                    parent: B
                  - name: B
                    parent: A
                """)
        }
    }

    @Test("importing the same file twice changes nothing the second time")
    func idempotent() throws {
        let yaml = """
            groups:
              - name: Production
                user: ubuntu
            hosts:
              - name: web
                addr: 10.0.0.1
                group: Production
                tags: [edge]
            """
        let path = TestScratch.database("s.sqlite")
        let store = try Store(path: path)

        let first = try Portable.merge(
            try Portable.parse(yaml), into: try store.snapshot())
        try store.apply(first)
        #expect(first.result.added == 2)

        let second = try Portable.merge(
            try Portable.parse(yaml), into: try store.snapshot())
        #expect(second.isEmpty)
        #expect(second.result.unchanged == 2)
        #expect(try store.snapshot().hosts.count == 1)
    }
}
