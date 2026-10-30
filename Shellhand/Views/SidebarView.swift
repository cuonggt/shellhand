import SwiftUI
import UniformTypeIdentifiers

/// Hosts in their groups: a group's own settings
/// reach everything beneath it, so the tree is the point rather than
/// decoration.
///
/// The tree is flattened into rows here rather than built from nested
/// `DisclosureGroup`s, and a search shows the same rows with the groups left
/// out. A `List` whose contents switch between two shapes — an outline one
/// moment, a flat section the next — keeps rows of the shape it has just left
/// and draws them over the new ones. That was the doubled text the sidebar
/// showed after filtering, and because the leftovers are real rows in the
/// table, they survived clearing the search and piled up with every search
/// after it. One `ForEach` over one array of rows leaves nothing to confuse:
/// filtering is then an ordinary row diff.
struct SidebarView: View {
    let store: HostStore
    @Binding var selection: Selection?
    @Binding var search: String
    /// The search field's focus, the window's to set: ⌘F with the hosts in
    /// front puts the keyboard here.
    var searchFocus: FocusState<Bool>.Binding
    /// The tags chosen in the bar. More than one narrows rather than widens:
    /// `web` and `eu` asks for the European web servers. The window holds
    /// them, so the host pane narrows to the same hosts as this list does.
    @Binding var chosenTags: Set<String>
    /// The same actions the menu bar uses, so right-clicking a row and
    /// reaching for the menu do the same thing — and do it once. A row is
    /// selected by the right-click before the menu is built, so these act on
    /// what was clicked.
    let actions: AppActions
    let onConnect: (Host) -> Void
    /// A click on a group row, which asks for the list even when that group
    /// was already selected — the one way back once a tab has taken the pane.
    let onBrowse: (Selection) -> Void
    /// Whether the pane is showing the whole list, so its row can say so.
    let browsingAll: Bool
    let onBrowseAll: () -> Void
    /// The groups folded away. Absent means open, so a group that arrives
    /// while the window is up shows what is in it — and so that the fold
    /// state of a group nobody has touched is one fact, not two.
    @State private var collapsed: Set<String> = []
    /// Whether the first load has been folded away yet. The window opens on
    /// the groups rather than on every host in them: a few hundred hosts is
    /// a scroll, and the groups are how the list is meant to be read.
    ///
    /// Once only, so folding one open by hand is not undone by the next
    /// refresh, and so a group made later still arrives open.
    @State private var foldedFirstLoad = false
    /// The tag being renamed, and what to.
    @State private var renaming: String?
    @State private var renamedTo = ""
    /// The tag whose Delete is being asked about.
    @State private var deletingTag: String?
    /// What a row is being dragged over, so it can say so before the drop.
    @State private var dropTarget: String?

    var body: some View {
        let found = filtering ? matches : []
        List(selection: $selection) {
            ForEach(rows(matching: found)) { row in
                view(of: row)
            }
        }
        .onClickedRow(clicked(row:))
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                searchField
                allHosts
            }
        }
        .safeAreaInset(edge: .bottom) { tagBar }
        // Folded away as the list arrives, once. `.task` would be too early
        // — the store is still loading and there are no groups to fold.
        .onChange(of: store.snapshot.groups) { _, groups in
            guard !foldedFirstLoad, !groups.isEmpty else { return }
            foldedFirstLoad = true
            collapsed = store.tree.folded(keepingVisible: ancestry(of: selection))
        }
        // **Whatever is selected stays visible.** The selection restored at
        // launch arrives *after* the groups do — `ContentView` waits for the
        // store before putting it back — so folding alone would hide it, and
        // the window would name a host the list could not show. Opening its
        // ancestors here catches that, and anything else that selects into a
        // folded group later.
        //
        // Only ever opens. Folding a group whose host is selected is left
        // alone, because the selection has not changed and this does not run.
        .onChange(of: selection) { _, now in
            collapsed.subtract(ancestry(of: now))
        }
        .onKeyPress(.leftArrow) { fold(true) }
        .onKeyPress(.rightArrow) { fold(false) }
        // Escape clears the selection, which is how you get back to the whole
        // list. Ignored when nothing is picked, so the search field keeps its
        // own Escape — clearing what you typed is what it means there.
        .onKeyPress(.escape) {
            guard selection != nil else { return .ignored }
            selection = nil
            return .handled
        }
        .contextMenu(forSelectionType: Selection.self) { items in
            rowMenu(for: items.first)
        } primaryAction: { items in
            switch items.first {
            case let .host(id):
                if let host = store.snapshot.hosts.first(where: { $0.id == id }) {
                    onConnect(host)
                }
            case let .group(id):
                toggle(id)
            case nil:
                break
            }
        }
        .overlay {
            if store.snapshot.hosts.isEmpty && !store.loading {
                // Quiet on purpose: the detail pane beside it is showing the
                // welcome, and two panels both saying "no hosts yet" with
                // their own buttons read as a stutter.
                ContentUnavailableView {
                    Label("No hosts yet", systemImage: "tray")
                }
            } else if filtering && found.isEmpty {
                noMatches
            }
        }
    }

    /// The host list's own search, drawn here rather than with `.searchable`.
    ///
    /// With `placement: .sidebar` the system hoists the field to the very top
    /// of the column, outside the list it belongs to. `.searchable` goes where
    /// it likes rather than where you put it, which is why a plain field is
    /// what works here.
    /// The way back to the whole list, which there was none of: once a group
    /// was open, nothing led to every host again short of picking one filed
    /// nowhere. A button rather than a row of the list, so that it is not one
    /// more thing the selection could be.
    private var allHosts: some View {
        Button(action: onBrowseAll) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("All Hosts")
                Spacer()
                Text("\(store.snapshot.hosts.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                browsingAll ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .accessibilityLabel("All Hosts, \(Browsing.counted(store.snapshot.hosts.count))")
        .accessibilityAddTraits(browsingAll ? .isSelected : [])
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Name, address or tag", text: $search)
                .textFieldStyle(.plain)
                .focused(searchFocus)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    /// What right-clicking a row offers. Nothing clicked is the empty space
    /// below the list, where the only sensible answers are new ones.
    @ViewBuilder
    /// The row's own menu, shared with the pane so the two cannot drift —
    /// `Views/RowMenu.swift`.
    private func rowMenu(for item: Selection?) -> some View {
        RowMenu(item: item, store: store, actions: actions, onConnect: onConnect)
    }

    private var filtering: Bool { !search.isEmpty || !chosenTags.isEmpty }

    private var matches: [Host] {
        SidebarRows.matches(in: store.snapshot.hosts, search: search, tags: chosenTags)
    }

    // MARK: the rows

    /// `SidebarRow` under its old name, so the rest of this file reads as it
    /// did. The type and the building of it are in `SidebarRows`, where they
    /// can be checked without a window.
    private typealias Row = SidebarRow

    /// The whole sidebar as a flat list: the tree walked in order when
    /// nothing is being searched for, the matches when something is.
    private func rows(matching found: [Host]) -> [Row] {
        SidebarRows.build(
            tree: store.tree, collapsed: collapsed, matching: filtering ? found : nil)
    }

    /// What a click on the list meant, worked out from where it landed.
    ///
    /// Empty space clears the selection. A row that is **already** selected
    /// writes nothing through the `List`'s binding, so a repeat click on one
    /// is invisible to `onChange` — and a repeat click on a group is exactly
    /// how you ask for the list back after a tab has taken the pane. So the
    /// group's case is reported from here instead.
    ///
    /// A host is deliberately left alone: clicking the host you are already
    /// on, with its session in front, must not throw you back to the list.
    /// Where a host click really does move the selection, the `onChange` in
    /// `ContentView` sees it and does the right thing.
    private func clicked(row index: Int) {
        guard index >= 0 else {
            selection = nil
            return
        }
        // Worked out here rather than handed in. The monitor's closure is made
        // **once**, so a `[Row]` passed to it would be the array as it was at
        // the first draw — wrong after a group is folded, a host is added or a
        // word is typed into the search field. `filtering`, `matches` and
        // `store` all read through live storage, so asking again is current.
        let rows = rows(matching: filtering ? matches : [])
        guard index < rows.count, case let .group(group, _) = rows[index].kind else { return }
        onBrowse(.group(group.id))
    }

    /// The groups that have to be open for something to be visible: the one
    /// it is filed in and everything above that.
    ///
    /// A group's own fold is its business — what matters is that the row can
    /// be reached — so for a selected group this opens its parents and not
    /// the group itself.
    private func ancestry(of selection: Selection?) -> Set<String> {
        switch selection {
        case let .host(id): store.tree.ancestry(ofHost: id)
        case let .group(id): store.tree.ancestry(ofGroup: id)
        case nil: []
        }
    }

    @ViewBuilder
    private func view(of row: Row) -> some View {
        switch row.kind {
        case let .header(title):
            let header = Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .selectionDisabled()
            // "Ungrouped" is a place a host can be put, so it takes a drop
            // and is how a host is taken out of a group by hand. "Matching"
            // is a label over search results and is not anywhere.
            if row.id == "label:ungrouped" {
                header
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .background(highlight(row.id))
                    .dropDestination(for: ListItem.self) { items, _ in
                        accept(items, into: "")
                    } isTargeted: { over(row.id, $0) }
            } else {
                header
            }
        case let .group(group, expanded):
            GroupRow(group: group, expanded: expanded) { toggle(group.id) }
                .padding(.leading, indent(row.depth))
                .tag(Selection.group(group.id))
                .background(highlight(group.id))
                .draggable(ListItem(kind: .group, id: group.id))
                .dropDestination(for: ListItem.self) { items, _ in
                    accept(items, into: group.id)
                } isTargeted: { over(group.id, $0) }
        case let .host(host, showPath):
            HostRow(store: store, host: host, showGroup: showPath, chosen: chosenTags)
                .padding(.leading, indent(row.depth) + 16)
                .tag(Selection.host(host.id))
                .draggable(ListItem(kind: .host, id: host.id))
        }
    }

    /// Says where a drop would land, while the drag is still in the air.
    @ViewBuilder
    private func highlight(_ id: String) -> some View {
        if dropTarget == id {
            RoundedRectangle(cornerRadius: 5).fill(.tint.opacity(0.2))
        }
    }

    private func over(_ id: String, _ targeted: Bool) {
        if targeted {
            dropTarget = id
        } else if dropTarget == id {
            dropTarget = nil
        }
    }

    /// Takes what was dropped on a group — or on "Ungrouped", whose id is the
    /// empty string, the same one the store uses for a host in no group.
    ///
    /// A group dropped into itself or into something already beneath it is
    /// refused by the store rather than checked here, so the one rule about
    /// loops lives in one place.
    private func accept(_ items: [ListItem], into groupId: String) -> Bool {
        var took = false
        for item in items {
            switch item.kind {
            case .host:
                guard let host = store.snapshot.hosts.first(where: { $0.id == item.id })
                else { continue }
                took = true
                Task { await store.move(host: host, toGroup: groupId) }
            case .group:
                guard let group = store.snapshot.groups.first(where: { $0.id == item.id })
                else { continue }
                took = true
                Task { await store.move(group: group, toParent: groupId) }
            }
        }
        dropTarget = nil
        return took
    }

    /// Enough that the nesting reads, little enough that a deep tree still
    /// leaves room for a name.
    private func indent(_ depth: Int) -> CGFloat { CGFloat(depth) * 14 }

    // MARK: folding

    private func toggle(_ id: String) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
    }

    /// Left and right on a selected group, as an outline would do it.
    private func fold(_ shut: Bool) -> KeyPress.Result {
        guard case let .group(id) = selection, !filtering else { return .ignored }
        if shut == collapsed.contains(id) { return .ignored }
        toggle(id)
        return .handled
    }

    // MARK: the rest of the sidebar

    @ViewBuilder
    private var noMatches: some View {
        if search.isEmpty, !chosenTags.isEmpty {
            let named = chosenTags.sorted().joined(separator: " and ")
            ContentUnavailableView {
                Label("Nothing tagged \(named)", systemImage: "tag")
            } description: {
                Text(chosenTags.count == 1
                    ? "No host carries this tag."
                    : "No host carries all of these at once.")
            } actions: {
                Button("Clear Tags") { chosenTags = [] }
            }
        } else {
            ContentUnavailableView.search(text: search)
        }
    }

    /// The tags in use, as chips along the bottom.
    ///
    /// Several can be on at once and they narrow together, so the bar is a
    /// filter rather than a switch. There is no list of tags anywhere else —
    /// a tag exists because a host carries it — so renaming and deleting one
    /// belong here, on the chip, rather than in a window of their own.
    @ViewBuilder
    private var tagBar: some View {
        let tags = store.allTags
        if !tags.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                // Wrapped onto as many rows as they need. A row that scrolled
                // sideways clipped mid-word — "we" — with nothing to say
                // there were more.
                TagFlow(spacing: 6) {
                    ForEach(tags, id: \.self) { name in
                        chip(name)
                    }
                }
                .padding(.vertical, 6)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

                if !chosenTags.isEmpty {
                    Button {
                        chosenTags = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Show every host again")
                    .help("Show every host again")
                    .padding(.trailing, 10)
                    .padding(.top, 7)
                }
            }
            .background(.bar)
            .alert("Rename tag", isPresented: Binding(
                get: { renaming != nil },
                set: { shown in if !shown { renaming = nil } }
            )) {
                TextField("Tag", text: $renamedTo)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") {
                    guard let was = renaming, Tags.problem(withTag: renamedTo) == nil
                    else { renaming = nil; return }
                    Task {
                        await store.rename(tag: was, to: renamedTo)
                        // The chip that was chosen is gone by that name.
                        if chosenTags.remove(was) != nil,
                           let now = Tags.clean(renamedTo).first {
                            chosenTags.insert(now)
                        }
                        renaming = nil
                    }
                }
                .disabled(Tags.problem(withTag: renamedTo) != nil)
            } message: {
                Text(renaming.map { was in
                    "Every host tagged \(was) is retagged. Renaming onto a tag that "
                        + "already exists merges the two."
                } ?? "")
            }
            // Asked, with how many hosts it comes off, where it went from
            // every host at once without a word.
            .confirmationDialog(
                deletingTag.map { "Delete the tag \($0)?" } ?? "",
                isPresented: Binding(
                    get: { deletingTag != nil },
                    set: { shown in if !shown { deletingTag = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let name = deletingTag else { return }
                    deletingTag = nil
                    Task {
                        await store.delete(tag: name)
                        chosenTags.remove(name)
                    }
                }
                Button("Cancel", role: .cancel) { deletingTag = nil }
            } message: {
                Text(deletingTag.map {
                    Tags.deletionWarning($0, carriedBy: Tags.removing($0, from: store.snapshot.hosts).count)
                } ?? "")
            }
        }
    }

    private func chip(_ name: String) -> some View {
        let on = chosenTags.contains(name)
        return Button {
            if on { chosenTags.remove(name) } else { chosenTags.insert(name) }
        } label: {
            Text(name)
                .font(.caption)
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    on ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    in: Capsule())
        }
        .buttonStyle(.plain)
        .help(on ? "Stop narrowing by \(name)" : "Show only hosts tagged \(name)")
        .contextMenu {
            Button("Rename \(name)…") {
                renamedTo = name
                renaming = name
            }
            Button("Delete \(name)…", role: .destructive) { deletingTag = name }
        }
    }
}

/// A group, with the triangle that folds it. The triangle is its own button so
/// that clicking it folds without also selecting, which is how an outline
/// behaves.
struct GroupRow: View {
    let group: Group
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse \(group.name)" : "Expand \(group.name)")

            Label {
                HStack(spacing: 6) {
                    Text(group.name)
                    if !group.user.isEmpty {
                        Text(group.user)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "folder")
            }
        }
    }
}

struct HostRow: View {
    let store: HostStore
    let host: Host
    let showGroup: Bool
    /// The tags the bar is narrowing by, so the ones being filtered on stand
    /// out from the rest on the row.
    var chosen: Set<String> = []

    /// Enough to tell machines apart at a glance; past that the row is taller
    /// than it is useful and the rest are a search away.
    private static let shown = 3

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(host.name)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !host.tags.isEmpty { tags }
            }
        } icon: {
            HostIcon(os: host.os, named: host.osLabel)
        }
    }

    /// Under the name, which is where Termius puts them and where they read
    /// as belonging to the host rather than to the list.
    private var tags: some View {
        HStack(spacing: 3) {
            ForEach(host.tags.prefix(Self.shown), id: \.self) { tag in
                let on = chosen.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                Text(tag)
                    .font(.system(size: 9))
                    .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        on ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary),
                        in: Capsule())
            }
            if host.tags.count > Self.shown {
                Text("+\(host.tags.count - Self.shown)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 1)
    }

    private var subtitle: String {
        var parts = [host.destinationLine]
        if showGroup, let group = store.group(host.groupId) { parts.append("· \(store.path(of: group))") }
        return parts.joined(separator: " ")
    }
}

/// A row on its way to somewhere else.
///
/// A type of its own rather than a plain string, so that text dragged in from
/// another app is not mistaken for a host, and so a group and a host can be
/// told apart at the far end.
nonisolated struct ListItem: Codable, Transferable {
    enum Kind: String, Codable { case host, group }
    var kind: Kind
    var id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .shellhandListItem)
    }
}

nonisolated extension UTType {
    static let shellhandListItem = UTType(exportedAs: "com.shellhand.list-item")
}

// MARK: clicking the list

/// Where a click in the sidebar landed: the row's index, or -1 for the empty
/// space below the rows.
///
/// Two things need this, and neither can be had from the `List` itself.
/// Clicking the empty space clears the selection, the way a Finder window
/// does. And clicking a **row that is already selected** writes nothing
/// through `List(selection:)` — the value does not change, so no `onChange`
/// fires — yet it still means "show me that", which is the one way back to
/// the list once a tab has taken the pane.
///
/// This has to be done in AppKit. A `List` on macOS is an `NSTableView` in an
/// `NSScrollView`, and a click on the space below the rows is handled there —
/// it never reaches SwiftUI's gesture system, so `.onTapGesture` on the List
/// never fires at all. `.simultaneousGesture` and `.highPriorityGesture` do
/// fire, but on the rows as well, so a click would select and then clear in
/// the same breath. That was tried first and it does nothing; this is why.
///
/// So: find the table the List is, and watch for a left mouse down inside it.
/// `NSTableView.row(at:)` answers the row under a point, and -1 for a point on
/// no row — no hit-testing of our own. The search field and the tag bar are
/// outside the table's bounds, and every other list in the app is a different
/// table, so neither needs excluding by hand.
///
/// This arrives on **mouse down**, before the `List` has moved its selection,
/// so whatever reads it must hold for the click that follows — and an
/// `onChange(of:)` on the selection, which lands after, has the last word
/// where the selection really did change.
private struct ClickedRow: ViewModifier {
    let clicked: (Int) -> Void
    /// A box rather than `@State` on its own: the monitor's closure is made
    /// once and has to see the table whenever it is found, which is after.
    @State private var box = TableBox()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .background(TableFinder(box: box))
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                    guard let table = box.table, event.window === table.window else { return event }
                    let point = table.convert(event.locationInWindow, from: nil)
                    if table.bounds.contains(point) { clicked(table.row(at: point)) }
                    // Always handed back: this watches, it does not swallow.
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

@MainActor private final class TableBox {
    var table: NSTableView?
}

/// The `NSTableView` a `List` is, found from a view put behind it.
private struct TableFinder: NSViewRepresentable {
    let box: TableBox

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        // Also when the one held has lost its window: SwiftUI can make the
        // List again, and a table kept from the old one would leave this
        // quietly doing nothing rather than noisily wrong.
        guard box.table?.window == nil else { return }
        // Next turn of the loop: while the background is being made the List
        // is not in the hierarchy yet, so there is nothing to find.
        DispatchQueue.main.async {
            var ancestor = view.superview
            while let here = ancestor {
                if let found = Self.table(in: here) {
                    box.table = found
                    return
                }
                ancestor = here.superview
            }
        }
    }

    /// The first table in a subtree, breadth first. The nearest ancestor that
    /// holds a table at all is inside the sidebar, so the first one found is
    /// the sidebar's and not a file pane's.
    private static func table(in view: NSView) -> NSTableView? {
        var queue = view.subviews
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let table = next as? NSTableView { return table }
            queue.append(contentsOf: next.subviews)
        }
        return nil
    }
}

extension View {
    /// Hands back the index of the sidebar row a click landed on, or -1 for
    /// the empty space below them.
    func onClickedRow(_ clicked: @escaping (Int) -> Void) -> some View {
        modifier(ClickedRow(clicked: clicked))
    }
}

/// Chips in rows, as many to a row as fit and the rest wrapping below: the
/// tag bar scrolled sideways and clipped mid-word, with nothing to say that
/// there were more.
struct TagFlow: Layout {
    var spacing: CGFloat = 6

    /// Which items go on which row, given each one's width and the room
    /// there is — the whole of the wrapping, apart from the layout so a test
    /// can hold it still. An item wider than the room has a row to itself.
    nonisolated static func rows(_ widths: [CGFloat], spacing: CGFloat, room: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var row: [Int] = []
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let wanted = row.isEmpty ? width : used + spacing + width
            if !row.isEmpty, wanted > room {
                rows.append(row)
                row = [index]
                used = width
            } else {
                row.append(index)
                used = wanted
            }
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(sizes.map(\.width), spacing: spacing, room: proposal.width ?? .infinity)
        let heights = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }
        let widths = rows.map { row in
            row.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(max(0, row.count - 1))
        }
        return CGSize(
            width: proposal.width ?? (widths.max() ?? 0),
            height: heights.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in Self.rows(sizes.map(\.width), spacing: spacing, room: bounds.width) {
            var x = bounds.minX
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += (row.map { sizes[$0].height }.max() ?? 0) + spacing
        }
    }
}
