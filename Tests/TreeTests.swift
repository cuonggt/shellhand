import Testing
@testable import Shellhand

/// The host list as a tree: what is under what, what is above it, and the
/// walks between — including what each of them does when the tree turns back
/// on itself.
///
/// No `import Foundation`: it would make `Host` ambiguous with
/// `Foundation.Host`, so ids are plain strings.
@Suite("Tree")
nonisolated struct TreeTests {
    ///     production            hosts: web, api
    ///       └ eu                hosts: edge
    ///           └ dublin        hosts: db
    ///     staging               (no hosts)
    ///     (unfiled)             hosts: laptop
    private static let snapshot = Snapshot(
        groups: [
            Group(id: "prod", name: "Production"),
            Group(id: "eu", name: "EU", parentId: "prod"),
            Group(id: "dub", name: "Dublin", parentId: "eu"),
            Group(id: "stg", name: "Staging"),
        ],
        hosts: [
            Host(id: "h1", name: "web", groupId: "prod"),
            Host(id: "h2", name: "api", groupId: "prod"),
            Host(id: "h3", name: "edge", groupId: "eu"),
            Host(id: "h4", name: "db", groupId: "dub"),
            Host(id: "h5", name: "laptop"),
        ])

    private let tree = Tree(snapshot)

    // MARK: looking things up

    @Test("a group's own hosts, by name, and nothing from beneath it")
    func own() {
        #expect(tree.hosts(in: "prod").map(\.name) == ["api", "web"])
        #expect(tree.hosts(in: "eu").map(\.name) == ["edge"])
        #expect(tree.hosts(in: "stg").isEmpty)
    }

    @Test("children come back by name, and a leaf has none")
    func children() {
        #expect(tree.children(of: "").map(\.name) == ["Production", "Staging"])
        #expect(tree.children(of: "prod").map(\.name) == ["EU"])
        #expect(tree.children(of: "dub").isEmpty)
    }

    @Test("hosts filed nowhere are their own list")
    func unfiled() {
        #expect(tree.ungrouped.map(\.name) == ["laptop"])
    }

    @Test("an id nothing answers to is empty, not a crash")
    func missing() {
        #expect(tree.group("nope") == nil)
        #expect(tree.host("nope") == nil)
        #expect(tree.hosts(in: "nope").isEmpty)
        #expect(tree.children(of: "nope").isEmpty)
    }

    // MARK: walking down

    @Test("everything beneath a group, however deep, by name")
    func beneath() {
        #expect(tree.hostsBeneath("prod").map(\.name) == ["api", "db", "edge", "web"])
        #expect(tree.hostsBeneath("eu").map(\.name) == ["db", "edge"])
        #expect(tree.hostsBeneath("dub").map(\.name) == ["db"])
        #expect(tree.hostsBeneath("stg").isEmpty)
    }

    @Test("a group that is its own descendant does not hang the walk down")
    func cycleDown() {
        // dublin's parent is eu, and eu's parent is made dublin: a loop that
        // only a bad edit or a corrupt store could produce.
        let looped = Tree(Snapshot(
            groups: [
                Group(id: "eu", name: "EU", parentId: "dub"),
                Group(id: "dub", name: "Dublin", parentId: "eu"),
            ],
            hosts: [Host(id: "h1", name: "edge", groupId: "eu")]))
        #expect(looped.hostsBeneath("eu").map(\.name) == ["edge"])
    }

    // MARK: walking up

    @Test("the path reads from the top down")
    func path() {
        #expect(tree.path(of: Group(id: "dub", name: "Dublin", parentId: "eu"))
            == "Production / EU / Dublin")
        #expect(tree.path(of: Group(id: "prod", name: "Production")) == "Production")
    }

    @Test("a loop above a group stops the path rather than the app")
    func cycleUp() {
        let looped = Tree(Snapshot(groups: [
            Group(id: "a", name: "A", parentId: "b"),
            Group(id: "b", name: "B", parentId: "a"),
        ]))
        // It stops once it comes back round; what matters is that it stops.
        #expect(looped.path(of: Group(id: "a", name: "A", parentId: "b")) == "B / A")
    }

    @Test("a host needs its own group open, and every group above it")
    func ancestryOfHost() {
        #expect(tree.ancestry(ofHost: "h4") == ["dub", "eu", "prod"])
        #expect(tree.ancestry(ofHost: "h3") == ["eu", "prod"])
        #expect(tree.ancestry(ofHost: "h1") == ["prod"])
    }

    @Test("a host filed nowhere needs nothing open")
    func ancestryOfUnfiled() {
        #expect(tree.ancestry(ofHost: "h5").isEmpty)
        #expect(tree.ancestry(ofHost: "nope").isEmpty)
    }

    /// A group's own fold is its business — what matters is that its row can
    /// be reached, which means its parents and not itself.
    @Test("a group needs its parents open, but not itself")
    func ancestryOfGroup() {
        #expect(tree.ancestry(ofGroup: "dub") == ["eu", "prod"])
        #expect(tree.ancestry(ofGroup: "eu") == ["prod"])
        #expect(tree.ancestry(ofGroup: "prod").isEmpty)
        #expect(tree.ancestry(ofGroup: "nope").isEmpty)
    }

    @Test("a loop above a group does not hang the climb")
    func ancestryCycle() {
        let looped = Tree(Snapshot(
            groups: [
                Group(id: "a", name: "A", parentId: "b"),
                Group(id: "b", name: "B", parentId: "a"),
            ],
            hosts: [Host(id: "h", name: "x", groupId: "a")]))
        #expect(looped.ancestry(ofHost: "h") == ["a", "b"])
    }

    // MARK: folding on first load

    @Test("everything folds except what the selection needs open")
    func folds() {
        #expect(tree.folded(keepingVisible: tree.ancestry(ofHost: "h4")) == ["stg"])
        #expect(tree.folded(keepingVisible: tree.ancestry(ofHost: "h1")) == ["eu", "dub", "stg"])
    }

    @Test("with nothing selected, everything folds")
    func foldsAll() {
        #expect(tree.folded(keepingVisible: []) == ["prod", "eu", "dub", "stg"])
    }

    @Test("a list with no groups folds to nothing")
    func foldsNothing() {
        let flat = Tree(Snapshot(hosts: [Host(id: "h", name: "x")]))
        #expect(flat.folded(keepingVisible: []).isEmpty)
    }
}
