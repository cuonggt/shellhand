import Testing
@testable import Shellhand

/// The sidebar as one flat list, and what the search field narrows it to.
///
/// No `import Foundation`: it would make `Host` ambiguous with
/// `Foundation.Host`.
@Suite("Sidebar rows")
nonisolated struct SidebarRowsTests {
    ///     Production            hosts: web
    ///       └ EU                hosts: edge
    ///     Staging               (no hosts)
    ///     (ungrouped)           hosts: laptop
    private static let snapshot = Snapshot(
        groups: [
            Group(id: "prod", name: "Production"),
            Group(id: "eu", name: "EU", parentId: "prod"),
            Group(id: "stg", name: "Staging"),
        ],
        hosts: [
            Host(id: "h1", name: "web", addr: "198.51.100.1", groupId: "prod"),
            Host(id: "h2", name: "edge", addr: "198.51.100.2", groupId: "eu", tags: ["eu"]),
            Host(id: "h3", name: "laptop", addr: "192.0.2.9"),
        ])

    private let tree = Tree(snapshot)

    /// Rows as `id` plus depth, which is all the ordering and nesting a test
    /// needs to pin.
    private func shape(collapsed: Set<String> = [], matching: [Host]? = nil) -> [String] {
        SidebarRows.build(tree: tree, collapsed: collapsed, matching: matching)
            .map { "\($0.depth):\($0.id)" }
    }

    // MARK: the tree

    @Test("groups come before hosts at every level, each indented one further")
    func order() {
        #expect(shape() == [
            "0:label:hosts",
            "0:group:prod",
            "1:group:eu",
            "2:host:h2",
            "1:host:h1",
            "0:group:stg",
            "0:label:ungrouped",
            "0:host:h3",
        ])
    }

    @Test("a folded group keeps its own row and loses everything beneath it")
    func folded() {
        #expect(shape(collapsed: ["prod"]) == [
            "0:label:hosts",
            "0:group:prod",
            "0:group:stg",
            "0:label:ungrouped",
            "0:host:h3",
        ])
    }

    @Test("folding one level down leaves the level above intact")
    func foldedInner() {
        #expect(shape(collapsed: ["eu"]) == [
            "0:label:hosts",
            "0:group:prod",
            "1:group:eu",
            "1:host:h1",
            "0:group:stg",
            "0:label:ungrouped",
            "0:host:h3",
        ])
    }

    @Test("a group says whether it is open, so its row can draw the triangle")
    func expandedFlag() {
        let open = SidebarRows.build(tree: tree, collapsed: [], matching: nil)
        #expect(open.contains { $0.kind == .group(Group(id: "prod", name: "Production"), expanded: true) })

        let shut = SidebarRows.build(tree: tree, collapsed: ["prod"], matching: nil)
        #expect(shut.contains { $0.kind == .group(Group(id: "prod", name: "Production"), expanded: false) })
    }

    @Test("the Ungrouped label appears only where something is unfiled")
    func ungroupedLabel() {
        #expect(shape().contains("0:label:ungrouped"))
        let filed = Tree(Snapshot(
            groups: [Group(id: "prod", name: "Production")],
            hosts: [Host(id: "h1", name: "web", groupId: "prod")]))
        let rows = SidebarRows.build(tree: filed, collapsed: [], matching: nil).map(\.id)
        #expect(!rows.contains("label:ungrouped"))
    }

    /// A header above nothing is worse than no header, and the empty case has
    /// its own panel.
    @Test("an empty list has no header over it")
    func emptyList() {
        let nothing = Tree(Snapshot())
        #expect(SidebarRows.build(tree: nothing, collapsed: [], matching: nil).isEmpty)
    }

    @Test("a group that is its own ancestor stops the branch, not the app")
    func cycle() {
        let looped = Tree(Snapshot(
            groups: [
                Group(id: "a", name: "A", parentId: "b"),
                Group(id: "b", name: "B", parentId: "a"),
            ],
            hosts: []))
        // Reachable from no root, so nothing is drawn — and crucially it
        // returns at all.
        #expect(SidebarRows.build(tree: looped, collapsed: [], matching: nil).map(\.id)
            == ["label:hosts"])
    }

    // MARK: searching

    /// The results replace the tree outright. Two shapes in one list is what
    /// left the dropped shape's rows drawn over the new ones.
    @Test("matching replaces the tree rather than being added to it")
    func matchingReplaces() {
        let found = [Self.snapshot.hosts[0]]
        #expect(shape(matching: found) == ["0:label:matching", "0:host:h1"])
    }

    @Test("matching nothing is a list of nothing, not the tree back")
    func matchedNothing() {
        #expect(shape(matching: []).isEmpty)
    }

    @Test("a matched host shows its path, since the tree is not there to say")
    func showsPath() {
        let rows = SidebarRows.build(tree: tree, collapsed: [], matching: [Self.snapshot.hosts[1]])
        #expect(rows.contains { $0.kind == .host(Self.snapshot.hosts[1], showPath: true) })
    }

    // MARK: what the search field finds

    private func found(_ search: String, tags: Set<String> = []) -> [String] {
        SidebarRows.matches(in: Self.snapshot.hosts, search: search, tags: tags).map(\.name)
    }

    @Test("a name, an address or a tag all find a host")
    func findsBy() {
        #expect(found("web") == ["web"])
        #expect(found("192.0.2") == ["laptop"])
        #expect(found("eu") == ["edge"])
    }

    @Test("searching ignores case")
    func caseBlind() {
        #expect(found("WEB") == ["web"])
        #expect(found("LaPtOp") == ["laptop"])
    }

    @Test("an empty search is everything, by name")
    func everything() {
        #expect(found("") == ["edge", "laptop", "web"])
    }

    @Test("nothing matching is nothing, not everything")
    func nothing() {
        #expect(found("zzzz").isEmpty)
    }

    /// Two chips mean both, not either: `web` and `eu` asks for the European
    /// web servers. Widening is what the search field is for.
    @Test("chosen tags narrow together")
    func tagsNarrow() {
        #expect(found("", tags: ["eu"]) == ["edge"])
        #expect(found("", tags: ["eu", "nope"]).isEmpty)
    }

    @Test("a tag and a search narrow together too")
    func tagAndSearch() {
        #expect(found("edge", tags: ["eu"]) == ["edge"])
        #expect(found("web", tags: ["eu"]).isEmpty)
    }
}
