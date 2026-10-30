import SwiftUI

/// What the menu bar can ask the front window to do.
///
/// Menus live on the Scene and the state lives in the window, so the window
/// publishes its actions as a focused value and the commands read them. That
/// is also why the shortcuts are here rather than on buttons: a shortcut on a
/// toolbar button works, but it appears in no menu, so nobody discovers it —
/// and four of them were on invisible buttons stacked behind the terminal.
@MainActor
struct AppActions {
    var newTab: () -> Void = {}
    var newLocalShell: () -> Void = {}
    var newHost: () -> Void = {}
    /// A host filed under one group in particular, from that group's own menu.
    /// The group is handed over rather than read back out of the selection,
    /// so this does not depend on right-clicking a row having selected it,
    /// and so New Host… in the File menu goes on making a host with no group.
    var newHostIn: (Group) -> Void = { _ in }
    /// The row's own actions, each handed its subject rather than reading it
    /// back out of the selection — the same reason `newHostIn` takes its
    /// group, and **necessary** for a card in the grid: `contextMenu` on a
    /// card does not select it, so a menu that read the selection would edit
    /// or delete whatever happened to be picked before.
    var onHost = HostActions()
    /// The same for a group's own menu. Its Edit, Delete and New Group Inside
    /// read the selection until these existed, so on a card in the grid they
    /// acted on whichever group was picked before: "Delete Group…" opened on
    /// EU asked to delete Production.
    var onGroup = GroupActions()

    struct HostActions {
        var edit: (Host) -> Void = { _ in }
        var delete: (Host) -> Void = { _ in }
        var copyCommand: (Host) -> Void = { _ in }
    }

    struct GroupActions {
        var newGroupIn: (Group) -> Void = { _ in }
        var edit: (Group) -> Void = { _ in }
        var delete: (Group) -> Void = { _ in }
    }
    var editHost: () -> Void = {}
    /// Asks the window to open the file window. It cannot be done from here:
    /// `openWindow` is inert both in a `Commands` body and when captured into
    /// one of these closures — only a live view can call it — so this nudges
    /// the window, which does it where the environment is real.
    var openFiles: () -> Void = {}
    /// Selecting the hosts tab, which is not the same as bringing the window
    /// forward — the app menu's Hosts does both.
    var showHosts: () -> Void = {}
    /// Files on one host in particular, from that host's own menu.
    var openFilesOn: (Host) -> Void = { _ in }
    var newGroup: () -> Void = {}
    var editGroup: () -> Void = {}
    /// Asks; the window is where the question is put, because deleting is not
    /// something a menu should do on the way past.
    var deleteHost: () -> Void = {}
    var deleteGroup: () -> Void = {}
    var copyAsCommand: () -> Void = {}
    var connect: () -> Void = {}
    var reconnect: () -> Void = {}
    /// Gives up on the connection being made in the tab in front.
    var stopConnecting: () -> Void = {}
    var closeTab: () -> Void = {}
    var toggleSplit: () -> Void = {}
    var quickConnect: () -> Void = {}
    var openImport: () -> Void = {}
    var find: () -> Void = {}
    var findNext: () -> Void = {}
    var findPrevious: () -> Void = {}
    var clearScrollback: () -> Void = {}
    var biggerText: () -> Void = {}
    var smallerText: () -> Void = {}
    var actualSize: () -> Void = {}
    var toggleInspector: () -> Void = {}

    /// The sessions open, for the Window menu.
    ///
    /// The sidebar is where you switch between them, and the sidebar can be
    /// collapsed — by exactly the person running six of them, to widen the
    /// terminal. This is so collapsing it does not take the switcher away.
    var openSessions: [SessionItem] = []
    var showSession: (UUID) -> Void = { _ in }
    /// The next or previous tab of the strip, round from the last to the
    /// first — `Panes.stepping` says which.
    var nextTab: () -> Void = {}
    var previousTab: () -> Void = {}

    /// The group a new group would go inside, named, so the menu item can
    /// say so — empty when it would go to the top of the list. The sidebar's
    /// own version of that item can say "Inside" and leave the row to name
    /// the group; the menu bar has no row, so it names it itself.
    var groupInside = ""

    /// What is possible right now, so menu items grey out rather than lie.
    var hasHost = false
    var hasGroup = false
    var hasSession = false
    /// Whether the session in front is still connecting.
    var canStopConnecting = false
    /// Whether there are two things that could go side by side — terminals
    /// and SFTP tabs alike — and the one in front is one of them.
    var canSplit = false
    /// Whether the strip holds more than the hosts, so stepping goes anywhere.
    var canStepTabs = false
    /// File ▸ Export…: the list as YAML, the way the import sheet's Export…
    /// writes it. It lived only in that sheet, behind a button labelled
    /// Import.
    var exportList: () -> Void = {}
    /// Whether there is a list to export.
    var canExport = false
    /// Whether ⌘T has anything to open — another of the session in front,
    /// or with the hosts in front the host selected. `Panes.newTab` decides;
    /// it used to be `hasHost`, which greyed ⌘T out in a terminal whenever
    /// the list had a group picked.
    var canNewTab = false
}

/// One open session, named short enough for a menu.
nonisolated struct SessionItem: Identifiable, Hashable {
    let id: UUID
    let title: String
}

struct AppActionsKey: FocusedValueKey {
    typealias Value = AppActions
}

extension FocusedValues {
    var appActions: AppActions? {
        get { self[AppActionsKey.self] }
        set { self[AppActionsKey.self] = newValue }
    }
}

struct ShellhandCommands: Commands {
    @FocusedValue(\.appActions) private var actions

    /// Settings needs these to say where the host list and the ssh options
    /// are; they come down from the app rather than through `AppActions`,
    /// because they are the same whatever window is in front.
    let storePath: String
    let configPath: String

    /// One item that does two things, so it says which: a group selected in
    /// the sidebar means the new one goes inside it, and nothing selected
    /// means the top of the list. Without this the only way to find out was
    /// to open the editor and read its parent picker.
    private var newGroupTitle: String {
        let inside = actions?.groupInside ?? ""
        return inside.isEmpty ? "New Group…" : "New Group Inside \(inside)…"
    }

    var body: some Commands {
        // The app menu: looking for an update, then the two things this app
        // shows, all above Settings.
        //
        // **Hosts does not go through `AppActions`.** That is a focused scene
        // value, so it is nil whenever the host window is not the front one —
        // which is exactly when "bring the host list forward" is wanted, and
        // the item would be greyed out at the only moment it has a job.
        // `HostsWindow.front()` asks AppKit directly instead.
        //
        // SFTP does go through it, because opening the window needs the
        // store the host window holds — so ⌘B is dead while the SFTP window
        // itself is in front. Bring the host list forward and it works.
        CommandGroup(after: .appInfo) {
            Divider()
            // Straight under About, where every Mac app keeps it. Like Hosts
            // and SFTP it needs nothing selected, so it is not gated on the
            // sidebar — only on whether Sparkle can look at all, which a
            // Debug build never can, so this greys out while developing
            // rather than looking live and doing nothing.
            Button("Check for Updates\u{2026}") { Updates.shared.check() }
                .disabled(!Updates.shared.canCheck)
            Divider()
            Button("Hosts") {
                HostsWindow.front()
                actions?.showHosts()
            }
            // Fronting a browser that already exists needs no store, so it
            // works from the SFTP window itself where `AppActions` is nil.
            // Only making a new one has to go through the host window.
            Button("SFTP") {
                if !FilesWindowController.front() { actions?.openFiles() }
            }
            .keyboardShortcut("b", modifiers: .command)
        }

        // Settings is a window of this app's own making, not a `Settings`
        // scene — the scene cannot be given the style mask the glass chrome
        // needs. Replacing `.appSettings` keeps the item where every Mac app
        // has it, and carries ⌘, which the scene used to give for free.
        CommandGroup(replacing: .appSettings) {
            Button("Settings\u{2026}") {
                SettingsWindowController.show(
                    storePath: storePath, configPath: configPath)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        // Replacing .newItem puts these where New and Open live in every
        // other Mac app, rather than adding a menu nobody looks in.
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { actions?.newTab() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!(actions?.canNewTab ?? false))
            Button("New Local Shell") { actions?.newLocalShell() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("New Host…") { actions?.newHost() }
                .keyboardShortcut("n", modifiers: .command)
            Button(newGroupTitle) { actions?.newGroup() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Import…") { actions?.openImport() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            // No key: ⇧⌘E, the usual one, is Edit Group's here.
            Button("Export…") { actions?.exportList() }
                .disabled(!(actions?.canExport ?? false))
        }

        CommandGroup(after: .newItem) {
            Button("Close Tab") { actions?.closeTab() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(!(actions?.hasSession ?? false))
        }

        // Three menus where there was one. "Host" had grown to nineteen items
        // covering connecting, editing, deleting, copying, four unrelated
        // dialogs and two snippet submenus — which is not a menu about hosts,
        // it is everything that did not fit in File. The line between them is
        // what each item acts on, which is also what gates it: a host, the
        // session in front, or nothing at all.
        CommandMenu("Host") {
            Button("Connect") { actions?.connect() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!(actions?.hasHost ?? false))
            Button("Quick Connect…") { actions?.quickConnect() }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Edit Host…") { actions?.editHost() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!(actions?.hasHost ?? false))
            Button("Edit Group…") { actions?.editGroup() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!(actions?.hasGroup ?? false))
            Divider()
            Button("Copy as ssh Command") { actions?.copyAsCommand() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!(actions?.hasHost ?? false))
            Divider()
            Button("Delete Host…") { actions?.deleteHost() }
                .disabled(!(actions?.hasHost ?? false))
            // One `.disabled`, not two. This carried a second one on `hasHost`
            // as well, so deleting a group needed a host selected too — which
            // nothing about deleting a group requires.
            Button("Delete Group…") { actions?.deleteGroup() }
                .disabled(!(actions?.hasGroup ?? false))
        }

        // Everything that acts on the session in front, and nothing that does
        // not — so the whole menu greys out together when there is no
        // terminal, rather than items greying out one by one inside a menu
        // about something else.
        CommandMenu("Terminal") {
            Button("Reconnect") { actions?.reconnect() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!(actions?.hasSession ?? false))
            // ⌘., the Mac's key for giving up on something under way, and
            // only while a connection is: disabled, it passes the key on.
            Button("Stop Connecting") { actions?.stopConnecting() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!(actions?.canStopConnecting ?? false))
            Divider()
            Button("Show Beside") { actions?.toggleSplit() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!(actions?.canSplit ?? false))
            Divider()
            // ⌥⌘K, Terminal.app's own key for this. ⌘K, which clears in
            // Terminal.app, iTerm2 and Ghostty, stays Quick Connect's.
            Button("Clear Scrollback") { actions?.clearScrollback() }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(!(actions?.hasSession ?? false))
            Divider()
            // Here rather than in View, where "Bigger Text" does not say
            // bigger than what. These size the terminal and nothing else.
            Button("Bigger Text") { actions?.biggerText() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!(actions?.hasSession ?? false))
            Button("Smaller Text") { actions?.smallerText() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!(actions?.hasSession ?? false))
            Button("Actual Size") { actions?.actualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!(actions?.hasSession ?? false))
        }

        // The sessions, above the window list, with ⌘1 to ⌘9 for the first
        // nine. The sidebar is where you switch between them; this is what
        // still works when the sidebar has been collapsed to widen the
        // terminal, which is exactly what somebody with six of them does.
        //
        // Stepping comes first, on ⇧⌘[ and ⇧⌘] as in Terminal.app and
        // Safari. ⌃⇧⇥ and ⌃⇥ do the same, and are not here: an item holds one
        // key, so those are `StepsTabs`'s, behind the host list.
        CommandGroup(before: .windowList) {
            Button("Show Previous Tab") { actions?.previousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(!(actions?.canStepTabs ?? false))
            Button("Show Next Tab") { actions?.nextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(!(actions?.canStepTabs ?? false))
            Divider()
            let open = actions?.openSessions ?? []
            if !open.isEmpty {
                ForEach(Array(open.prefix(9).enumerated()), id: \.element.id) { index, item in
                    Button(item.title) { actions?.showSession(item.id) }
                        .keyboardShortcut(
                            KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                ForEach(Array(open.dropFirst(9))) { item in
                    Button(item.title) { actions?.showSession(item.id) }
                }
                Divider()
            }
        }

        // Find belongs beside the system's own text commands.
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { actions?.find() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!(actions?.hasSession ?? false))
            Button("Find Next") { actions?.findNext() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!(actions?.hasSession ?? false))
            Button("Find Previous") { actions?.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!(actions?.hasSession ?? false))
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Host Details") { actions?.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }

        // Replacing the system's own "Shellhand Help", which only said help
        // was not available. Needs nothing selected, like the app menu's.
        CommandGroup(replacing: .help) {
            Button("Shellhand Help") { NSWorkspace.shared.open(Help.readme) }
            Button("Report a Problem…") { NSWorkspace.shared.open(Help.reportFromHere) }
        }
    }
}
