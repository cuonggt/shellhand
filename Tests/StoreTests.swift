import Foundation
import Testing
@testable import Shellhand

/// The store, against a scratch file — never the real list.
@Suite("Store")
nonisolated struct StoreTests {
    private func scratch() throws -> Store {
        try Store(path: TestScratch.database())
    }

    @Test("an empty store reads as an empty list")
    func empty() throws {
        let store = try scratch()
        let snapshot = try store.snapshot()
        #expect(snapshot.hosts.isEmpty)
        #expect(snapshot.groups.isEmpty)
    }

    @Test("a host saved without an id is given one, and reads back whole")
    func roundTrip() throws {
        let store = try scratch()
        let saved = try store.save(Host(
            name: "  web  ", addr: "10.0.0.1", port: 2222, user: "deploy",
            tags: ["edge", "eu"]))
        #expect(!saved.id.isEmpty)
        #expect(saved.name == "web")

        let read = try #require(try store.snapshot().hosts.first)
        #expect(read.id == saved.id)
        #expect(read.addr == "10.0.0.1")
        #expect(read.port == 2222)
        #expect(read.user == "deploy")
        #expect(read.tags == ["edge", "eu"])
    }

    @Test("saving twice under one id updates rather than duplicates")
    func upsert() throws {
        let store = try scratch()
        var host = try store.save(Host(name: "web", addr: "10.0.0.1"))
        host.addr = "10.0.0.2"
        _ = try store.save(host)
        let hosts = try store.snapshot().hosts
        #expect(hosts.count == 1)
        #expect(hosts.first?.addr == "10.0.0.2")
    }

    @Test("deleting a group hands what was under it to the group above")
    func deleteGroupReparents() throws {
        let store = try scratch()
        let top = try store.save(Group(name: "Production"))
        let middle = try store.save(Group(name: "EU", parentId: top.id))
        let leaf = try store.save(Group(name: "Frankfurt", parentId: middle.id))
        let host = try store.save(Host(name: "web", addr: "10.0.0.1", groupId: middle.id))

        try store.deleteGroup(id: middle.id)

        let snapshot = try store.snapshot()
        #expect(snapshot.groups.count == 2)
        #expect(snapshot.groups.first { $0.id == leaf.id }?.parentId == top.id)
        #expect(snapshot.hosts.first { $0.id == host.id }?.groupId == top.id)
    }

    @Test("deleting a top-level group leaves what was under it at the top")
    func deleteTopGroup() throws {
        let store = try scratch()
        let top = try store.save(Group(name: "Production"))
        let host = try store.save(Host(name: "web", addr: "10.0.0.1", groupId: top.id))
        try store.deleteGroup(id: top.id)
        #expect(try store.snapshot().hosts.first { $0.id == host.id }?.groupId == "")
    }

    @Test("a group cannot be made its own parent")
    func groupSelfParent() throws {
        let store = try scratch()
        var group = try store.save(Group(name: "Production"))
        group.parentId = group.id
        let saved = try store.save(group)
        #expect(saved.parentId == "")
    }

    @Test("the list survives being closed and opened again")
    func reopen() throws {
        let path = TestScratch.database()
        let first = try Store(path: path)
        _ = try first.save(Host(name: "web", addr: "10.0.0.1", tags: ["edge"]))

        let second = try Store(path: path)
        let hosts = try second.snapshot().hosts
        #expect(hosts.count == 1)
        #expect(hosts.first?.tags == ["edge"])
    }
}
