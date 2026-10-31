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
            table
            Divider()
            footer
        }
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
        }
        .alert("New folder", isPresented: $newFolder) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task { await place.makeDirectory(named: name) } }
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
                .textSelection(.enabled)
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
            }

            HStack(spacing: 4) {
                Button { Task { await place.parent() } } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Up one directory")
                .help("Up one directory")
                .disabled(place.listing.path.isEmpty)

                // Typing a path beats walking to it, which is the whole of
                // what this field is for. Enter goes there.
                TextField("Path", text: $typedPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { Task { await place.go(to: typedPath) } }
                    .onChange(of: place.listing.path) { _, now in typedPath = now }
                    .onAppear { typedPath = place.listing.path }

                Button {
                    name = ""
                    newFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("New Folder")
                .help("New Folder")
                .keyboardShortcut(isActive ? KeyboardShortcut("n", modifiers: [.command, .shift]) : nil)
                .disabled(place.listing.path.isEmpty)

                Button { Task { await place.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
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
            .width(min: 70, ideal: 80)
            TableColumn("Modified", value: \.modTime) { entry in
                Text(entry.modTime).foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 130)
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
        // ⌫ asks first, through the same question as the menu's Delete.
        .onDeleteCommand { if !selection.isEmpty { confirmingDelete = true } }
        // Space, as in Finder: a look at the file picked, on this Mac. A file
        // on a host would have to be fetched first.
        .onKeyPress(.space) {
            guard place.isLocal, chosen.count == 1, let entry = chosen.first else { return .ignored }
            QuickLook.shared.show(place.localURL(named: entry.name))
            return .handled
        }
        // A folder opened takes its selection with it: kept, the folder you
        // went into stayed selected inside itself — "1 of 0 selected", and a
        // Copy button live with nothing to copy.
        .onChange(of: place.listing.path) { _, _ in selection = [] }
        .overlay { if place.listing.path.isEmpty { waiting } }
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
            Unreached(host: host, said: failure, trouble: Places.trouble(failure, on: host.name)) {
                Task { await place.tryAgain() }
            }
        } else if let failure = place.failure {
            ContentUnavailableView {
                Label("Cannot show this", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            }
        } else {
            // Only the far side is ever unpointed — this Mac is always the
            // near one — so this asks for a host rather than for "a place",
            // which is what its own header above it says too.
            ContentUnavailableView {
                Label("Pick a host", systemImage: "server.rack")
            } description: {
                Text("Choose one above to see its files beside your own.")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Copy to \(other.title)") {
                let going = chosen
                Task { await files.copy(going, from: place, to: other) }
            }
            .controlSize(.small)
            .disabled(chosen.isEmpty || other.listing.path.isEmpty)

            Spacer()
            Text(count).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
    }

    @ViewBuilder
    private func menu(for names: Set<String>) -> some View {
        let picked = entries.filter { names.contains($0.name) }
        if !picked.isEmpty {
            Button("Copy to \(other.title)") {
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

    /// Double-click: into a directory, or across to the other pane.
    private func open(_ names: Set<String>) {
        let picked = entries.filter { names.contains($0.name) }
        if picked.count == 1, let entry = picked.first, entry.isDir {
            Task { await place.go(to: place.path(entry.name)) }
            return
        }
        Task { await files.copy(picked, from: place, to: other) }
    }

    private var count: String {
        var said = chosen.isEmpty
            ? (entries.count == 1 ? "1 item" : "\(entries.count) items")
            : "\(chosen.count) of \(entries.count) selected"
        if !place.showHidden, place.hiddenCount > 0 { said += " · \(place.hiddenCount) hidden" }
        return said
    }
}

/// A host SFTP could not open, said as what it means and what to do about it:
/// a terminal tab, where a new key's question and a password can be
/// answered, and another go. It said "Cannot show this" over ssh's sentence.
private struct Unreached: View {
    let host: Host
    let said: String
    let trouble: Places.Trouble
    let onTryAgain: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(trouble.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if !trouble.advice.isEmpty {
                Text(trouble.advice)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(said)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            HStack {
                if trouble.offersTerminal {
                    Button("Open in Terminal") { TerminalRequest.post(for: host) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Try Again", action: onTryAgain)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 460)
    }
}

/// SFTP asking the host window for a terminal tab on a host. An object rather
/// than a bare id, so that one host window takes it and any other leaves it.
@MainActor
final class TerminalRequest {
    let hostID: String
    var taken = false

    init(hostID: String) { self.hostID = hostID }

    static func post(for host: Host) {
        NotificationCenter.default.post(
            name: .shellhandOpenTerminal, object: TerminalRequest(hostID: host.id))
    }
}

extension Notification.Name {
    /// SFTP's Open in Terminal, which the host window answers.
    static let shellhandOpenTerminal = Notification.Name("shellhand.openTerminal")
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
