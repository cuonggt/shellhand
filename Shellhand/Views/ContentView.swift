import SwiftUI
import UniformTypeIdentifiers

/// What the sidebar has selected. A group stands for everything beneath it,
/// however deep.
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
nonisolated enum PaneTab: Hashable {
    case hosts
    case session(UUID)
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var store: HostStore
    @State private var sessions = Sessions()
    @State private var selection: Selection?
    @State private var search = ""
    /// The sidebar's chosen tags, held here with the search so that the host
    /// pane narrows to what the sidebar does.
    @State private var chosenTags: Set<String> = []
    @State private var editing: Host?
    @State private var editingGroup: Group?
    @State private var deletingHost: Host?
    @State private var deletingGroup: Group?
    /// A tab waiting on an answer before it is closed or reconnected.
    @State private var closing: PendingClose?
    /// File ▸ Export…: the list as written, and whether the save panel is up.
    @State private var exportText = ""
    @State private var exportingList = false
    @State private var showingQuickConnect = false
    /// Which way in the import sheet opens on, and whether it is open at all.
    ///
    /// One value rather than a flag beside a source, because the content of a
    /// sheet driven by `isPresented` is built from the view as it was before
    /// the flag flipped: pressing CSV on the welcome opened the sheet on the
    /// ssh config every time.
    @State private var importing: ImportSheet.Source?
    /// Open by default, and remembered: the host's details live **here**
    /// now rather than in the pane, so a window that came up with it shut
    /// would answer a click on a host with nothing anywhere. `@AppStorage`
    /// rather than `@State` because it is a preference about you, not about
    /// this window — and a new key, since no existing one means this.
    @AppStorage("hostInspector") private var showingInspector = true
    /// Which group the pane is **looking at**, which is not what is selected
    /// — see `Browsing`. Empty means the whole list.
    @State private var browsing = ""
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
    /// What was wrong with the settings file at launch, until it is read.
    ///
    /// Its own state rather than `store.report`: a refresh that works clears
    /// `lastError`, and the first one lands right after the window opens.
    @State private var configProblem: String?

    init(dbPath: String, configPath: String = "", configProblem: String? = nil) {
        _store = State(initialValue: HostStore(dbPath: dbPath))
        self.configPath = configPath
        _configProblem = State(initialValue: configProblem)
    }

    private var selectedHost: Host? {
        guard case let .host(id) = selection else { return nil }
        return store.snapshot.hosts.first { $0.id == id }
    }

    private var selectedGroup: Group? {
        guard case let .group(id) = selection else { return nil }
        return store.group(id)
    }

    /// The place the pane shows: `browsing`, with a group that has been
    /// deleted since forgotten. Deliberately **not** `selectedGroup`, which
    /// is nil for a host — that is the whole of what `Browsing` is for.
    private var browsedGroup: Group? {
        store.group(Browsing.settled(browsing, within: store.snapshot.groups))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                store: store, selection: $selection, search: $search,
                chosenTags: $chosenTags,
                actions: actions, onConnect: connect,
                onBrowse: { now in
                    selection = now
                    pane = .hosts
                },
                browsingAll: browsedGroup == nil && pane == .hosts,
                onBrowseAll: { browse(to: "") })
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
                .toolbar { listToolbar }
        } detail: {
            DetailView(
                store: store, sessions: sessions,
                group: browsedGroup, selection: selection,
                actions: actions,
                pane: pane, beside: beside,
                onConnect: connect, onPickTab: pick(tab:),
                tabActions: tabActions,
                onEdit: { editing = $0 },
                onEditGroup: { editingGroup = $0 },
                onPick: { selection = $0 },
                onImport: { open(import: $0) }, onNewHost: { editing = Host() },
                search: search, tags: chosenTags, onBrowse: browse(to:),
                onClearFilter: {
                    search = ""
                    chosenTags = []
                })
                .toolbar { paneToolbar }
        }
        // Tags the window so Shellhand ▸ Hosts can find it again from an
        // SFTP window or from Settings, where this scene's actions are not
        // in focus.
        .background(TagsHostsWindow())
        // And asks before the window closes on sessions somebody is in: the
        // close button, File ▸ Close and Close All all go through its
        // delegate, which is where this stands. (⌘W never reaches the window:
        // Close Tab holds it, and SwiftUI's Close is left with no key at all.)
        .background(GuardsClosing(sessions: sessions))
        // ⌃⇥ and ⌃⇧⇥ through the strip, which the Window menu cannot carry
        // beside ⇧⌘] and ⇧⌘[ — an item holds one key.
        .background(StepsTabs(step: step(by:)))
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
            browsing = Browsing.scope(
                after: now, from: browsing,
                hostsGroup: {
                    guard case let .host(id) = now else { return nil }
                    return store.snapshot.hosts.first { $0.id == id }?.groupId
                }())
            if case let .host(id) = now {
                storedHostID = id
                // **Deferred a turn of the loop on purpose.** Changing the
                // inspector in the same update that moves the pane crashes
                // SwiftUI — "reentrant operation", two things about one split
                // in a single transaction — and `pane` is set three lines
                // below. It is intermittent, so a dozen clicks is the test,
                // not one.
                DispatchQueue.main.async { showingInspector = true }
            }
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
        .confirmationDialog(
            closing?.question.title ?? "",
            isPresented: Binding(get: { closing != nil },
                                 set: { if !$0 { closing = nil } }),
            titleVisibility: .visible
        ) {
            Button(closing?.question.confirm ?? "Close", role: .destructive) {
                if let pending = closing {
                    finish(pending.sessions, reconnecting: pending.reconnecting,
                           keeping: pending.keeping)
                }
            }
        } message: {
            Text(closing?.question.message ?? "")
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
            pane = Panes.following(selected: now, front: pane)
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
        .fileExporter(
            isPresented: $exportingList,
            document: YAMLDocument(text: exportText),
            contentType: .yaml,
            defaultFilename: YAMLDocument.defaultFilename
        ) { result in
            // Cancelling is an answer, not a failure; anything else the disk
            // refused is said rather than dropped.
            if case let .failure(error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                store.report("The list could not be exported: \(error.localizedDescription)")
            }
        }
        // A constant binding cannot be dismissed: the alert came back the
        // moment it was closed, because nothing ever cleared the error.
        // One alert for both, the store's first: dismissing clears only the
        // one shown, so a settings problem behind it comes up next.
        .alert("Shellhand", isPresented: Binding(
            get: { store.lastError != nil || configProblem != nil },
            set: { shown in if !shown { dismissProblem() } }
        )) {
            Button("OK") { dismissProblem() }
        } message: {
            Text(store.lastError ?? configProblem ?? "")
        }
    }

    private func dismissProblem() {
        if store.lastError != nil { store.clearError() } else { configProblem = nil }
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
                openFiles(on: subjectHost)
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
            case .connected: return session.host.map(\.destinationLine) ?? "local"
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

    /// What the inspector describes — see `Panes.inspected`.
    private var inspected: Panes.Inspected {
        Panes.inspected(
            inFront: frontSession.map { Panes.Opening.of($0.host) },
            selectedHost: selectedHost?.id, selectedGroup: selectedGroup?.id,
            isListed: isListed)
    }

    @ViewBuilder
    private var inspector: some View {
        switch inspected {
        case let .host(id):
            if let host = store.snapshot.hosts.first(where: { $0.id == id }) {
                // The whole of it. There used to be two shapes — a compact one
                // here and the full one in the pane — and `compact` existed so
                // the two would not be the same view twice. The pane shows the
                // list now, so this is the only place a host is described and
                // there is nothing left to repeat.
                HostDetailView(
                    store: store, host: host, sessions: sessions,
                    onConnect: connect,
                    onShowSession: { pick(tab: .session($0)) },
                    onEdit: { editing = $0 })
            } else {
                nothingSelected
            }
        case let .group(id):
            if let group = store.group(id) {
                GroupInspector(
                    store: store, group: group,
                    onEdit: { editingGroup = $0 },
                    onNewHostIn: { editing = Host(groupId: $0.id) },
                    onNewGroupIn: { editingGroup = Group(parentId: $0.id) })
            } else {
                nothingSelected
            }
        case let .unsaved(host):
            UnsavedHostInspector(host: host, onSave: { editing = $0 })
        case .localShell:
            LocalShellInspector()
        case .nothing:
            nothingSelected
        }
    }

    private var nothingSelected: some View {
        ContentUnavailableView(
            "Nothing selected", systemImage: "sidebar.right",
            description: Text("Pick a host or a group to see what it connects with."))
    }

    /// Opens the import sheet on one of its three ways in.
    private func open(import source: ImportSheet.Source) { importing = source }

    /// What the menu bar can ask this window to do, and what is possible now.
    private var actions: AppActions {
        AppActions(
            newTab: openNewTab,
            newLocalShell: { show(session: sessions.openLocalShell().id) },
            newHost: { editing = Host() },
            newHostIn: { group in editing = Host(groupId: group.id) },
            onHost: AppActions.HostActions(
                edit: { editing = $0 },
                delete: { deletingHost = $0 },
                copyCommand: { copyAsCommand(for: $0) }),
            onGroup: AppActions.GroupActions(
                newGroupIn: { editingGroup = Group(parentId: $0.id) },
                edit: { editingGroup = $0 },
                delete: { deletingGroup = $0 }),
            editHost: { if let host = subjectHost { editing = host } },
            // On whatever host is selected, so that pressing this with one
            // picked opens straight onto it. With nothing picked the far
            // side asks which host, rather than showing this Mac twice.
            openFiles: { openFiles(on: subjectHost) },
            showHosts: { pick(tab: .hosts) },
            openFilesOn: { host in openFiles(on: host) },
            // A new group goes inside whichever one is selected, which is
            // what picking one and asking for a group means.
            newGroup: { editingGroup = Group(parentId: selectedGroup?.id ?? "") },
            editGroup: { if let group = selectedGroup { editingGroup = group } },
            deleteHost: { deletingHost = subjectHost },
            deleteGroup: { deletingGroup = selectedGroup },
            copyAsCommand: copyAsCommand,
            connect: { if let host = subjectHost { connect(host) } },
            reconnect: {
                if let session = frontSession, session.host != nil {
                    end(session, reconnecting: true)
                }
            },
            closeTab: { if let session = frontSession { end(session) } },
            toggleSplit: toggleSplit,
            quickConnect: { showingQuickConnect = true },
            openImport: { open(import: .sshConfig) },
            find: { frontSession?.findOpen.toggle() },
            findNext: { _ = frontSession?.findNext() },
            findPrevious: { _ = frontSession?.findPrevious() },
            clearScrollback: { frontSession?.clearScrollback() },
            biggerText: { frontSession?.changeFontSize(by: 1) },
            smallerText: { frontSession?.changeFontSize(by: -1) },
            actualSize: { frontSession?.resetFontSize() },
            toggleInspector: { showingInspector.toggle() },
            openSessions: sessions.all.map {
                SessionItem(id: $0.id, title: Sessions.shortTitle(of: $0))
            },
            showSession: show(session:),
            nextTab: { step(by: 1) },
            previousTab: { step(by: -1) },
            groupInside: selectedGroup?.name ?? "",
            hasHost: subjectHost != nil,
            hasGroup: selectedGroup != nil,
            hasSession: frontSession != nil,
            canSplit: Panes.canSplit(front: pane, open: openTabs),
            canStepTabs: Panes.stepping(by: 1, from: pane, sessions: openTabs) != nil,
            exportList: {
                Task {
                    exportText = await store.exportYAML() ?? ""
                    exportingList = !exportText.isEmpty
                }
            },
            canExport: !store.snapshot.hosts.isEmpty || !store.snapshot.groups.isEmpty,
            canNewTab: newTabOpening != nil)
    }

    /// The listed host the Host menu, ⌘B and the toolbar's SFTP act on — see
    /// `Panes.subject`. The session in front wins over the selection.
    private var subjectHost: Host? {
        Panes.subject(
            inFront: frontSession.map { Panes.Opening.of($0.host) },
            selected: selectedHost?.id, isListed: isListed
        ).flatMap { id in store.snapshot.hosts.first { $0.id == id } }
    }

    /// What ⌘T would open now — see `Panes.newTab`.
    private var newTabOpening: Panes.Opening? {
        Panes.newTab(
            inFront: frontSession.map { Panes.Opening.of($0.host) },
            selected: selectedHost?.id, isListed: isListed)
    }

    /// Whether the list still holds a host, for the rules that ask.
    private func isListed(_ id: String) -> Bool {
        store.snapshot.hosts.contains { $0.id == id }
    }

    /// ⌘T. A host is connected to as the list has it now rather than as the
    /// session in front was opened, so an edit made since is the one used.
    private func openNewTab() { open(newTabOpening) }

    /// Opens another session of what an `Opening` names — ⌘T's, or a tab's
    /// Duplicate.
    private func open(_ opening: Panes.Opening?) {
        switch opening {
        case let .host(id)?:
            if let host = store.snapshot.hosts.first(where: { $0.id == id }) { connect(host) }
        case let .unsaved(host)?:
            connect(host)
        case .localShell?:
            show(session: sessions.openLocalShell().id)
        case nil:
            break
        }
    }

    /// What a tab's × and its own menu do, each to the session it is on.
    private var tabActions: TabActions {
        TabActions(
            reconnect: { end($0, reconnecting: true) },
            duplicate: { open(duplicate(of: $0)) },
            openSFTP: { session in
                if let id = Panes.sftp(for: .of(session.host), isListed: isListed),
                   let host = store.snapshot.hosts.first(where: { $0.id == id }) {
                    openFiles(on: host)
                }
            },
            close: { end($0) },
            closeOthers: closeOthers(keeping:),
            canDuplicate: { duplicate(of: $0) != nil },
            canOpenSFTP: { Panes.sftp(for: .of($0.host), isListed: isListed) != nil })
    }

    /// What a tab's Duplicate opens: ⌘T's rule, asked of that tab rather
    /// than of the one in front.
    private func duplicate(of session: TerminalSession) -> Panes.Opening? {
        Panes.newTab(inFront: .of(session.host), selected: nil, isListed: isListed)
    }

    /// Tabs waiting on an answer, and what was going to happen to them.
    private struct PendingClose {
        let sessions: [TerminalSession]
        let reconnecting: Bool
        /// The tab to bring in front afterwards: the one Close Other Tabs
        /// kept.
        let keeping: TerminalSession?
        let question: Closing.Question
    }

    /// Closes a tab — or reconnects it — asking first when that would drop a
    /// session somebody is in. ⌘W, ⌘R, a tab's × and its menu all come
    /// through here, so there is one place the question is put.
    private func end(_ session: TerminalSession, reconnecting: Bool = false) {
        if let question = Closing.question(
            reconnecting ? .reconnecting : .closingTab,
            dropping: [Closing.Open(session)], confirming: Closing.confirmsNow)
        {
            closing = PendingClose(
                sessions: [session], reconnecting: reconnecting, keeping: nil, question: question)
        } else {
            finish([session], reconnecting: reconnecting, keeping: nil)
        }
    }

    /// A tab's Close Other Tabs: every session but this one, asked about as
    /// one question, and this one brought in front.
    private func closeOthers(keeping session: TerminalSession) {
        let others = sessions.all.filter { $0.id != session.id }
        if let question = Closing.question(
            .closingOthers, dropping: others.map(Closing.Open.init),
            confirming: Closing.confirmsNow)
        {
            closing = PendingClose(
                sessions: others, reconnecting: false, keeping: session, question: question)
        } else {
            finish(others, reconnecting: false, keeping: session)
        }
    }

    /// What `end` and `closeOthers` do once nothing is left to ask.
    /// Reconnecting rebuilds the argv rather than reusing it, since the host
    /// may have been edited.
    private func finish(_ ending: [TerminalSession], reconnecting: Bool, keeping: TerminalSession?) {
        for session in ending { sessions.close(session) }
        if reconnecting, let host = ending.first?.host { connect(host) }
        if let keeping { pick(tab: .session(keeping.id)) }
    }

    /// The ssh command for the selected host, on the pasteboard — the same
    /// argv the app would run, so it can be pasted into a terminal or a
    /// runbook and behave the same.
    private func copyAsCommand() {
        guard let host = subjectHost else { return }
        copyAsCommand(for: host)
    }

    /// The same, on a host handed over rather than read out of the selection,
    /// which is what a row's own menu needs.
    private func copyAsCommand(for host: Host) {
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
            await learnOS(of: host)
        }
    }

    /// Asks a host what it is, so it can be drawn with its own mark.
    ///
    /// **How often is `Host.shouldAskOS`**, which is a day — see it for why
    /// neither "once ever" nor "every connect" is right — and whether at all
    /// is the switch in Settings ▸ General. This only obeys them.
    ///
    /// After the session, not before: the terminal is what was asked for and
    /// must not wait on an icon. Everything here fails quietly — see
    /// `Core.osOf` for why none of its failures is worth reporting.
    private func learnOS(of host: Host) async {
        guard host.shouldAskOS(allowed: Host.asksNow) else { return }
        let said = await Core.shared.osOf(db: store.dbPath, hostID: host.id)
        // Read again rather than editing the copy this closure captured: it
        // may be minutes old by now, and saving a stale one would undo
        // whatever was edited in between.
        guard var fresh = store.snapshot.hosts.first(where: { $0.id == host.id }) else { return }
        // Stamped whether or not it answered. A host that cannot say — one
        // taking only a password, a BSD, a container with no sftp subsystem —
        // must not be asked again on the next connect, which is what asking
        // only on success would do. An answer it did give replaces whatever
        // was there, so a rebuilt machine corrects itself.
        fresh.osSeen = Date().timeIntervalSince1970
        if let said {
            fresh.os = said.id
            fresh.osName = said.name
        }
        _ = await store.save(fresh)
    }

    /// Shows a tab. The strip, the sidebar and everything that opens a
    /// session go through this, so the pane and `Sessions` cannot drift.
    /// Goes to a place in the list: the whole of it for "", a group otherwise.
    /// The whole list clears a group selection, or the sidebar would go on
    /// highlighting the group the pane has just left; a host stays selected,
    /// being a thing rather than a place.
    private func browse(to scope: String) {
        if scope.isEmpty {
            if case .group = selection { selection = nil }
            browsing = ""
        } else {
            selection = .group(scope)
        }
        pane = .hosts
    }

    private func pick(tab: PaneTab) {
        (pane, beside) = Panes.picking(tab, front: pane, beside: beside)
        if case let .session(id) = tab { sessions.selected = id }
    }

    /// The next or previous tab of the strip, through `pick` so that a tab
    /// shown beside trades places exactly as a click on it does. False when
    /// there is nowhere to go, so ⌃⇥ can be let through to whatever wants it.
    @discardableResult
    private func step(by offset: Int) -> Bool {
        guard let tab = Panes.stepping(by: offset, from: pane, sessions: openTabs)
        else { return false }
        pick(tab: tab)
        return true
    }

    /// Opens the split on the next thing that is not already in front, or
    /// closes it. The hosts are not offered: the sidebar is the list, and the
    /// split is for watching one thing while working in another.
    private func toggleSplit() {
        beside = Panes.splitting(front: pane, beside: beside, open: openTabs)
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
    /// The place the pane is looking at, or nil for the whole list. This is
    /// `Browsing`'s answer rather than the selection: picking a host must not
    /// move the list out from under the click that picked it.
    let group: Group?
    /// What is selected, for the pane to draw as selected.
    let selection: Selection?
    /// For the pane's row menu, which is the sidebar's own.
    let actions: AppActions
    /// Which tab of the strip is up, and so what fills the pane.
    let pane: PaneTab
    /// What is beside it, when the split is open.
    let beside: PaneTab?
    let onConnect: (Host) -> Void
    /// Picking a tab in the strip, or a session under "Open now".
    let onPickTab: (PaneTab) -> Void
    /// A tab's × and its own menu, each acting on the tab's own session.
    let tabActions: TabActions
    let onEdit: (Host) -> Void
    let onEditGroup: (Group) -> Void
    let onPick: (Selection) -> Void
    let onImport: (ImportSheet.Source) -> Void
    let onNewHost: () -> Void
    /// What the sidebar is narrowed to, for the host pane to narrow to too.
    let search: String
    let tags: Set<String>
    let onBrowse: (String) -> Void
    let onClearFilter: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drawn whenever there is a list at all, so the hosts tab is
            // always there to come back to. The welcome is the exception: a
            // fresh install has no list to browse, so it meets the window it
            // has always met rather than one tab leading nowhere.
            if Panes.showsTabs(hosts: store.snapshot.hosts.count,
                               loading: store.loading, sessions: sessions.all.count) {
                SessionTabBar(sessions: sessions, pane: pane, onPick: onPickTab,
                              actions: tabActions)
                Divider()
            }
            // The welcome stands in for the **hosts tab** on a fresh install,
            // not for the window: see `Panes.welcoming`.
            if Panes.welcoming(hosts: store.snapshot.hosts.count,
                               loading: store.loading, front: pane) {
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

    /// The host side of the app, which is **always the list**.
    ///
    /// It used to swap itself for the selected host's details, so selecting a
    /// host in the pane made the pane disappear — you could never click down
    /// a list, and the thing you had just picked was the only thing you could
    /// no longer see in context. The details are the inspector's job now, and
    /// the list stays put with the selection drawn on it.
    private var hostsSide: some View {
        HostsPane(
            store: store, group: group, selection: selection,
            onPick: onPick, onConnect: onConnect, onEditGroup: onEditGroup,
            actions: actions, search: search, tags: tags,
            onBrowse: onBrowse, onClearFilter: onClearFilter)
    }
}
