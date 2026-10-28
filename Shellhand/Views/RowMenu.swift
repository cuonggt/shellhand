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

    var body: some View {
        switch item {
        case let .host(id):
            if let host = store.snapshot.hosts.first(where: { $0.id == id }) {
                Button("Connect") { onConnect(host) }
                Button("SFTP…") { actions.openFilesOn(host) }
                Button("Copy as ssh Command") { actions.onHost.copyCommand(host) }
                Divider()
                Button("Edit Host…") { actions.onHost.edit(host) }
                Button("Delete Host…") { actions.onHost.delete(host) }
            }
        case let .group(id):
            // Inside the group this menu was opened on. It used to call the
            // same plain `newHost` the File menu does, so the one item in a
            // group's menu that made something put it at the top of the list
            // instead — while "New Group Inside…" directly below it nested.
            // Both say "Inside" now, and the row it was opened on is what
            // names the group, which is why neither label has to.
            if let group = store.group(id) {
                Button("New Host Inside…") { actions.newHostIn(group) }
            }
            Button("New Group Inside…") { actions.newGroup() }
            Divider()
            Button("Edit Group…") { actions.editGroup() }
            Button("Delete Group…") { actions.deleteGroup() }
        case nil:
            Button("New Host…") { actions.newHost() }
            Button("New Group…") { actions.newGroup() }
        }
    }
}
