import SwiftUI

/// The menu a row carries — the same one in the sidebar and in the pane.
///
/// **One definition, because they are meant to be the same menu** and because
/// two copies of a decision drift. The local-copy error handling did exactly
/// that: a drag between panes reported a refused copy while a drop from Finder
/// swallowed it, for months, because the same decision had been written twice.
///
/// **Everything here acts on the item the menu was opened on, handed over
/// rather than read back out of the selection.** `AppActions.newHostIn` already
/// worked this way and says why. In the sidebar and in the pane's list it
/// would not strictly matter — `contextMenu(forSelectionType:)` selects the
/// row first — but on a card in the grid nothing selects it, and a menu
/// reading the selection would edit or delete whatever was picked before. One
/// menu that is correct everywhere beats two that are each correct somewhere.
struct RowMenu: View {
    /// What the menu was opened on. Nil is the empty space around the rows,
    /// where the only sensible offers are the ones that make something.
    let item: Selection?
    let store: HostStore
    let actions: AppActions
    let onConnect: (Host) -> Void

    /// One line of the menu, carrying what it acts on. Out of the view so
    /// that **what each item acts on** can be checked without opening a
    /// menu: a group's Edit, Delete and New Group Inside once carried
    /// nothing and read the selection, which on a grid card was some other
    /// group.
    enum Line: Equatable {
        case connect(Host), sftp(Host), copyCommand(Host), editHost(Host), deleteHost(Host)
        case newHostIn(Group), newGroupIn(Group), editGroup(Group), deleteGroup(Group)
        /// The empty space's offers, which make something rather than act on
        /// a row, and so are the only ones left to read the selection.
        case newHost, newGroup
        case divider

        var title: String {
            switch self {
            case .connect: "Connect"
            case .sftp: "SFTP…"
            case .copyCommand: "Copy as ssh Command"
            case .editHost: "Edit Host…"
            case .deleteHost: "Delete Host…"
            // Inside the group this menu was opened on. New Host once called
            // the same plain `newHost` the File menu does, so the one item in
            // a group's menu that made something put it at the top of the
            // list instead. Both say "Inside", and the row names the group.
            case .newHostIn: "New Host Inside…"
            case .newGroupIn: "New Group Inside…"
            case .editGroup: "Edit Group…"
            case .deleteGroup: "Delete Group…"
            case .newHost: "New Host…"
            case .newGroup: "New Group…"
            case .divider: ""
            }
        }
    }

    /// The menu for what it was opened on. A row whose record has gone since
    /// offers nothing rather than acting on some other one.
    static func lines(for item: Selection?, hosts: [Host], groups: [Group]) -> [Line] {
        switch item {
        case let .host(id):
            guard let host = hosts.first(where: { $0.id == id }) else { return [] }
            return [.connect(host), .sftp(host), .copyCommand(host), .divider,
                    .editHost(host), .deleteHost(host)]
        case let .group(id):
            guard let group = groups.first(where: { $0.id == id }) else { return [] }
            return [.newHostIn(group), .newGroupIn(group), .divider,
                    .editGroup(group), .deleteGroup(group)]
        case nil:
            return [.newHost, .newGroup]
        }
    }

    var body: some View {
        let lines = Self.lines(
            for: item, hosts: store.snapshot.hosts, groups: store.snapshot.groups)
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            if line == .divider {
                Divider()
            } else {
                Button(line.title) { perform(line) }
            }
        }
    }

    private func perform(_ line: Line) {
        switch line {
        case let .connect(host): onConnect(host)
        case let .sftp(host): actions.openFilesOn(host)
        case let .copyCommand(host): actions.onHost.copyCommand(host)
        case let .editHost(host): actions.onHost.edit(host)
        case let .deleteHost(host): actions.onHost.delete(host)
        case let .newHostIn(group): actions.newHostIn(group)
        case let .newGroupIn(group): actions.onGroup.newGroupIn(group)
        case let .editGroup(group): actions.onGroup.edit(group)
        case let .deleteGroup(group): actions.onGroup.delete(group)
        case .newHost: actions.newHost()
        case .newGroup: actions.newGroup()
        case .divider: break
        }
    }
}
