import Foundation
import Testing
@testable import Shellhand

/// `Foundation.Host` exists, so the app's own has to be named.
private typealias AppHost = Shellhand.Host

/// The store the window talks to, against a scratch file — never the real
/// list.
///
/// Every call carries its own database path, so a `HostStore` pointed at a
/// temporary file reaches nothing of the user's. That is what makes these
/// cheap enough to write: no fixture, no fakes, and the same code path the
/// app runs.
@MainActor
@Suite("Host store")
struct HostStoreTests {
    private func scratch() -> HostStore {
        HostStore(dbPath: TestScratch.database())
    }

    /// A store holding Production, EU beneath it, and a host in each.
    private func peopled() async -> (HostStore, Group, Group) {
        let store = scratch()
        await store.refresh()
        let prod = await store.save(Group(name: "Production"))!
        let eu = await store.save(Group(name: "EU", parentId: prod.id))!
        await store.save(AppHost(name: "web", addr: "10.0.0.1", groupId: prod.id))
        await store.save(AppHost(name: "edge", addr: "10.0.0.2", groupId: eu.id))
        return (store, prod, eu)
    }

    // MARK: reading

    @Test("an empty store reads as an empty list, with no error")
    func empty() async {
        let store = scratch()
        await store.refresh()
        #expect(store.snapshot.hosts.isEmpty)
        #expect(store.snapshot.groups.isEmpty)
        #expect(store.lastError == nil)
        #expect(store.loading == false)
    }

    @Test("a saved host comes back, with an id, and the tree is rebuilt round it")
    func savesAHost() async {
        let store = scratch()
        await store.refresh()
        let saved = await store.save(AppHost(name: "web", addr: "10.0.0.1"))
        #expect(saved?.id.isEmpty == false)
        #expect(store.snapshot.hosts.map(\.name) == ["web"])
        // The index is rebuilt by the same write, not on the next read.
        #expect(store.ungrouped.map(\.name) == ["web"])
    }

    /// **The test that catches the three-edit trap.** A field needs the
    /// model, a migration *and* the hand-written row mapping at the bottom of
    /// `Store.swift`; miss the third and it reads and writes as its default
    /// for ever, with no error anywhere. Nothing but a round trip through the
    /// store notices, which is how the last one was found.
    @Test("what a host said it was survives the store")
    func osRoundTrips() async {
        let store = scratch()
        await store.refresh()
        var host = AppHost(name: "web", addr: "10.0.0.1")
        host.os = "ubuntu"
        _ = await store.save(host)
        #expect(store.snapshot.hosts.first?.os == "ubuntu")

        // And back out again, through a reader that has not seen the write —
        // which is what makes this a round trip rather than a cache check.
        let second = HostStore(dbPath: store.dbPath)
        await second.refresh()
        #expect(second.snapshot.hosts.first?.os == "ubuntu")
    }

    @Test("the tree the sidebar reads follows what was saved")
    func rebuildsTheTree() async {
        let (store, prod, eu) = await peopled()
        #expect(store.children(of: "").map(\.name) == ["Production"])
        #expect(store.children(of: prod.id).map(\.name) == ["EU"])
        #expect(store.hosts(in: eu.id).map(\.name) == ["edge"])
        #expect(store.hostsBeneath(prod.id).map(\.name) == ["edge", "web"])
        #expect(store.path(of: eu) == "Production / EU")
    }

    // MARK: moving things

    @Test("a host moves into a group, and back out of all of them")
    func movesAHost() async {
        let (store, prod, _) = await peopled()
        let web = store.snapshot.hosts.first { $0.name == "web" }!
        await store.move(host: web, toGroup: "")
        #expect(store.ungrouped.map(\.name) == ["web"])
        #expect(store.hosts(in: prod.id).isEmpty)
    }

    @Test("a group moves under another, and up to the top")
    func movesAGroup() async {
        let (store, prod, eu) = await peopled()
        #expect(await store.move(group: eu, toParent: "") == true)
        #expect(store.children(of: "").map(\.name) == ["EU", "Production"])

        let moved = store.group(eu.id)!
        #expect(await store.move(group: moved, toParent: prod.id) == true)
        #expect(store.children(of: prod.id).map(\.name) == ["EU"])
    }

    @Test("a group is refused the parent it already has")
    func refusesTheSameParent() async {
        let (store, prod, eu) = await peopled()
        #expect(await store.move(group: eu, toParent: prod.id) == false)
    }

    @Test("a group is refused itself as a parent")
    func refusesItself() async {
        let (store, _, eu) = await peopled()
        #expect(await store.move(group: eu, toParent: eu.id) == false)
    }

    /// The one that would make a loop, and the reason `move` answers Bool at
    /// all: a tree that closes on itself hangs every walk over it.
    @Test("a group is refused a parent that is already beneath it")
    func refusesItsOwnDescendant() async {
        let (store, prod, eu) = await peopled()
        #expect(await store.move(group: prod, toParent: eu.id) == false)
        #expect(store.group(prod.id)?.parentId == "")
    }

    // MARK: tags, which exist only because a host carries them

    @Test("renaming a tag rewrites every host carrying it, and says how many")
    func renamesATag() async {
        let store = scratch()
        await store.refresh()
        await store.save(AppHost(name: "a", addr: "10.0.0.1", tags: ["eu", "web"]))
        await store.save(AppHost(name: "b", addr: "10.0.0.2", tags: ["eu"]))
        await store.save(AppHost(name: "c", addr: "10.0.0.3", tags: ["us"]))

        #expect(await store.rename(tag: "eu", to: "europe") == 2)
        #expect(store.allTags.contains("europe"))
        #expect(!store.allTags.contains("eu"))
        #expect(store.snapshot.hosts.first { $0.name == "c" }?.tags == ["us"])
    }

    @Test("renaming onto a tag that already exists merges the two")
    func mergesATag() async {
        let store = scratch()
        await store.refresh()
        await store.save(AppHost(name: "a", addr: "10.0.0.1", tags: ["eu", "web"]))
        await store.refresh()

        #expect(await store.rename(tag: "eu", to: "web") == 1)
        #expect(store.snapshot.hosts.first?.tags == ["web"], "not web twice")
    }

    @Test("deleting a tag takes it off every host, because there is no list of tags")
    func deletesATag() async {
        let store = scratch()
        await store.refresh()
        await store.save(AppHost(name: "a", addr: "10.0.0.1", tags: ["eu", "web"]))
        await store.save(AppHost(name: "b", addr: "10.0.0.2", tags: ["eu"]))

        #expect(await store.delete(tag: "eu") == 2)
        #expect(store.allTags == ["web"])
    }

    // MARK: deleting

    @Test("a deleted host is gone from the list and from its group")
    func deletesAHost() async {
        let (store, prod, _) = await peopled()
        let web = store.snapshot.hosts.first { $0.name == "web" }!
        await store.delete(web)
        #expect(store.snapshot.hosts.map(\.name) == ["edge"])
        #expect(store.hosts(in: prod.id).isEmpty)
    }

    @Test("a deleted group is gone, and what it held is said beforehand")
    func deletesAGroup() async {
        let (store, _, eu) = await peopled()
        // The warning is what the dialog shows before anything happens.
        #expect(!store.deletionWarning(for: eu).isEmpty)
        await store.delete(eu)
        #expect(store.snapshot.groups.map(\.name) == ["Production"])
    }

    // MARK: import and export

    @Test("a list exported from one store imports into another")
    func roundTrip() async {
        let (source, _, _) = await peopled()
        let yaml = await source.exportYAML()
        #expect(yaml?.isEmpty == false)

        let destination = scratch()
        await destination.refresh()
        _ = await destination.importYAML(yaml!, dryRun: false)
        #expect(Set(destination.snapshot.hosts.map(\.name)) == ["web", "edge"])
        #expect(Set(destination.snapshot.groups.map(\.name)) == ["Production", "EU"])
    }

    /// The dry run is what the import sheet previews. It has to answer the
    /// same question without touching anything, or the preview is a report of
    /// what it just did.
    @Test("a dry run changes nothing")
    func dryRunChangesNothing() async {
        let (source, _, _) = await peopled()
        let yaml = await source.exportYAML()!

        let destination = scratch()
        await destination.refresh()
        let planned = await destination.importYAML(yaml, dryRun: true)
        #expect(planned != nil, "it still answers")
        #expect(destination.snapshot.hosts.isEmpty)
        #expect(destination.snapshot.groups.isEmpty)
    }
}
