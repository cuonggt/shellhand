import Testing
@testable import Shellhand

/// What each item of a row's menu acts on.
///
/// The bug this holds: a group's Edit Group…, Delete Group… and New Group
/// Inside… carried no group and read the selection, and a right-click on a
/// card in the grid does not select it — so "Delete Group…" opened on EU,
/// while Production was picked, asked to delete Production.
///
/// No `import Foundation`: it would make `Host` ambiguous with
/// `Foundation.Host`. Nothing here needs it.
@MainActor
@Suite("A row's menu")
struct RowMenuTests {
    private let production = Group(id: "g1", name: "Production")
    private let eu = Group(id: "g2", name: "EU", parentId: "g1")
    private let web = Host(id: "h1", name: "web", addr: "192.0.2.1", groupId: "g2")

    private func lines(_ item: Selection?) -> [RowMenu.Line] {
        RowMenu.lines(for: item, hosts: [web], groups: [production, eu])
    }

    @Test("every item on a group's menu acts on that group")
    func groupLinesCarryTheirGroup() {
        #expect(lines(.group("g2")) == [
            .newHostIn(eu), .newGroupIn(eu), .divider, .editGroup(eu), .deleteGroup(eu),
        ])
    }

    @Test("every item on a host's menu acts on that host")
    func hostLinesCarryTheirHost() {
        #expect(lines(.host("h1")) == [
            .connect(web), .sftp(web), .copyCommand(web), .divider,
            .editHost(web), .deleteHost(web),
        ])
    }

    @Test("the empty space offers only what makes something")
    func emptySpace() {
        #expect(lines(nil) == [.newHost, .newGroup])
    }

    @Test("a row whose record has gone offers nothing")
    func goneRecord() {
        #expect(lines(.group("gone")).isEmpty)
        #expect(lines(.host("gone")).isEmpty)
    }

    @Test("the items say what they did before")
    func titles() {
        #expect(lines(.group("g2")).map(\.title) == [
            "New Host Inside…", "New Group Inside…", "",
            "Edit Group…", "Delete Group…",
        ])
    }
}
