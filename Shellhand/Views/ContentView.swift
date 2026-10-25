import SwiftUI

/// What the sidebar has selected. A group shows everything beneath it, as
/// selecting one in the TUI does.
enum Selection: Hashable {
    case host(String)
    case group(String)
}

/// What the detail pane is showing: the host side of the app, or one of the
/// sessions. The hosts lead the strip and cannot be closed; the sessions
/// follow. SFTP is not here — it is a window of its own.
///
/// It is the tab strip's selection, so **the state is the thing you can see
/// and click**.
///
/// This replaced a `Bool` called `browsing`, and the reason is worth keeping.
/// A flag nobody can point at has to be set as a side effect of something
/// else, and twice that side effect silently did not happen: picking the tab
/// already selected wrote an unchanged value, so the `onChange` watching it
/// never fired, and clicking the sidebar row already selected wrote nothing
/// through the `List`'s binding at all. Both were the same bug, and neither
/// is expressible once the mode is a tab.
enum PaneTab: Hashable {
    case hosts
    case session(UUID)
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var store: HostStore
    @State private var sessions = Sessions()
    @State private var selection: Selection?
    @State private var search = ""
    @State private var editing: Host?
    @State private var editingGroup: Group?
    @State private var deletingHost: Host?
    @State private var deletingGroup: Group?
    @State private var showingQuickConnect = false
    /// Which way in the import sheet opens on, and whether it is open at all.
    ///
    /// One value rather than a flag beside a source, because the content of a
    /// sheet driven by `isPresented` is built from the view as it was before
    /// the flag flipped: pressing CSV on the welcome opened the sheet on the
    /// ssh config every time.
    @State private var importing: ImportSheet.Source?
    @State private var showingInspector = false
    /// Which tab of the strip the pane is on. Starts on the hosts, which is
    /// what the window is for and the only thing there is on a fresh install.
    @State private var pane = PaneTab.hosts
    /// What is shown beside it, when the split is open. Either kind on either
    /// side: a transfer running next to the terminal you are typing in is the
    /// whole reason the split takes an SFTP tab at all.
    @State private var beside: PaneTab?
    /// macOS restores the window itself; this restores what was selected in
    /// it. Nothing reconnects on its own: opening a window should not reach
    /// out to other people's machines.
    @SceneStorage("selectedHost") private var storedHostID = ""

    private let configPath: String

    init(dbPath: String, configPath: String = "") {
        _store = State(initialValue: HostStore(dbPath: dbPath))
        self.configPath = configPath
    }

    private var selectedHost: Host? {
        guard case let .host(id) = selection else { return nil }
        return store.snapshot.hosts.first { $0.id == id }
    }

    private var selectedGroup: Group? {
        guard case let .group(id) = selection else { return nil }
        return store.group(id)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                store: store, selection: $selection, search: $search,
                actions: actions, onConnect: connect,
                onBrowse: { now in
                    selection = now
                    pane = .hosts
                })
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
                .toolbar { listToolbar }
        } detail: {
            DetailView(
                store: store, sessions: sessions,
                host: selectedHost, group: selectedGroup,
                pane: pane, beside: beside,
                onConnect: connect, onPickTab: pick(tab:),
                onEdit: { editing = $0 },
                onEditGroup: { editingGroup = $0 },
                onPick: { selection = $0 },
                onImport: { open(import: $0) }, onNewHost: { editing = Host() })
                .toolbar { paneToolbar }
        }
        // Tags the window so Shellhand ▸ Hosts can find it again from an
        // SFTP window or from Settings, where this scene's actions are not
        // in focus.
        .background(TagsHostsWindow())
        .navigationTitle(windowTitle)
        .navigationSubtitle(windowSubtitle)
        .inspector(isPresented: $showingInspector) {
            inspector.inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .focusedSceneValue(\.appActions, actions)
        .task {
            // Settings keeps this; the engine is where it has to take effect,
            // and it is only told when the stepper moves — so it is told here
            // too, or every launch would be back to the default.
            await Core.shared.setTransferWidth(
                UserDefaults.standard.object(forKey: "transferWidth") as? Int
                    ?? TransferQueue.defaultWidth)
            await store.refresh()
            store.watchForExternalChanges()
            if !storedHostID.isEmpty,
               store.snapshot.hosts.contains(where: { $0.id == storedHostID }) {
                selection = .host(storedHostID)
            }
        }
        .onChange(of: selection) { _, now in
            if case let .host(id) = now { storedHostID = id }
            // Anything picked in the sidebar is about the hosts, so the
            // hosts tab is what shows it — a host's own detail, a group's
            // list, or the whole list. No guessing between the list and a
            // terminal: the tabs say which is up and either is one click.
            pane = .hosts
        }
        .sheet(item: $editing) { host in
            HostEditorSheet(store: store, host: host)
        }
        .sheet(item: $editingGroup) { group in
            GroupEditorSheet(store: store, group: group)
        }
        .confirmationDialog(
            deletingHost.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { deletingHost != nil },
                                 set: { if !$0 { deletingHost = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let host = deletingHost {
                    Task { await store.delete(host) }
                }
            }
        } message: {
            Text(deletingHost.map { store.deletionWarning(for: $0) } ?? "")
        }
        .confirmationDialog(
            deletingGroup.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { deletingGroup != nil },
                                 set: { if !$0 { deletingGroup = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let group = deletingGroup {
                    Task { await store.delete(group) }
                }
            }
        } message: {
            Text(deletingGroup.map { store.deletionWarning(for: $0) } ?? "")
        }
        .sheet(isPresented: $showingQuickConnect) {
            QuickConnectSheet(store: store, onConnect: connect)
        }
        // A palette chosen on a group reaches the tabs already open, not just
        // the next connection.
        .onChange(of: store.snapshot.hosts) { _, hosts in
            sessions.repaint(from: hosts)
        }
        // Closing a tab moves `Sessions.selected` — to another session, or to
        // nothing when that was the last one. The strip has to follow it, or
        // the pane would sit on a tab no longer drawn. Safe as an `onChange`
        // where setting the mode was not: this only has to react when the
        // value really did move, and closing always moves it.
        .onChange(of: sessions.selected) { _, now in
            guard case .session = pane else { return }
            pane = now.map(PaneTab.session) ?? .hosts
        }
        // Closed on the way into SFTP and put back on the way out.
        //
        // Done here rather than by deriving `isPresented` from the tab: a
        // binding whose `get` reads `pane` makes SwiftUI present and dismiss
        // the inspector *during* the update that changed the tab, and that
        // crashes the app on the way back out of SFTP. An `onChange` runs
        // after the update instead, which is the whole difference.
        .sheet(item: $importing) { source in
            ImportSheet(store: store, start: source)
        }
        // A constant binding cannot be dismissed: the alert came back the
        // moment it was closed, because nothing ever cleared the error.
        .alert("Shellhand", isPresented: Binding(
            get: { store.lastError != nil },
            set: { shown in if !shown { store.clearError() } }
        )) {
            Button("OK") { store.clearError() }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    /// Placed by what each item acts on, the way the menus are named. Quick
    /// Connect and New Host find or make something in the **list**, so they
    /// sit over the sidebar. Files acts on the host **selected**, so it sits
    /// over the pane that shows it. The inspector toggle goes to the trailing
    /// edge, where macOS keeps them — next to the inspector it opens, rather
    /// than next to the sidebar toggle, where it read as a second one of
    /// those.
    ///
    /// Connect is deliberately **not** here. It was the only item that came
    /// and went with the selection, so every button to its right slid
    /// sideways as you clicked around the list — the same thing a width that
    /// jumps between sheets does under the pointer. And it was a third copy
    /// of an action the detail pane already offers under the host's own name,
    /// with ⌘↩ in the Host menu for the keyboard.
    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        // `.navigation` is the **detail** side here, and everything else
        // lands over the sidebar in the order it is declared — the opposite
        // of what the names suggest, and measured rather than assumed.
        ToolbarItemGroup {
            Button {
                showingQuickConnect = true
            } label: {
                Label("Quick Connect", systemImage: "magnifyingglass")
            }
            .help("Connect to a host by name (⌘K)")

            Button {
                editing = Host()
            } label: {
                Label("New Host", systemImage: "plus")
            }
            .help("Add a host (⌘N)")

            // Last of the three, so the two that are pressed most keep the
            // place they have had: a button that moves under the pointer is
            // the thing this toolbar has already been rearranged to avoid.
            Button {
                openFiles(on: selectedHost)
            } label: {
                Label("SFTP", systemImage: "arrow.left.arrow.right")
            }
            .help("Move files between this Mac and a host, over SFTP (⌘B)")
        }
    }

    /// What acts on the pane itself — which is the inspector toggle and
    /// nothing else now that Files has gone over the list.
    ///
    /// Attached to the **detail view** rather than to the split view, which
    /// is what finally put it on the right. Hung off the split view it lands
    /// hard against the divider whatever placement it is given, and neither a
    /// `ToolbarSpacer(.flexible)` nor a plain `Spacer` inside the group
    /// pushes it anywhere. Each column owning its own toolbar is the thing
    /// that works — so this stays, one item or not.
    @ToolbarContentBuilder
    private var paneToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showingInspector.toggle()
            } label: {
                Label("Host Details", systemImage: "sidebar.right")
            }
            .help("Show what this host connects with (⌥⌘I)")
        }
    }

    /// What the window says it is: **whatever the tab in front is about**,
    /// the same rule the inspector follows.
    ///
    /// Not `sessions.current`, which is the current *terminal* and says
    /// nothing about which tab is up — with the hosts in front the title bar
    /// still named the session, so the window called itself one thing while
    /// showing another.
    private var windowTitle: String {
        switch pane {
        case .hosts:
            return selectedHost?.name ?? selectedGroup?.name ?? "Shellhand"
        case let .session(id):
            return sessions.all.first { $0.id == id }?.title ?? "Shellhand"
        }
    }

    /// Under it: how the session is doing, or where what is selected is
    /// filed — a group's path for a host, the path above for a group.
    private var windowSubtitle: String {
        switch pane {
        case .hosts:
            if let host = selectedHost, let group = store.group(host.groupId) {
                return store.path(of: group)
            }
            if let group = selectedGroup, let parent = store.group(group.parentId) {
                return store.path(of: parent)
            }
            return ""
        case let .session(id):
            guard let session = sessions.all.first(where: { $0.id == id }) else { return "" }
            switch session.state {
            case .connecting: return "connecting…"
            case .connected: return session.host.map { "\($0.effective.user)@\($0.addr)" } ?? "local"
            case .askingHostKey: return "waiting for an answer"
            case let .ended(code, _):
                return code == 0 ? "ended" : "ended with status \(code.map(String.init) ?? "a signal")"
            }
        }
    }

    /// The session the pane is actually showing, or nothing.
    ///
    /// Everything in the **Terminal** menu acts on this, and the menu is
    /// gated on it. Not `sessions.current`, which is the current terminal
    /// whether or not its tab is in front — with the hosts up, that left the
    /// whole menu live and pointed at a terminal nobody could see, so ⌘W
    /// closed a session off screen. The menus are named for what they act
    /// on, and Terminal's rule has always been "a session in front"; this is
    /// what makes it true.
    private var frontSession: TerminalSession? {
        guard case let .session(id) = pane else { return nil }
        return sessions.all.first { $0.id == id }
    }

    /// The host whose details the inspector shows: **whatever the tab in
    /// front is about.** The hosts tab means the one picked in the sidebar;
    /// a session's tab means the machine that session is on.
    ///
    /// Not `sessions.current`, which is the current *terminal* and says
    /// nothing about which tab is up — on the hosts tab it still named the
    /// last session's host, so the inspector described something that was
    /// not on screen.
    ///
    /// Looked up live rather than taken off the session, so a host edited
    /// while its terminal is open shows as edited. A session with no host —
    /// a local shell — has nothing to describe, and says so rather than
    /// falling back to the sidebar and naming an unrelated machine.
    private var inspectedHost: Host? {
        switch pane {
        case .hosts:
            return selectedHost
        case let .session(id):
            guard let onHost = sessions.all.first(where: { $0.id == id })?.host?.id
            else { return nil }
            return store.snapshot.hosts.first { $0.id == onHost }
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let host = inspectedHost {
            // Compact: the inspector is beside a terminal or a files pane,
            // saying what the session in front is using. The full shape is
            // the main panel's, and showing it in both at once was simply
            // the same view twice.
            HostDetailView(
                store: store, host: host, compact: true,
                onConnect: connect, onEdit: { editing = $0 })
        } else {
            ContentUnavailableView(
                "Nothing selected", systemImage: "sidebar.right",
                description: Text("Pick a host to see what it connects with."))
        }
    }

    /// Opens the import sheet on one of its three ways in.
    private func open(import source: ImportSheet.Source) { importing = source }

    /// What the menu bar can ask this window to do, and what is possible now.
    private var actions: AppActions {
        AppActions(
            newTab: { if let host = selectedHost { connect(host) } },
            newLocalShell: { show(session: sessions.openLocalShell().id) },
            newHost: { editing = Host() },
            newHostIn: { group in editing = Host(groupId: group.id) },
            editHost: { if let host = selectedHost { editing = host } },
            // On whatever host is selected, so that pressing this with one
            // picked opens straight onto it. With nothing picked the far
            // side asks which host, rather than showing this Mac twice.
            openFiles: { openFiles(on: selectedHost) },
            showHosts: { pick(tab: .hosts) },
            openFilesOn: { host in openFiles(on: host) },
            // A new group goes inside whichever one is selected, which is
            // what picking one and asking for a group means.
            newGroup: { editingGroup = Group(parentId: selectedGroup?.id ?? "") },
            editGroup: { if let group = selectedGroup { editingGroup = group } },
            deleteHost: { deletingHost = selectedHost },
            deleteGroup: { deletingGroup = selectedGroup },
            copyAsCommand: copyAsCommand,
            connect: { if let host = selectedHost { connect(host) } },
            reconnect: {
                if let session = frontSession, let host = session.host {
                    sessions.close(session)
                    connect(host)
                }
            },
            closeTab: { if let session = frontSession { sessions.close(session) } },
            toggleSplit: toggleSplit,
            quickConnect: { showingQuickConnect = true },
            openImport: { open(import: .sshConfig) },
            find: { frontSession?.findOpen.toggle() },
            findNext: { _ = frontSession?.findNext() },
            findPrevious: { _ = frontSession?.findPrevious() },
            biggerText: { frontSession?.changeFontSize(by: 1) },
            smallerText: { frontSession?.changeFontSize(by: -1) },
            actualSize: { frontSession?.resetFontSize() },
            toggleInspector: { showingInspector.toggle() },
            openSessions: sessions.all.map {
                SessionItem(id: $0.id, title: Sessions.shortTitle(of: $0))
            },
            showSession: show(session:),
            groupInside: selectedGroup?.name ?? "",
            hasHost: selectedHost != nil,
            hasGroup: selectedGroup != nil,
            hasSession: frontSession != nil,
            // Not on the hosts tab: it is not one of the two sides, so
            // there would be nothing to put beside it.
            canSplit: pane != .hosts && openTabs.count > 1)
    }

    /// The ssh command for the selected host, on the pasteboard — the same
    /// argv the app would run, so it can be pasted into a terminal or a
    /// runbook and behave the same.
    private func copyAsCommand() {
        guard let host = selectedHost else { return }
        Task {
            guard let argv = await store.sshArgs(for: host) else { return }

            let command = sshCommand(argv)
            // The pasteboard is a container, not a variable: writing without
            // clearing first leaves whatever else was in it advertised too.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    /// The argv as a line someone could paste into a terminal.
    private func sshCommand(_ argv: [String]) -> String {
        (["ssh"] + argv.map(quoted)).joined(separator: " ")
    }

    private func quoted(_ argument: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz"
            + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%_+=:,./-")
        guard argument.unicodeScalars.allSatisfy(safe.contains) else {
            return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return argument
    }

    private func connect(_ host: Host) {
        Task {
            guard let argv = await store.sshArgs(for: host) else { return }
            show(session: sessions.open(host: host, argv: argv).id)
        }
    }

    /// Shows a tab. The strip, the sidebar and everything that opens a
    /// session go through this, so the pane and `Sessions` cannot drift.
    private func pick(tab: PaneTab) {
        // Picking the one already shown beside this one would draw the same
        // thing twice, and a terminal is one view that can only be in one
        // place — so the second pane drew nothing. They trade places instead,
        // which is what clicking the other pane's tab means.
        if beside == tab { beside = pane }
        pane = tab
        if case let .session(id) = tab { sessions.selected = id }
    }

    /// Opens the split on the next thing that is not already in front, or
    /// closes it. The hosts are not offered: the sidebar is the list, and the
    /// split is for watching one thing while working in another.
    private func toggleSplit() {
        guard beside == nil else {
            beside = nil
            return
        }
        beside = openTabs.first { $0 != pane }
    }

    /// Every tab that can take a side of the split, terminals before SFTP,
    /// which is the order the strip draws them in.
    private var openTabs: [PaneTab] {
        sessions.all.map { PaneTab.session($0.id) }
    }

    /// Opens the SFTP window, or brings the one open forward and points it
    /// at a host. One window: asking again moves it rather than stacking
    /// another over it.
    private func openFiles(on host: Host?) {
        FilesWindowController.show(store: store, on: host)
    }

    /// Puts a session in the pane — connecting, New Local Shell, the Window
    /// menu and "Open now" all land here.
    private func show(session id: UUID) {
        pick(tab: .session(id))
    }
}

/// The right-hand side: the sessions, or what is known about the host the
/// sidebar has selected.
struct DetailView: View {
    let store: HostStore
    let sessions: Sessions
    let host: Host?
    /// The group picked, when one is. A group has no detail view of its own —
    /// what you want from it is what is filed under it, which is the library
    /// one level down.
    let group: Group?
    /// Which tab of the strip is up, and so what fills the pane.
    let pane: PaneTab
    /// What is beside it, when the split is open.
    let beside: PaneTab?
    let onConnect: (Host) -> Void
    /// Picking a tab in the strip, or a session under "Open now".
    let onPickTab: (PaneTab) -> Void
    let onEdit: (Host) -> Void
    let onEditGroup: (Group) -> Void
    let onPick: (Selection) -> Void
    let onImport: (ImportSheet.Source) -> Void
    let onNewHost: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drawn whenever there is a list at all, so the hosts tab is
            // always there to come back to. The welcome is the exception: a
            // fresh install has no list to browse, so it meets the window it
            // has always met rather than one tab leading nowhere.
            if !(store.snapshot.hosts.isEmpty && !store.loading) {
                SessionTabBar(sessions: sessions, pane: pane, onPick: onPickTab)
                Divider()
            }
            // The welcome comes first: on a fresh install there is no list
            // to browse, and "All hosts, 0 hosts" is not what to meet.
            if store.snapshot.hosts.isEmpty && !store.loading {
                WelcomeView(store: store, onImport: onImport, onNewHost: onNewHost)
            } else if case .hosts = pane {
                hostsSide
            } else if let beside {
                // A minimum on each side, or the greedy one takes nearly all
                // of it: `FilesPane` holds an `HSplitView` of its own and
                // claims whatever it is offered, which left a terminal beside
                // it as a strip too narrow to read one column of output.
                HSplitView {
                    side(pane, front: true)
                        .frame(minWidth: 320, maxWidth: .infinity)
                    side(beside, front: false)
                        .frame(minWidth: 320, maxWidth: .infinity)
                }
            } else {
                side(pane, front: true)
            }
        }
    }

    /// One side of the pane, whichever kind of tab names it.
    ///
    /// Falls back to the host side when the tab names something no longer
    /// open: closing a tab must not leave a blank where a pane was.
    @ViewBuilder
    private func side(_ which: PaneTab, front: Bool) -> some View {
        switch which {
        case .hosts:
            hostsSide
        case let .session(id):
            if let session = sessions.all.first(where: { $0.id == id }) {
                TerminalPane(session: session, sessions: sessions, isFront: front,
                             onReconnect: onConnect)
            } else {
                hostsSide
            }
        }
    }

    /// The host side of the app: the host selected, or the list.
    @ViewBuilder
    private var hostsSide: some View {
        if let host {
            HostDetailView(store: store, host: host, sessions: sessions,
                           onConnect: onConnect,
                           onShowSession: { onPickTab(.session($0)) },
                           onEdit: onEdit)
        } else {
            library
        }
    }

    /// Nothing picked, or a group picked. Either way the answer is the list —
    /// the whole of it, or the part filed under that group.
    private var library: some View {
        LibraryView(
            store: store, group: group,
            onPick: onPick, onEditGroup: onEditGroup)
    }
}
