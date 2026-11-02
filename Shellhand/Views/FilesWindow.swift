import SwiftUI
import UniformTypeIdentifiers

/// A reference to something in one of the two panes, for dragging between
/// them. A remote file has no URL to hand over, so what travels is which pane
/// it is in and what it is called.
nonisolated struct FileRef: Codable, Transferable {
    var place: String
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .shellhandFile)
    }
}

nonisolated extension UTType {
    static let shellhandFile = UTType(exportedAs: "com.shellhand.file-reference")
}

/// Files: two places side by side, and what is going between them.
///
/// A window of its own, one per time Files is opened. It was a tab in the
/// strip with the terminals for a while, on the grounds that a browser is one
/// end of one host's connection like a session is. What that cost is what a
/// window buys and why it is back: a window can sit beside a terminal and a
/// tab cannot, so watching a transfer while typing somewhere else meant
/// switching away from the thing you were watching.
///
/// This Mac is always the left side; the right is the host it was opened on,
/// or a question if it was opened from no host in particular. Either side can
/// be re-pointed from its own menu, so host-to-host copying is intact — it is
/// just not what opening Files means.
struct FilesPane: View {
    let store: HostStore
    let files: FilesModel
    /// Only to start the right side off: the panes can be re-pointed after.
    let openedOn: Host?

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                PlacePane(store: store, files: files, place: files.left, other: files.right,
                          side: "left")
                PlacePane(store: store, files: files, place: files.right, other: files.left,
                          side: "right")
            }
            if !files.transfers.isEmpty {
                Divider()
                TransfersStrip(files: files)
            }
        }
        // The store is the window's own and already loaded, so there is
        // nothing to refresh here — only the two sides to point.
        .task { await files.start(on: openedOn) }
        // Asked once for the whole batch, not once per file: a drag of forty
        // answered forty times is a dialog nobody reads by the fourth.
        // Dismissing it answers Cancel, so the copy parked on it is never
        // left waiting on a question that is no longer on screen.
        .confirmationDialog(
            files.asking?.said ?? "",
            isPresented: Binding(
                get: { files.asking != nil },
                set: { if !$0 { files.answer(nil) } }),
            titleVisibility: .visible
        ) {
            if let asking = files.asking {
                Button(asking.replacing, role: .destructive) { files.answer(.replace) }
                Button(asking.skipping) { files.answer(.skip) }
            }
            Button("Cancel", role: .cancel) { files.answer(nil) }
        } message: {
            Text("Replacing cannot be undone.")
        }
    }
}

private struct PlacePane: View {
    let store: HostStore
    let files: FilesModel
    let place: FilePlace
    let other: FilePlace
    /// Which pane this is, so a drag knows where it came from.
    let side: String

    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\RemoteEntry.name)]
    @State private var typedPath = ""
    @State private var editingPath = false
    @State private var confirmingDelete = false
    @State private var renaming: RemoteEntry?
    @State private var newFolder = false
    @State private var name = ""
    @FocusState private var listFocused: Bool

    /// Whether the window's keys act on this side. The keys go on the
    /// buttons of the side in front, rather than in the menus: a menu item
    /// takes its key even while it is disabled, and ⌘R is Terminal ▸
    /// Reconnect's there, disabled whenever SFTP is in front.
    private var isActive: Bool { files.active === place }

    private var entries: [RemoteEntry] {
        let sorted = place.entries.sorted(using: sortOrder)
        return sorted.filter(\.isDir) + sorted.filter { !$0.isDir }
    }

    private var chosen: [RemoteEntry] { entries.filter { selection.contains($0.name) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if Places.notice(listed: !place.listing.path.isEmpty, failure: place.failure) == .banner,
               let failure = place.failure {
                banner(failure)
                Divider()
            }
            // A side with no listing says why on the table's own ground, with
            // no table: laid over one, its stripes ran through the question
            // and the refusal's card, under a sortable header over nothing.
            if place.listing.path.isEmpty {
                waiting
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SwiftUI.Color(nsColor: .controlBackgroundColor))
            } else {
                table
            }
            Divider()
            footer
        }
        // On the side, not the table, which is not there while a side is
        // re-pointed and so would miss the listing it came back with.
        .onChange(of: place.listing.path) { _, _ in selection = [] }
        .frame(minWidth: 400)
        .confirmationDialog(
            deleting.title, isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button(deleting.confirm, role: .destructive) {
                let going = chosen
                selection = []
                Task { await place.remove(going) }
            }
        } message: {
            Text(deleting.message)
        }
        .alert("Rename", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let entry = renaming { Task { await place.rename(entry, to: name) } }
                renaming = nil
            }
            // Greyed for a name the rename would refuse, as the sidebar's
            // tag rename is: it closed the question and did nothing.
            .disabled(!Places.usableName(name, renaming: renaming?.name))
        }
        // New Folder from the menu bar, on the side the window's keys act on.
        .onChange(of: files.newFolderAsks) { _, _ in
            guard isActive, !place.listing.path.isEmpty else { return }
            name = ""
            newFolder = true
        }
        .alert("New Folder", isPresented: $newFolder) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task { await place.makeDirectory(named: name) } }
                .disabled(!Places.usableName(name))
        } message: {
            Text(Places.newFolderPlace(in: place.folder, on: place.title))
        }
    }

    // MARK: the parts

    private var deleting: Places.DeleteQuestion {
        Places.deleteQuestion(chosen.map(\.name), local: place.isLocal, on: place.title)
    }

    /// What went wrong while a listing is up, said above it and left there
    /// until it is read. Before this, nothing drew it: a refused rename,
    /// delete or new folder happened without a word.
    private func banner(_ failure: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(failure)
                .font(.callout)
                .selectable(failure)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss") { place.clearFailure() }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.12))
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Menu {
                    Button("This Mac") { Task { await place.use(nil) } }
                    Divider()
                    // In order, as the sidebar is: in the order they were
                    // added, finding one in forty meant reading all forty.
                    ForEach(store.snapshot.hosts.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }) { host in
                        Button(host.name) { Task { await place.use(host) } }
                    }
                } label: {
                    Label(place.title, systemImage: place.isLocal ? "laptopcomputer" : "server.rack")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if place.connecting { ProgressView().controlSize(.small) }
                Spacer()

                Menu {
                    Toggle("Show Hidden Files", isOn: Binding(
                        get: { place.showHidden }, set: { place.showHidden = $0 }))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More actions")
                .menuStyle(.borderlessButton)
                .fixedSize()
                // Greyed with the row below it while there is no listing:
                // Show Hidden Files had nothing to show or hide, beside an
                // arrow, a path and two buttons all grey.
                .disabled(place.listing.path.isEmpty)
            }

            HStack(spacing: 4) {
                Button { Task { await place.parent() } } label: {
                    Image(systemName: "arrow.up").foregroundStyle(iconColour(place.canGoUp))
                }
                .buttonStyle(.borderless)
                // Finder's name for the move: this window says folder, and
                // "Up one directory" sat beside its New Folder.
                .accessibilityLabel("Enclosing Folder")
                .help("Enclosing Folder")
                // Greyed with no folder above as well as with nothing
                // listed: at "/" it stood live and did nothing.
                .disabled(!place.canGoUp)

                // Typing a path beats walking to it, which is the whole of
                // what this field is for. Enter goes there.
                TextField("Path", text: $typedPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    // Greyed with the buttons beside it while there is no
                    // listing — a side asking which host, or refused: Return
                    // there went nowhere and said nothing.
                    .disabled(place.listing.path.isEmpty)
                    .onSubmit { Task { await place.go(to: typedPath) } }
                    .onChange(of: place.listing.path) { _, now in typedPath = now }
                    .onAppear { typedPath = place.listing.path }

                Button {
                    name = ""
                    newFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus").foregroundStyle(iconColour(listed))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("New Folder")
                .help("New Folder")
                .keyboardShortcut(isActive ? KeyboardShortcut("n", modifiers: [.command, .shift]) : nil)
                .disabled(place.listing.path.isEmpty)

                Button { Task { await place.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(iconColour(listed))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh")
                .help("Refresh")
                .keyboardShortcut(isActive ? KeyboardShortcut("r", modifiers: .command) : nil)
                .disabled(place.listing.path.isEmpty)
            }
        }
        .padding(8)
    }

    /// The header's icons in the colours AppKit draws a control's text in:
    /// black while they can act, as the "…" menu beside them is, and its
    /// grey while the side lists nothing. Borderless, they were drawn
    /// mid-grey when live, nearer greyed than live beside the menu's black —
    /// and a hierarchical style changed nothing, since `.primary` inside a
    /// borderless button is the button's own grey, while `.tertiary` made
    /// the greyed ones fainter than the greyed menu.
    private func iconColour(_ live: Bool) -> SwiftUI.Color {
        SwiftUI.Color(nsColor: live ? .controlTextColor : .disabledControlTextColor)
    }

    /// Whether this side lists anything, which New Folder and Refresh need.
    private var listed: Bool { !place.listing.path.isEmpty }

    private var table: some View {
        Table(entries, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { entry in
                Label {
                    Text(entry.name)
                } icon: {
                    Image(systemName: entry.isDir ? "folder" : "doc")
                        .foregroundStyle(entry.isDir ? AnyShapeStyle(.tint)
                                         : AnyShapeStyle(.secondary))
                }
                .draggable(FileRef(place: side, name: entry.name))
            }
            TableColumn("Size", value: \.size) { entry in
                Text(entry.isDir ? "—" : entry.size.formatted(.byteCount(style: .file)))
                    .foregroundStyle(.secondary)
            }
            // Held to what they hold, so the room left goes to Name: with no
            // most, the spare was shared, Size taking 154pt for "6 bytes"
            // beside a Name of 172.
            .width(min: 70, ideal: 80, max: 100)
            TableColumn("Modified", value: \.modTime) { entry in
                Text(entry.modTime).foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 130, max: 150)
        }
        .contextMenu(forSelectionType: String.self) { names in
            menu(for: names)
        } primaryAction: { names in
            open(names)
        }
        // The side last worked in is the one ⌘R and ⇧⌘N act on.
        .focused($listFocused)
        .onChange(of: listFocused) { _, now in if now { files.active = place } }
        // The keyboard starts in the list of the side in front, as the host
        // window's starts in its host list: left alone, AppKit gave it to
        // This Mac's path field, the window's first text field, where ↓,
        // Space and ⌫ edited the path rather than acting on a file.
        .task { if isActive { listFocused = true } }
        // ⌫ asks first, through the same question as the menu's Delete. Nil
        // with nothing selected, which greys Edit ▸ Delete: always handed a
        // closure, it stayed live and did nothing.
        .onDeleteCommand(perform: selection.isEmpty ? nil : { confirmingDelete = true })
        // Space, as in Finder: a look at the file picked, on this Mac. A file
        // on a host would have to be fetched first.
        .onKeyPress(.space) {
            guard place.isLocal, chosen.count == 1, let entry = chosen.first else { return .ignored }
            QuickLook.shared.show(place.localURL(named: entry.name))
            return .handled
        }
        // A folder opened takes its selection with it (`body`): kept, the
        // folder you went into stayed selected inside itself — "1 of 0
        // selected", and a Copy button live with nothing to copy.
        // From the other pane, and from Finder.
        .dropDestination(for: FileRef.self) { refs, _ in
            let names = Set(refs.filter { $0.place != side }.map(\.name))
            guard !names.isEmpty else { return false }
            let coming = other.entries.filter { names.contains($0.name) }
            Task { await files.copy(coming, from: other, to: place) }
            return true
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { for url in urls where url.isFileURL { await files.bring(url, to: place) } }
            return true
        }
    }

    @ViewBuilder
    private var waiting: some View {
        if place.connecting {
            ProgressView("Connecting to \(place.title)…")
        } else if let failure = place.failure, let host = place.host {
            // The host as the list has it now, for Try Again and for what the
            // card offers: one deleted since has no editor and no tab to open.
            let listed = store.snapshot.hosts.first { $0.id == host.id }
            Unreached(host: host, listed: listed != nil, said: failure,
                      trouble: Places.trouble(failure, on: host.name)) {
                Task { await place.tryAgain(with: listed) }
            }
        } else if let failure = place.failure {
            ContentUnavailableView {
                // As a host's refusal says it, "Couldn't connect to web",
                // where this kept the "Cannot show this" the card replaced.
                Label("Couldn't open this folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            }
        } else {
            // Only the far side is ever unpointed — this Mac is always the
            // near one — so this asks for a host rather than for "a place",
            // in the header's own words: it said "Pick a host" under a header
            // saying "Choose a host". Its "its" is the host's: after "Use the
            // menu above" it read as the menu's.
            ContentUnavailableView {
                Label("Choose a host", systemImage: "server.rack")
            } description: {
                Text("Choose one from the menu above, and its files show here beside your own.")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(Places.copyTitle(to: other.chosen, title: other.title)) {
                let going = chosen
                Task { await files.copy(going, from: place, to: other) }
            }
            .controlSize(.small)
            .disabled(chosen.isEmpty || other.listing.path.isEmpty)
            // Not drawn under a side with nothing listed, which has nothing
            // to choose and copy: it sat there greyed for good. Kept in its
            // place, so the two sides' footers stand the same height.
            .opacity(place.listing.path.isEmpty ? 0 : 1)
            .accessibilityHidden(place.listing.path.isEmpty)

            Spacer()
            Text(count).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
    }

    @ViewBuilder
    private func menu(for names: Set<String>) -> some View {
        let picked = entries.filter { names.contains($0.name) }
        if !picked.isEmpty {
            Button(Places.copyTitle(to: other.chosen, title: other.title)) {
                Task { await files.copy(picked, from: place, to: other) }
            }
            .disabled(other.listing.path.isEmpty)
            if picked.count == 1, let entry = picked.first {
                if entry.isDir {
                    Button("Open") { Task { await place.go(to: place.path(entry.name)) } }
                }
                // Folders too: SFTP renames a folder as it renames a file, and
                // only a file was offered it.
                Button("Rename…") {
                    name = entry.name
                    renaming = entry
                }
                if place.isLocal, !entry.isDir {
                    Button("Quick Look") {
                        QuickLook.shared.show(place.localURL(named: entry.name))
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [place.localURL(named: entry.name)])
                    }
                }
            }
            Divider()
            Button(place.isLocal ? "Move to Trash…" : "Delete…") {
                selection = names
                confirmingDelete = true
            }
        }
    }

    /// Double-click: into a directory, or across to the other pane — and a
    /// beep where the other side has nowhere to put it, pointed nowhere,
    /// connecting or refused: it did nothing and said nothing.
    private func open(_ names: Set<String>) {
        let picked = entries.filter { names.contains($0.name) }
        if picked.count == 1, let entry = picked.first, entry.isDir {
            Task { await place.go(to: place.path(entry.name)) }
            return
        }
        guard other.via != nil else {
            NSSound.beep()
            return
        }
        Task { await files.copy(picked, from: place, to: other) }
    }

    /// Nothing for a side showing no listing — pointed nowhere, connecting
    /// or refused — where "0 items" read as an empty folder it did not have.
    private var count: String {
        guard !place.listing.path.isEmpty else { return "" }
        var said = chosen.isEmpty
            ? (entries.count == 1 ? "1 item" : "\(entries.count) items")
            : "\(chosen.count) of \(entries.count) selected"
        if !place.showHidden, place.hiddenCount > 0 { said += " · \(place.hiddenCount) hidden" }
        return said
    }
}

/// A host SFTP could not open, said as what it means and what to do about it:
/// a terminal tab, where a new key's question and a password can be
/// answered, the host's editor, where its address, user and key are put
/// right, and another go. It said "Cannot show this" over ssh's sentence.
///
/// **Drawn as the terminal's card for the same refusal is**: the headline in
/// red with its mark, ssh's own line boxed and first, what it means under it,
/// and the way on leading, prominent. It was plain black, with the line
/// unboxed after the advice and the retry last, so one failure looked like
/// two things in two windows.
private struct Unreached: View {
    let host: Host
    /// Whether the list still holds it: a host deleted since has nothing for
    /// Open in Terminal or Edit Host… to open, and both did nothing.
    let listed: Bool
    let said: String
    let trouble: Places.Trouble
    let onTryAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(trouble.title, systemImage: SessionStatus.couldNotConnect.symbol)
                .font(.headline)
                .foregroundStyle(SwiftUI.Color.red)
            // As tall as its lines, as the terminal card's: held to one,
            // ssh's line lost its end.
            Text(said)
                .font(.caption.monospaced())
                .selectable(said)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            if !trouble.advice.isEmpty {
                Text(trouble.advice)
                    .font(.callout)
                    .foregroundStyle(Card.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack { buttons(stacked: false) }
                // One above another at one width, as the terminal card's.
                VStack(alignment: .leading) { buttons(stacked: true) }
                    .fixedSize(horizontal: true, vertical: false)
            }
            // Small, as the terminal card's are: the one card drawn in two
            // windows had its buttons at two sizes.
            .controlSize(.small)
        }
        // The terminal card's shape, where it was 460 wide in 24pt margins.
        .cardChrome()
    }

    /// The way on first and prominent, as Reconnect leads the terminal's
    /// card: a terminal tab where one can answer what SFTP cannot, and
    /// otherwise another go — then the host's editor, as the card has it.
    @ViewBuilder
    private func buttons(stacked: Bool) -> some View {
        if trouble.offersTerminal && listed {
            Button { HostRequest.post(.terminal, for: host) } label: {
                Text("Open in Terminal").stackedButtonLabel(stacked)
            }
            .buttonStyle(.borderedProminent)
            Button(action: onTryAgain) { Text("Try Again").stackedButtonLabel(stacked) }
        } else {
            Button(action: onTryAgain) { Text("Try Again").stackedButtonLabel(stacked) }
                .buttonStyle(.borderedProminent)
        }
        // As a terminal tab that could not connect offers it. Only Try Again
        // was here, under advice to check the host's user and key; Try Again
        // reads the host from the list afresh (`FilePlace.tryAgain(with:)`),
        // so what is put right there is what it tries, under its new name.
        if listed {
            Button { HostRequest.post(.editor, for: host) } label: {
                Text("Edit Host…").stackedButtonLabel(stacked)
            }
        }
    }
}

/// SFTP asking the host window for something about a host: a terminal tab
/// on it, or its editor. An object rather than a bare id, so that one host
/// window takes it and any other leaves it.
@MainActor
final class HostRequest {
    enum Wanted { case terminal, editor }

    let hostID: String
    let wanted: Wanted
    var taken = false

    init(hostID: String, wanted: Wanted) {
        self.hostID = hostID
        self.wanted = wanted
    }

    static func post(_ wanted: Wanted, for host: Host) {
        NotificationCenter.default.post(
            name: .shellhandHostRequest, object: HostRequest(hostID: host.id, wanted: wanted))
    }
}

extension Notification.Name {
    /// SFTP's Open in Terminal and Edit Host…, which the host window answers.
    static let shellhandHostRequest = Notification.Name("shellhand.hostRequest")
}

private struct TransfersStrip: View {
    let files: FilesModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Transfers").font(.caption.bold())
                // What is moving, what is waiting its turn, and what broke —
                // the answer to "has it hung?" without reading every row.
                Text(TransferQueue.summary(files.transfers))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear finished") { files.clearFinished() }
                    .controlSize(.small)
                    .disabled(!files.transfers.contains(where: \.finished))
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            List(files.transfers) { transfer in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(transfer.name)
                            .lineLimit(1)
                            .foregroundStyle(transfer.waiting ? .secondary : .primary)
                        // Which way and where to: with a host open on each
                        // side, a name and a bar did not say.
                        let route = TransferQueue.route(transfer)
                        if !route.isEmpty {
                            Text(route)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(minWidth: 140, maxWidth: 320, alignment: .leading)
                    // A queued transfer has no progress to show, and a bar
                    // sitting at nought reads as one that is stuck.
                    if transfer.waiting {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: 220, alignment: .leading)
                    } else if transfer.moving || transfer.state == TransferQueue.done {
                        // Full once done: a copy on this disk has no byte
                        // count, and its finished row sat at nought.
                        ProgressView(value: transfer.moving ? transfer.fraction : 1)
                            .frame(maxWidth: 220)
                    } else {
                        // Failed or stopped: the words say it, and a bar at
                        // nought reads as stuck.
                        SwiftUI.Color.clear.frame(maxWidth: 220, maxHeight: 4)
                    }
                    Text(describe(transfer))
                        .font(.caption2)
                        .foregroundStyle(
                            transfer.state == TransferQueue.failed ? .red : .secondary)
                    Spacer()
                    // Another go, where the sessions it went through are
                    // still the panes' own.
                    if files.canRetry(transfer) {
                        Button("Retry") { Task { await files.retry(transfer) } }
                            .controlSize(.small)
                    }
                    if !transfer.finished {
                        Button(transfer.waiting ? "Remove" : "Stop") { files.cancel(transfer) }
                            .controlSize(.small)
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 130)
        }
    }

    private func describe(_ transfer: Transfer) -> String {
        switch transfer.state {
        case TransferQueue.queued: "waiting its turn"
        case TransferQueue.running:
            "\(transfer.done.formatted(.byteCount(style: .file))) of "
                + transfer.total.formatted(.byteCount(style: .file))
        case TransferQueue.done: "done"
        case TransferQueue.cancelled: "stopped"
        default: transfer.error.isEmpty ? transfer.state : "failed: " + transfer.error
        }
    }
}
